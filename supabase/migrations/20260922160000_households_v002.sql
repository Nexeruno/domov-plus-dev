create extension if not exists pgcrypto with schema extensions;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  current_household_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 80),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles
  add constraint profiles_current_household_fk
  foreign key (current_household_id) references public.households(id) on delete set null;

create table public.household_memberships (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner', 'member')),
  created_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create table public.household_invitations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  target_email text not null check (target_email = lower(trim(target_email))),
  invited_by uuid not null references public.profiles(id),
  token_hash text not null unique,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired', 'cancelled')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  responded_at timestamptz,
  constraint invitation_expiry_after_creation check (expires_at > created_at)
);

create unique index household_invitations_one_pending_email
  on public.household_invitations (household_id, target_email)
  where status = 'pending';

create table public.household_audit_log (
  id bigint generated always as identity primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  event_type text not null check (event_type in (
    'household_created', 'invitation_created', 'invitation_accepted',
    'invitation_declined', 'invitation_cancelled', 'household_name_changed'
  )),
  actor_user_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index household_memberships_user_id_idx on public.household_memberships(user_id);
create index household_invitations_household_idx on public.household_invitations(household_id, status);
create index household_audit_household_idx on public.household_audit_log(household_id, created_at desc);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), 'Uživatel'))
  on conflict (id) do update set display_name = excluded.display_name, updated_at = now();
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert or update of raw_user_meta_data on auth.users
  for each row execute function public.handle_new_user();

insert into public.profiles (id, display_name)
select id, coalesce(nullif(trim(raw_user_meta_data ->> 'display_name'), ''), 'Uživatel')
from auth.users
on conflict (id) do nothing;

