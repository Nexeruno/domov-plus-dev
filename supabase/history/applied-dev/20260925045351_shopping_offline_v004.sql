-- Domov+ V0.0.4 DELTA ONLY; requires the deployed, stabilized V0.0.3 schema.
-- Submit this complete file as ONE apply_migration request, in the migration
-- tool's transaction. Do not replay V0.0.1-V0.0.3 files just because migration
-- history is empty. No BEGIN/COMMIT here: the migration runner owns atomicity.
-- One-time migration: existing V0.0.4 objects intentionally cause failure.
-- No changes to existing RPC bodies, RLS policies or Realtime publication.
do $preflight$
begin
  if pg_catalog.to_regclass('public.shopping_items') is null
    or pg_catalog.to_regclass('public.households') is null
    or pg_catalog.to_regclass('public.household_audit_log') is null then
    raise exception 'V0.0.3 baseline missing; do not replay old migrations automatically';
  end if;
  if not exists (select 1 from pg_catalog.pg_attribute
    where attrelid='public.shopping_items'::regclass and attname='version'
      and atttypid='bigint'::regtype and not attisdropped)
    or not exists (select 1 from pg_catalog.pg_attribute
    where attrelid='public.households'::regclass and attname='timezone' and not attisdropped)
    or pg_catalog.to_regprocedure('public.list_current_shopping_items(uuid)') is null
    or pg_catalog.to_regprocedure('extensions.digest(bytea,text)') is null then
    raise exception 'V0.0.3 version/timezone/RPC/pgcrypto prerequisite missing';
  end if;
  if pg_catalog.to_regclass('public.shopping_sync_operations') is not null
    or exists (select 1 from pg_catalog.pg_attribute
      where attrelid='public.households'::regclass and attname='shopping_revision' and not attisdropped) then
    raise exception 'V0.0.4 already present or partially applied; inspect before proceeding';
  end if;
end;
$preflight$;

-- V0.0.4: atomically apply and remember one authenticated shopping operation.
-- The legacy V0.0.3 RPCs remain available to previously installed clients.
-- These fields describe the most recent winning offline rename and delete.
-- Legacy online RPCs do not populate them; the name check below prevents an
-- old offline rename from winning over a later legacy rename.
alter table public.shopping_items
  add column last_rename_base_version bigint,
  add column last_rename_base_name text,
  add column last_rename_operation_id uuid,
  add column last_delete_operation_id uuid;

-- Conservative baseline: pre-migration state history is unknown.
alter table public.shopping_items add column last_status_change_version bigint;
update public.shopping_items set last_status_change_version=version;
alter table public.shopping_items alter column last_status_change_version set not null;

-- Revision is a server counter, never a device timestamp. Existing data is
-- the baseline at revision zero; its original pre-migration name is unknown.
alter table public.households add column shopping_revision bigint not null default 0 check (shopping_revision >= 0);
alter table public.shopping_items
  add column origin_name_normalized text,
  add column created_revision bigint not null default 0;
update public.shopping_items set origin_name_normalized=pg_catalog.lower(pg_catalog.btrim(name));
alter table public.shopping_items alter column origin_name_normalized set not null;
create index shopping_items_origin_revision on public.shopping_items(household_id,origin_name_normalized,created_revision);

-- Covers legacy V0.0.3 RPCs too. Metadata-only/no-op updates do not advance
-- the revision. The origin and creation revision cannot be changed by rename.
create function public.track_shopping_revision() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_revision bigint;
begin
  if TG_OP='INSERT' then
    NEW.last_status_change_version := NEW.version;
    update public.households set shopping_revision=shopping_revision+1 where id=NEW.household_id
      returning shopping_revision into v_revision;
    NEW.origin_name_normalized := pg_catalog.lower(pg_catalog.btrim(NEW.name));
    NEW.created_revision := v_revision;
  elsif TG_OP='UPDATE' then
    if NEW.household_id is distinct from OLD.household_id or NEW.id is distinct from OLD.id then
      raise exception using errcode='22023', message='shopping_identity_immutable';
    end if;
    -- Rename/metadata changes do not invalidate an older status intent.
    -- Deleted rows remain governed by delete/restore rules separately.
    NEW.last_status_change_version := case when NEW.status is distinct from OLD.status
      then NEW.version else OLD.last_status_change_version end;
    NEW.origin_name_normalized := OLD.origin_name_normalized;
    NEW.created_revision := OLD.created_revision;
    if row(NEW.name,NEW.status,NEW.deleted_at,NEW.deleted_by,NEW.bought_at,NEW.bought_by)
      is distinct from row(OLD.name,OLD.status,OLD.deleted_at,OLD.deleted_by,OLD.bought_at,OLD.bought_by) then
      update public.households set shopping_revision=shopping_revision+1 where id=NEW.household_id;
    end if;
  else
    update public.households set shopping_revision=shopping_revision+1 where id=OLD.household_id;
    return OLD;
  end if;
  return NEW;
