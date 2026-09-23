-- V0.0.3 stability: helpers cannot probe another user's membership.
create or replace function public.is_household_member(p_household_id uuid, p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and p_user_id = auth.uid() and exists (
    select 1 from public.household_memberships
    where household_id = p_household_id and user_id = auth.uid()
  );
$$;

create or replace function public.is_household_owner(p_household_id uuid, p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and p_user_id = auth.uid() and exists (
    select 1 from public.household_memberships
    where household_id = p_household_id and user_id = auth.uid() and role = 'owner'
  );
$$;

-- Keep the existing invitation RPC and its signature. Check the invitee internally,
-- without invoking a public helper that can probe another user.
create or replace function public.create_household_invitation(p_household_id uuid, p_email text)
returns table(invitation_id uuid, invitation_token text, household_name text, inviter_name text)
language plpgsql security definer set search_path = '' as $$
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
  if v_existing_user is not null and exists (
    select 1 from public.household_memberships
    where household_id = p_household_id and user_id = v_existing_user
  ) then raise exception using errcode = '23505', message = 'already_household_member'; end if;
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

-- Filter on the server using the stored IANA zone. Local midnight bounds are
-- converted independently, so both 23-hour and 25-hour DST days work.
create or replace function public.list_current_shopping_items(p_household_id uuid)
returns setof public.shopping_items language plpgsql stable security definer set search_path = '' as $$
declare v_timezone text; v_today date;
begin
  if not public.is_household_member(p_household_id) then
    raise exception using errcode = '42501', message = 'not_household_member';
  end if;
  select timezone into v_timezone from public.households where id = p_household_id;
  v_today := (now() at time zone v_timezone)::date;
  return query
    select s.* from public.shopping_items s
    where s.household_id = p_household_id and s.deleted_at is null
      and (s.status = 'active' or (
        s.status = 'bought'
        and s.bought_at >= (v_today::timestamp at time zone v_timezone)
        and s.bought_at < ((v_today + 1)::timestamp at time zone v_timezone)
      ))
    order by s.created_at desc;
end;
$$;

create index if not exists shopping_items_bought_recent
  on public.shopping_items (household_id, bought_at)
  where status = 'bought' and deleted_at is null;

revoke all on function public.list_current_shopping_items(uuid) from public, anon;
grant execute on function public.list_current_shopping_items(uuid) to authenticated;