create or replace function public.is_household_member(p_household_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer set search_path = ''
as $$
  select exists (
    select 1 from public.household_memberships
    where household_id = p_household_id and user_id = p_user_id
  );
$$;

create or replace function public.is_household_owner(p_household_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer set search_path = ''
as $$
  select exists (
    select 1 from public.household_memberships
    where household_id = p_household_id and user_id = p_user_id and role = 'owner'
  );
$$;

alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_memberships enable row level security;
alter table public.household_invitations enable row level security;
alter table public.household_audit_log enable row level security;

create policy profiles_read_self_or_household_members on public.profiles
for select to authenticated
using (
  id = auth.uid() or exists (
    select 1
    from public.household_memberships mine
    join public.household_memberships theirs using (household_id)
    where mine.user_id = auth.uid() and theirs.user_id = profiles.id
  )
);

create policy households_read_members on public.households
for select to authenticated using (public.is_household_member(id));

create policy memberships_read_household_members on public.household_memberships
for select to authenticated using (public.is_household_member(household_id));

create policy invitations_read_owners on public.household_invitations
for select to authenticated using (public.is_household_owner(household_id));

create policy audit_read_members on public.household_audit_log
for select to authenticated using (public.is_household_member(household_id));

create or replace function public.create_household(p_name text default 'Domov')
returns uuid
language plpgsql
security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_household uuid;
  v_name text := trim(p_name);
begin
  if v_user is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
  if char_length(v_name) < 1 or char_length(v_name) > 80 then raise exception using errcode = '22023', message = 'invalid_household_name'; end if;

  insert into public.households(name, created_by) values (v_name, v_user) returning id into v_household;
  insert into public.household_memberships(household_id, user_id, role) values (v_household, v_user, 'owner');
  update public.profiles set current_household_id = v_household, updated_at = now() where id = v_user;
  insert into public.household_audit_log(household_id, event_type, actor_user_id)
    values (v_household, 'household_created', v_user);
  return v_household;
end;
$$;

create or replace function public.rename_household(p_household_id uuid, p_name text)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare v_name text := trim(p_name);
begin
  if not public.is_household_owner(p_household_id) then raise exception using errcode = '42501', message = 'not_household_owner'; end if;
  if char_length(v_name) < 1 or char_length(v_name) > 80 then raise exception using errcode = '22023', message = 'invalid_household_name'; end if;
  update public.households set name = v_name, updated_at = now() where id = p_household_id;
  insert into public.household_audit_log(household_id, event_type, actor_user_id, metadata)
    values (p_household_id, 'household_name_changed', auth.uid(), jsonb_build_object('name', v_name));
end;
$$;

create or replace function public.create_household_invitation(p_household_id uuid, p_email text)
returns table(invitation_id uuid, invitation_token text, household_name text, inviter_name text)
language plpgsql
security definer set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_existing_user uuid;
begin
  if not public.is_household_owner(p_household_id) then raise exception using errcode = '42501', message = 'not_household_owner'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception using errcode = '22023', message = 'invalid_email'; end if;

  update public.household_invitations set status = 'expired', responded_at = now()
  where household_id = p_household_id and status = 'pending' and expires_at <= now();

  select id into v_existing_user from auth.users where lower(email) = v_email limit 1;
  if v_existing_user is not null and public.is_household_member(p_household_id, v_existing_user) then
    raise exception using errcode = '23505', message = 'already_household_member';
  end if;
  if exists(select 1 from public.household_invitations where household_id = p_household_id and target_email = v_email and status = 'pending') then
    raise exception using errcode = '23505', message = 'active_invitation_exists';
  end if;

  return query
  with inserted as (
    insert into public.household_invitations(household_id, target_email, invited_by, token_hash)
    values (p_household_id, v_email, auth.uid(), encode(extensions.digest(v_token, 'sha256'), 'hex'))
    returning id
  ), audited as (
    insert into public.household_audit_log(household_id, event_type, actor_user_id, metadata)
    values (p_household_id, 'invitation_created', auth.uid(), jsonb_build_object('target_email', v_email))
  )
  select inserted.id, v_token, h.name, p.display_name
  from inserted
  join public.households h on h.id = p_household_id
  join public.profiles p on p.id = auth.uid();
end;
$$;

create or replace function public.get_invitation_preview(p_token text)
returns table(household_name text, inviter_name text, target_email text, invitation_status text, expires_at timestamptz)
language plpgsql
security definer set search_path = ''
as $$
begin
  update public.household_invitations set status = 'expired', responded_at = now()
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and status = 'pending' and expires_at <= now();
  return query
  select h.name, p.display_name, i.target_email, i.status, i.expires_at
  from public.household_invitations i
  join public.households h on h.id = i.household_id
  join public.profiles p on p.id = i.invited_by
  where i.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');
end;
$$;

create or replace function public.respond_to_household_invitation(p_token text, p_accept boolean)
returns uuid
language plpgsql
security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_inv public.household_invitations%rowtype;
begin
  if v_user is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
  select * into v_inv from public.household_invitations
    where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') for update;
  if not found then raise exception using errcode = '22023', message = 'invitation_not_found'; end if;
  if v_inv.status <> 'pending' then raise exception using errcode = '22023', message = 'invitation_not_pending'; end if;
  if v_inv.expires_at <= now() then
    update public.household_invitations set status = 'expired', responded_at = now() where id = v_inv.id;
    raise exception using errcode = '22023', message = 'invitation_expired';
  end if;
  if v_email <> v_inv.target_email then raise exception using errcode = '42501', message = 'invitation_email_mismatch'; end if;

  if p_accept then
    if exists(select 1 from public.household_memberships where household_id = v_inv.household_id and user_id = v_user) then
      raise exception using errcode = '23505', message = 'already_household_member';
    end if;
    insert into public.household_memberships(household_id, user_id, role) values (v_inv.household_id, v_user, 'owner');
    update public.profiles set current_household_id = v_inv.household_id, updated_at = now() where id = v_user;
    update public.household_invitations set status = 'accepted', responded_at = now() where id = v_inv.id;
    insert into public.household_audit_log(household_id, event_type, actor_user_id)
      values (v_inv.household_id, 'invitation_accepted', v_user);
  else
    update public.household_invitations set status = 'declined', responded_at = now() where id = v_inv.id;
    insert into public.household_audit_log(household_id, event_type, actor_user_id)
      values (v_inv.household_id, 'invitation_declined', v_user);
  end if;
  return v_inv.household_id;
end;
$$;

create or replace function public.cancel_household_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare v_household uuid;
begin
  select household_id into v_household from public.household_invitations where id = p_invitation_id for update;
  if v_household is null then raise exception using errcode = '22023', message = 'invitation_not_found'; end if;
  if not public.is_household_owner(v_household) then raise exception using errcode = '42501', message = 'not_household_owner'; end if;
  update public.household_invitations set status = 'cancelled', responded_at = now()
    where id = p_invitation_id and status = 'pending';
  if not found then raise exception using errcode = '22023', message = 'invitation_not_pending'; end if;
  insert into public.household_audit_log(household_id, event_type, actor_user_id)
    values (v_household, 'invitation_cancelled', auth.uid());
end;
$$;

revoke all on function public.create_household(text) from public;
revoke all on function public.rename_household(uuid, text) from public;
revoke all on function public.create_household_invitation(uuid, text) from public;
revoke all on function public.get_invitation_preview(text) from public;
revoke all on function public.respond_to_household_invitation(text, boolean) from public;
revoke all on function public.cancel_household_invitation(uuid) from public;
grant execute on function public.create_household(text) to authenticated;
grant execute on function public.rename_household(uuid, text) to authenticated;
grant execute on function public.create_household_invitation(uuid, text) to authenticated;
grant execute on function public.get_invitation_preview(text) to anon, authenticated;
grant execute on function public.respond_to_household_invitation(text, boolean) to authenticated;
grant execute on function public.cancel_household_invitation(uuid) to authenticated;

revoke insert, update, delete on public.profiles from anon, authenticated;
revoke insert, update, delete on public.households from anon, authenticated;
revoke insert, update, delete on public.household_memberships from anon, authenticated;
revoke insert, update, delete on public.household_invitations from anon, authenticated;
revoke insert, update, delete on public.household_audit_log from anon, authenticated;