end;
$$;
revoke all on function public.track_shopping_revision() from public, anon, authenticated;
create trigger shopping_revision_changed before insert or update or delete on public.shopping_items
for each row execute function public.track_shopping_revision();

-- One SQL statement / MVCC snapshot for items, timezone and revision.
create function public.get_shopping_snapshot(p_household_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select pg_catalog.jsonb_build_object('revision',h.shopping_revision::text,'timezone',h.timezone,
    'items',coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s) order by s.created_at desc)
      from public.shopping_items s where s.household_id=h.id and s.deleted_at is null
        and (s.status='active' or (s.status='bought'
          and s.bought_at >= (d.today::timestamp at time zone h.timezone)
          and s.bought_at < ((d.today+1)::timestamp at time zone h.timezone)))), '[]'::jsonb))
  from public.households h
  cross join lateral (select (now() at time zone h.timezone)::date as today) d
  where h.id=p_household_id and auth.uid() is not null
    and public.is_household_member(h.id);
$$;
revoke all on function public.get_shopping_snapshot(uuid) from public, anon;
grant execute on function public.get_shopping_snapshot(uuid) to authenticated;

create table public.shopping_sync_operations (
  operation_id uuid primary key,
  household_id uuid not null references public.households(id),
  actor_user_id uuid not null references public.profiles(id),
  item_id uuid not null,
  operation_type text not null check (operation_type in ('add','rename','buy','return','delete','restore')),
  request_hash text not null,
  result jsonb not null,
  processed_at timestamptz not null default now()
);
create index shopping_sync_operations_household on public.shopping_sync_operations(household_id, processed_at desc);
create unique index shopping_sync_operations_add_item on public.shopping_sync_operations(actor_user_id, household_id, item_id)
  where operation_type='add';
alter table public.shopping_sync_operations enable row level security;
revoke all on public.shopping_sync_operations from public, anon, authenticated;
-- Results are returned by RPC; the ledger has no direct client reads or writes.

