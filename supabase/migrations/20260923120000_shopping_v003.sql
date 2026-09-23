-- Domov+ V0.0.3: one online shopping list per household.
alter table public.households
  add column if not exists timezone text not null default 'Europe/Prague';

create or replace function public.validate_household_timezone()
returns trigger language plpgsql set search_path = public, pg_catalog as $$
begin
  if not exists (select 1 from pg_timezone_names where name = new.timezone) then
    raise exception 'invalid_household_timezone';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_household_timezone on public.households;
create trigger validate_household_timezone before insert or update of timezone on public.households
for each row execute function public.validate_household_timezone();

alter table public.household_audit_log drop constraint if exists household_audit_log_event_type_check;
alter table public.household_audit_log add constraint household_audit_log_event_type_check check (event_type in (
  'household_created','invitation_created','invitation_accepted','invitation_declined',
  'invitation_cancelled','household_name_changed','shopping_item_added',
  'shopping_item_renamed','shopping_item_bought','shopping_item_restored',
  'shopping_item_deleted','shopping_item_delete_undone'
));

create table if not exists public.shopping_items (
  id uuid primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120 and name = btrim(name)),
  status text not null default 'active' check (status in ('active','bought')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0),
  bought_by uuid references public.profiles(id),
  bought_at timestamptz,
  deleted_by uuid references public.profiles(id),
  deleted_at timestamptz,
  constraint shopping_items_bought_fields check (
    (status = 'active' and bought_by is null and bought_at is null) or
    (status = 'bought' and bought_by is not null and bought_at is not null)
  ),
  constraint shopping_items_deleted_fields check (
    (deleted_at is null and deleted_by is null) or
    (deleted_at is not null and deleted_by is not null)
  )
);

create unique index if not exists shopping_items_one_active_name
  on public.shopping_items (household_id, lower(name))
  where status = 'active' and deleted_at is null;
create index if not exists shopping_items_household_recent
  on public.shopping_items (household_id, created_at desc);
alter table public.shopping_items replica identity full;
alter table public.shopping_items enable row level security;

drop policy if exists "Members can read household shopping items" on public.shopping_items;
create policy "Members can read household shopping items" on public.shopping_items
for select to authenticated using (public.is_household_member(household_id));

revoke all on public.shopping_items from anon, authenticated;
grant select on public.shopping_items to authenticated;

do $$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'shopping_items'
  ) then alter publication supabase_realtime add table public.shopping_items; end if;
end $$;

create or replace function public.shopping_error_for_unique() returns void
language plpgsql set search_path = public, pg_catalog as $$
begin raise exception 'active_shopping_item_exists' using errcode = 'P0001'; end;
$$;

create or replace function public.add_shopping_item(p_household_id uuid, p_id uuid, p_name text)
returns public.shopping_items language plpgsql security definer set search_path = public, pg_catalog as $$
declare v_user uuid := auth.uid(); v_name text := btrim(p_name); v_item public.shopping_items;
begin
  if v_user is null or not public.is_household_member(p_household_id) then raise exception 'not_household_member'; end if;
  if p_id is null then raise exception 'invalid_shopping_item_id'; end if;
  if char_length(v_name) not between 1 and 120 then raise exception 'invalid_shopping_item_name'; end if;
  begin
    insert into public.shopping_items(id,household_id,name,created_by)
    values(p_id,p_household_id,v_name,v_user) returning * into v_item;
  exception when unique_violation then perform public.shopping_error_for_unique(); end;
  insert into public.household_audit_log(household_id,event_type,actor_user_id,metadata)
  values(p_household_id,'shopping_item_added',v_user,jsonb_build_object('item_id',p_id,'name',v_name));
  return v_item;
end; $$;

create or replace function public.rename_shopping_item(p_item_id uuid, p_name text, p_expected_version bigint)
returns public.shopping_items language plpgsql security definer set search_path = public, pg_catalog as $$
declare v_user uuid := auth.uid(); v_name text := btrim(p_name); v_item public.shopping_items; v_old text;
begin
  if char_length(v_name) not between 1 and 120 then raise exception 'invalid_shopping_item_name'; end if;
  select name into v_old from public.shopping_items where id=p_item_id and deleted_at is null and status='active'
    and version=p_expected_version and public.is_household_member(household_id) for update;
  if not found then raise exception 'shopping_item_not_available'; end if;
  begin update public.shopping_items set name=v_name,updated_at=now(),version=version+1 where id=p_item_id returning * into v_item;
  exception when unique_violation then perform public.shopping_error_for_unique(); end;
  insert into public.household_audit_log(household_id,event_type,actor_user_id,metadata)
  values(v_item.household_id,'shopping_item_renamed',v_user,jsonb_build_object('item_id',p_item_id,'old_name',v_old,'name',v_name));
  return v_item;
