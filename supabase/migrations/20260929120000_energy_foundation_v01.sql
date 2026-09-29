-- Energy foundation V0.1. Additive migration on the deployed household schema.
create table public.energy_readings (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id),
  reading_date date not null,
  vt_kwh numeric(12,3) not null check (vt_kwh >= 0),
  nt_kwh numeric(12,3) not null check (nt_kwh >= 0),
  price_vt_kwh numeric(10,4) not null check (price_vt_kwh >= 0),
  price_nt_kwh numeric(10,4) not null check (price_nt_kwh >= 0),
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id),
  unique (household_id, reading_date)
);
create index energy_readings_household_date_idx on public.energy_readings (household_id, reading_date desc);
alter table public.energy_readings enable row level security;
revoke all on public.energy_readings from public, anon, authenticated;
grant select on public.energy_readings to authenticated;
create policy energy_readings_member_select on public.energy_readings
  for select to authenticated using (public.is_household_member(household_id));

-- Preserve the existing event types and historical records.
alter table public.household_audit_log drop constraint household_audit_log_event_type_check;
alter table public.household_audit_log add constraint household_audit_log_event_type_check check (event_type in (
  'household_created','invitation_created','invitation_accepted','invitation_declined',
  'invitation_cancelled','household_name_changed','shopping_item_added',
  'shopping_item_renamed','shopping_item_bought','shopping_item_restored',
  'shopping_item_deleted','shopping_item_delete_undone','energy_reading_created'
));

-- Serialise appends for a household. Direct writes remain unavailable to clients.
create function public.add_energy_reading(
  p_household_id uuid, p_reading_date date, p_vt_kwh numeric, p_nt_kwh numeric,
  p_price_vt_kwh numeric, p_price_nt_kwh numeric
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_timezone text;
  v_previous public.energy_readings%rowtype;
  v_id uuid;
begin
  if v_actor is null or not public.is_household_member(p_household_id) then
    raise exception using errcode = '42501', message = 'not_household_member';
  end if;
  select timezone into v_timezone from public.households where id = p_household_id for update;
  if v_timezone is null then
    raise exception using errcode = '42501', message = 'not_household_member';
  end if;
  if p_reading_date is null or p_reading_date > (now() at time zone v_timezone)::date then
    raise exception using errcode = '22023', message = 'invalid_reading_date';
  end if;
  if p_vt_kwh is null or p_nt_kwh is null or p_price_vt_kwh is null or p_price_nt_kwh is null
     or p_vt_kwh < 0 or p_nt_kwh < 0 or p_price_vt_kwh < 0 or p_price_nt_kwh < 0 then
    raise exception using errcode = '22023', message = 'invalid_energy_value';
  end if;
  select * into v_previous from public.energy_readings
    where household_id = p_household_id order by reading_date desc limit 1;
  if found and p_reading_date <= v_previous.reading_date then
    raise exception using errcode = '22023', message = 'reading_date_not_newer';
  end if;
  if found and (p_vt_kwh < v_previous.vt_kwh or p_nt_kwh < v_previous.nt_kwh) then
    raise exception using errcode = '22023', message = 'reading_lower_than_previous';
  end if;
  insert into public.energy_readings (household_id,reading_date,vt_kwh,nt_kwh,price_vt_kwh,price_nt_kwh,created_by)
  values (p_household_id,p_reading_date,p_vt_kwh,p_nt_kwh,p_price_vt_kwh,p_price_nt_kwh,v_actor)
  returning id into v_id;
  insert into public.household_audit_log (household_id,event_type,actor_user_id,metadata)
  values (p_household_id,'energy_reading_created',v_actor,jsonb_build_object('reading_id',v_id));
  return v_id;
end;
$$;
revoke all on function public.add_energy_reading(uuid,date,numeric,numeric,numeric,numeric) from public, anon;
grant execute on function public.add_energy_reading(uuid,date,numeric,numeric,numeric,numeric) to authenticated;