create function public.apply_shopping_operation(
  p_operation_id uuid, p_household_id uuid, p_item_id uuid,
  p_type text, p_payload jsonb, p_base_version bigint,
  p_expected_user_id uuid default null, p_base_snapshot_revision bigint default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_previous public.shopping_sync_operations;
  v_item public.shopping_items;
  v_canonical public.shopping_items;
  v_result jsonb;
  v_outcome text := 'applied';
  v_name text;
  v_event text;
  v_original_id uuid := p_item_id;
  v_alias_id uuid;
  v_next_alias_id uuid;
  v_alias_depth integer;
  v_revision bigint;
begin
  if v_actor is null or not public.is_household_member(p_household_id) then
    raise exception using errcode='42501', message='not_household_member';
  end if;
  -- The client pins the account used to open its local queue. In particular,
  -- changing accounts between getUser() and the network request cannot send
  -- the old account's queued changes under the newly active account.
  if p_expected_user_id is not null and p_expected_user_id <> v_actor then
    raise exception using errcode='42501', message='shopping_account_changed';
  end if;
  if p_operation_id is null or p_item_id is null or p_type is null or p_type not in ('add','rename','buy','return','delete','restore')
     or p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode='22023', message='invalid_shopping_operation';
  end if;
  if p_type <> 'add' and (p_base_version is null or p_base_version < 1) then
    raise exception using errcode='22023', message='invalid_shopping_version';
  end if;
  if p_type='rename' and p_payload->>'base_name' is null then
    raise exception using errcode='22023', message='invalid_shopping_base_name';
  end if;
  -- Lock retries of this UUID even when the ledger row does not exist yet.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operation_id::text, 0));
  v_hash := pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
    pg_catalog.jsonb_build_object('household',p_household_id,'actor',v_actor,'item',p_item_id,
      'type',p_type,'payload',p_payload,'base_version',p_base_version,'snapshot_revision',p_base_snapshot_revision)::text,'UTF8'), 'sha256'),'hex');
  select * into v_previous from public.shopping_sync_operations where operation_id=p_operation_id;
  if found then
    if v_previous.household_id <> p_household_id or v_previous.actor_user_id <> v_actor or v_previous.request_hash <> v_hash then
      raise exception using errcode='22023', message='operation_id_reused';
    end if;
    return v_previous.result;
  end if;

  -- Serialize new sync requests within a household before checking origins.
  -- No household row is locked here before an item: legacy RPCs lock items
  -- first and update the household revision in the trigger.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('shopping:'||p_household_id::text, 0));
  select shopping_revision into v_revision from public.households where id=p_household_id;
  if p_type='add' and (p_base_snapshot_revision is null or p_base_snapshot_revision<0
    or p_base_snapshot_revision>v_revision) then
    raise exception using errcode='22023', message='invalid_snapshot_revision';
  end if;

  if p_type in ('add','rename') then
    v_name := pg_catalog.btrim(p_payload->>'name');
    if v_name is null or pg_catalog.char_length(v_name) not between 1 and 120 then
      raise exception using errcode='22023', message='invalid_shopping_item_name';
    end if;
  end if;
  if p_type='add' then
    select * into v_item from public.shopping_items where id=p_item_id for update;
    if found then
      -- Only the operation ledger can prove a retry. An existing item UUID is
      -- otherwise ambiguous, even if the caller created it earlier.
      raise exception using errcode='22023', message='shopping_item_id_reused';
    else
      -- Match origins even after rename/buy/delete. A stale add never revives
      -- a deleted item. A fresh snapshot allows the same origin name again.
      select * into v_canonical from public.shopping_items
      where household_id=p_household_id and origin_name_normalized=pg_catalog.lower(v_name)
        and created_revision>p_base_snapshot_revision
      order by created_revision, id limit 1 for update;
      if found then
        v_item := v_canonical;
        v_outcome := 'merged_duplicate';
      else
      begin
        insert into public.shopping_items(id,household_id,name,created_by)
        values(p_item_id,p_household_id,v_name,v_actor) returning * into v_item;
        v_event := 'shopping_item_added';
      exception when unique_violation then
        select * into v_canonical from public.shopping_items
        where household_id=p_household_id and deleted_at is null and status='active'
          and pg_catalog.lower(name)=pg_catalog.lower(v_name);
        if v_canonical.id is null then raise; end if;
        v_item := v_canonical;
        v_outcome := 'merged_duplicate';
      end;
      end if;
    end if;
  else
    -- An offline add that merged keeps its original UUID in every pending
    -- operation. Resolve the alias exclusively from this actor's recorded add;
    -- neither a claimed canonical ID nor a rewritten retry is trusted.
    for v_alias_depth in 1..16 loop
      select (result->>'canonical_item_id')::uuid into v_next_alias_id
      from public.shopping_sync_operations
      where actor_user_id=v_actor and household_id=p_household_id
        and item_id=coalesce(v_alias_id,v_original_id)
        and operation_type in ('add','return') and result->>'outcome'='merged_duplicate'
      order by processed_at desc, operation_id desc limit 1;
      exit when v_next_alias_id is null;
      if v_next_alias_id=coalesce(v_alias_id,v_original_id) then
        raise exception using errcode='22023', message='shopping_alias_cycle';
      end if;
      v_alias_id := v_next_alias_id;
    end loop;
    if v_next_alias_id is not null then
      raise exception using errcode='22023', message='shopping_alias_depth';
    end if;
    select * into v_item from public.shopping_items
    where id=coalesce(v_alias_id,v_original_id) and household_id=p_household_id for update;
    if not found then raise exception using errcode='42501', message='shopping_item_not_available'; end if;
    if v_item.deleted_at is not null and p_type <> 'restore' then
      v_outcome := case when p_type='delete' then 'already_applied' else 'conflict_deleted' end;
    elsif p_type='rename' then
      -- Only two rename operations with the same base version and base name
      -- are peers. The lower UUID wins even when it reaches the server later.
      -- An unrelated later rename changes the current name and blocks this.
      if v_item.status <> 'active' then v_outcome := 'conflict_changed';
      elsif v_item.name <> p_payload->>'base_name' and not
        (v_alias_id is not null and pg_catalog.lower(v_item.name)=pg_catalog.lower(p_payload->>'base_name'))
        and not (v_item.last_rename_base_version=p_base_version
          and pg_catalog.lower(v_item.last_rename_base_name)=pg_catalog.lower(p_payload->>'base_name')
          and v_item.last_rename_operation_id is not null
          and v_item.name=(select result->'item'->>'name' from public.shopping_sync_operations
            where operation_id=v_item.last_rename_operation_id))
        then v_outcome := 'conflict_renamed';
      elsif v_item.name = v_name then
        v_outcome := 'already_applied';
        -- Equal target names still participate in the UUID tie-break if
        -- another concurrent rename arrives later with a different target.
        if v_item.last_rename_base_version=p_base_version
          and pg_catalog.lower(v_item.last_rename_base_name)=pg_catalog.lower(p_payload->>'base_name')
          and p_operation_id < v_item.last_rename_operation_id then
          update public.shopping_items set last_rename_operation_id=p_operation_id
          where id=v_item.id returning * into v_item;
        end if;
      elsif v_item.last_rename_base_version=p_base_version
        and pg_catalog.lower(v_item.last_rename_base_name)=pg_catalog.lower(p_payload->>'base_name')
        and v_item.name <> p_payload->>'base_name'
        and v_item.last_rename_operation_id < p_operation_id then v_outcome := 'conflict_renamed';
      else
        begin
          update public.shopping_items set name=v_name,updated_at=now(),version=version+1,
            last_rename_base_version=p_base_version,last_rename_base_name=p_payload->>'base_name',
            last_rename_operation_id=p_operation_id
          where id=v_item.id returning * into v_item;
          v_event := 'shopping_item_renamed';
        exception when unique_violation then v_outcome := 'conflict_duplicate'; end;
      end if;
    elsif p_type='buy' then
      if v_item.status='bought' then v_outcome := 'already_applied';
      elsif v_item.last_status_change_version > p_base_version then v_outcome := 'conflict_changed';
      else
        update public.shopping_items set status='bought',bought_by=v_actor,bought_at=now(),updated_at=now(),version=version+1
        where id=v_item.id returning * into v_item;
        v_event := 'shopping_item_bought';
      end if;
    elsif p_type='return' then
      if v_item.status='active' then v_outcome := 'already_applied';
      elsif v_item.last_status_change_version > p_base_version then v_outcome := 'conflict_changed';
      else
        begin
          update public.shopping_items set status='active',bought_by=null,bought_at=null,updated_at=now(),version=version+1
          where id=v_item.id returning * into v_item;
          v_event := 'shopping_item_restored';
        exception when unique_violation then
          -- The canonical active item already represents this return. Retire
          -- the old bought row without touching the existing active row.
          select * into v_canonical from public.shopping_items
          where household_id=p_household_id and status='active' and deleted_at is null
            and pg_catalog.lower(name)=pg_catalog.lower(v_item.name) for update;
          if v_canonical.id is null then raise; end if;
          -- Keep the original bought_by/bought_at on the retired historical
          -- row; it is hidden from the current list by deleted_at.
          update public.shopping_items set deleted_at=now(),deleted_by=v_actor,
            updated_at=now(),version=version+1
          where id=v_item.id;
          v_item := v_canonical;
          v_outcome := 'merged_duplicate';
          v_event := 'shopping_item_restored';
        end;
      end if;
    elsif p_type='delete' then
      if v_item.deleted_at is not null then v_outcome := 'already_applied';
      else
        -- Delete dominates an earlier buy/return in both delivery orders.
        update public.shopping_items set deleted_by=v_actor,deleted_at=now(),status='active',
          bought_by=null,bought_at=null,last_delete_operation_id=p_operation_id,
          updated_at=now(),version=version+1
        where id=v_item.id returning * into v_item;
        v_event := 'shopping_item_deleted';
      end if;
    elsif p_type='restore' then
      if v_item.deleted_at is null then v_outcome := 'already_applied';
      elsif v_item.version is distinct from (select (result->'item'->>'version')::bigint
          from public.shopping_sync_operations where operation_id=(p_payload->>'delete_operation_id')::uuid
            and actor_user_id=v_actor and household_id=p_household_id and operation_type='delete')
        or v_item.deleted_by <> v_actor
        or v_item.last_delete_operation_id is distinct from (p_payload->>'delete_operation_id')::uuid then
        v_outcome := 'conflict_changed';
      else
        begin
          update public.shopping_items set deleted_by=null,deleted_at=null,last_delete_operation_id=null,
            updated_at=now(),version=version+1
          where id=v_item.id returning * into v_item;
          v_event := 'shopping_item_delete_undone';
        exception when unique_violation then v_outcome := 'conflict_duplicate'; end;
      end if;
    end if;
  end if;
  if v_event is not null then
    insert into public.household_audit_log(household_id,event_type,actor_user_id,metadata)
    values(p_household_id,v_event,v_actor,
      pg_catalog.jsonb_build_object('item_id',v_item.id,'operation_id',p_operation_id));
  end if;
  v_result := pg_catalog.jsonb_build_object('outcome',v_outcome,'item',pg_catalog.to_jsonb(v_item),
    'canonical_item_id',v_item.id,'shopping_revision',
      (select shopping_revision::text from public.households where id=p_household_id));
  insert into public.shopping_sync_operations(operation_id,household_id,actor_user_id,item_id,operation_type,request_hash,result)
  values(p_operation_id,p_household_id,v_actor,p_item_id,p_type,v_hash,v_result);
  return v_result;