end; $$;

create or replace function public.mark_shopping_item_bought(p_item_id uuid, p_expected_version bigint)
returns public.shopping_items language plpgsql security definer set search_path = public, pg_catalog as $$
declare v_user uuid := auth.uid(); v_item public.shopping_items;
begin
  update public.shopping_items set status='bought',bought_by=v_user,bought_at=now(),updated_at=now(),version=version+1
  where id=p_item_id and status='active' and deleted_at is null and version=p_expected_version
    and public.is_household_member(household_id) returning * into v_item;
  if not found then raise exception 'shopping_item_not_available'; end if;
  insert into public.household_audit_log(household_id,event_type,actor_user_id,metadata)
  values(v_item.household_id,'shopping_item_bought',v_user,jsonb_build_object('item_id',p_item_id,'name',v_item.name));
  return v_item;
end; $$;

create or replace function public.restore_shopping_item(p_item_id uuid, p_expected_version bigint)
returns public.shopping_items language plpgsql security definer set search_path = public, pg_catalog as $$
declare v_user uuid := auth.uid(); v_item public.shopping_items;
begin
  begin
    update public.shopping_items set status='active',bought_by=null,bought_at=null,updated_at=now(),version=version+1
    where id=p_item_id and status='bought' and deleted_at is null and version=p_expected_version
      and public.is_household_member(household_id) returning * into v_item;
  exception when unique_violation then perform public.shopping_error_for_unique(); end;
  if v_item.id is null then raise exception 'shopping_item_not_available'; end if;
  insert into public.household_audit_log(household_id,event_type,actor_user_id,metadata)
  values(v_item.household_id,'shopping_item_restored',v_user,jsonb_build_object('item_id',p_item_id,'name',v_item.name));
  return v_item;
end; $$;

create or replace function public.delete_shopping_item(p_item_id uuid, p_expected_version bigint)
returns public.shopping_items language plpgsql security definer set search_path = public, pg_catalog as $$
declare v_user uuid := auth.uid(); v_item public.shopping_items;
begin
  update public.shopping_items set deleted_by=v_user,deleted_at=now(),updated_at=now(),version=version+1
  where id=p_item_id and status='active' and deleted_at is null and version=p_expected_version
    and public.is_household_member(household_id) returning * into v_item;
  if not found then raise exception 'shopping_item_not_available'; end if;
  insert into public.household_audit_log(household_id,event_type,actor_user_id,metadata)
  values(v_item.household_id,'shopping_item_deleted',v_user,jsonb_build_object('item_id',p_item_id,'name',v_item.name));
  return v_item;
end; $$;

create or replace function public.undo_delete_shopping_item(p_item_id uuid, p_expected_version bigint)
returns public.shopping_items language plpgsql security definer set search_path = public, pg_catalog as $$
declare v_user uuid := auth.uid(); v_item public.shopping_items;
begin
  begin
    update public.shopping_items set deleted_by=null,deleted_at=null,updated_at=now(),version=version+1
    where id=p_item_id and status='active' and deleted_at is not null and version=p_expected_version
      and public.is_household_member(household_id) returning * into v_item;
  exception when unique_violation then perform public.shopping_error_for_unique(); end;
  if v_item.id is null then raise exception 'shopping_item_not_available'; end if;
  insert into public.household_audit_log(household_id,event_type,actor_user_id,metadata)
  values(v_item.household_id,'shopping_item_delete_undone',v_user,jsonb_build_object('item_id',p_item_id,'name',v_item.name));
  return v_item;
end; $$;

revoke all on function public.add_shopping_item(uuid,uuid,text) from public;
revoke all on function public.rename_shopping_item(uuid,text,bigint) from public;
revoke all on function public.mark_shopping_item_bought(uuid,bigint) from public;
revoke all on function public.restore_shopping_item(uuid,bigint) from public;
revoke all on function public.delete_shopping_item(uuid,bigint) from public;
revoke all on function public.undo_delete_shopping_item(uuid,bigint) from public;
grant execute on function public.add_shopping_item(uuid,uuid,text) to authenticated;
grant execute on function public.rename_shopping_item(uuid,text,bigint) to authenticated;
grant execute on function public.mark_shopping_item_bought(uuid,bigint) to authenticated;
grant execute on function public.restore_shopping_item(uuid,bigint) to authenticated;
grant execute on function public.delete_shopping_item(uuid,bigint) to authenticated;
grant execute on function public.undo_delete_shopping_item(uuid,bigint) to authenticated;