end;
$$;
revoke all on function public.apply_shopping_operation(uuid,uuid,uuid,text,jsonb,bigint,uuid,bigint) from public, anon;
grant execute on function public.apply_shopping_operation(uuid,uuid,uuid,text,jsonb,bigint,uuid,bigint) to authenticated;

-- Explicit ACL delta for existing application functions, exact signatures only.
-- Membership helpers require authenticated EXECUTE for existing SELECT RLS.
-- Their V0.0.3 bodies already restrict p_user_id to auth.uid(); unchanged here.
revoke execute on function public.create_household(text) from public, anon;
grant execute on function public.create_household(text) to authenticated;
revoke execute on function public.rename_household(uuid,text) from public, anon;
grant execute on function public.rename_household(uuid,text) to authenticated;
revoke execute on function public.create_household_invitation(uuid,text) from public, anon;
grant execute on function public.create_household_invitation(uuid,text) to authenticated;
revoke execute on function public.respond_to_household_invitation(text,boolean) from public, anon;
grant execute on function public.respond_to_household_invitation(text,boolean) to authenticated;
revoke execute on function public.cancel_household_invitation(uuid) from public, anon;
grant execute on function public.cancel_household_invitation(uuid) to authenticated;
revoke execute on function public.add_shopping_item(uuid,uuid,text) from public, anon;
grant execute on function public.add_shopping_item(uuid,uuid,text) to authenticated;
revoke execute on function public.rename_shopping_item(uuid,text,bigint) from public, anon;
grant execute on function public.rename_shopping_item(uuid,text,bigint) to authenticated;
revoke execute on function public.mark_shopping_item_bought(uuid,bigint) from public, anon;
grant execute on function public.mark_shopping_item_bought(uuid,bigint) to authenticated;
revoke execute on function public.restore_shopping_item(uuid,bigint) from public, anon;
grant execute on function public.restore_shopping_item(uuid,bigint) to authenticated;
revoke execute on function public.delete_shopping_item(uuid,bigint) from public, anon;
grant execute on function public.delete_shopping_item(uuid,bigint) to authenticated;
revoke execute on function public.undo_delete_shopping_item(uuid,bigint) from public, anon;
grant execute on function public.undo_delete_shopping_item(uuid,bigint) to authenticated;
revoke execute on function public.list_current_shopping_items(uuid) from public, anon;
grant execute on function public.list_current_shopping_items(uuid) to authenticated;
revoke execute on function public.is_household_member(uuid,uuid) from public, anon;
grant execute on function public.is_household_member(uuid,uuid) to authenticated;
revoke execute on function public.is_household_owner(uuid,uuid) from public, anon;
grant execute on function public.is_household_owner(uuid,uuid) to authenticated;

-- Token-bearing invitation preview is the ONLY anonymous application RPC.
revoke execute on function public.get_invitation_preview(text) from public;
grant execute on function public.get_invitation_preview(text) to anon, authenticated;

-- Internal/trigger functions are not client RPCs. Trigger execution and calls
-- from SECURITY DEFINER owners continue to work without client EXECUTE.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.validate_household_timezone() from public, anon, authenticated;
revoke execute on function public.shopping_error_for_unique() from public, anon, authenticated;
