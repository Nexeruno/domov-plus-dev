-- Run only after the energy migration on an isolated DEV project.
-- All test data rolls back, including the temporary auth users.
begin;

insert into auth.users (id,instance_id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
 ('e1000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','energy-v01-a@example.invalid','{"provider":"email"}','{"display_name":"Energy A"}',now(),now()),
 ('e2000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','energy-v01-b@example.invalid','{"provider":"email"}','{"display_name":"Energy B"}',now(),now());

insert into public.households(id,name,created_by)
values ('e1000000-0000-4000-8000-000000000011','Energy test A','e1000000-0000-4000-8000-000000000001'),
       ('e2000000-0000-4000-8000-000000000022','Energy test B','e2000000-0000-4000-8000-000000000002');
insert into public.household_memberships(household_id,user_id,role)
values ('e1000000-0000-4000-8000-000000000011','e1000000-0000-4000-8000-000000000001','owner'),
       ('e2000000-0000-4000-8000-000000000022','e2000000-0000-4000-8000-000000000002','owner');

do $$
begin
  if has_table_privilege('anon','public.energy_readings','SELECT') or
     has_table_privilege('authenticated','public.energy_readings','INSERT') or
     has_table_privilege('authenticated','public.energy_readings','UPDATE') or
     has_table_privilege('authenticated','public.energy_readings','DELETE') or
     has_function_privilege('anon','public.add_energy_reading(uuid,date,numeric,numeric,numeric,numeric)','EXECUTE') then
    raise exception 'Unexpected energy API grant';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select public.add_energy_reading('e1000000-0000-4000-8000-000000000011','2026-01-01',100,50,5,3);
select public.add_energy_reading('e1000000-0000-4000-8000-000000000011','2026-02-01',120,60,5,3);
do $$
begin
  if (select count(*) from public.energy_readings where household_id='e1000000-0000-4000-8000-000000000011') <> 2 then
    raise exception 'Member could not read own energy readings';
  end if;
  if (select count(*) from public.energy_readings where household_id='e2000000-0000-4000-8000-000000000022') <> 0 then
    raise exception 'Member read foreign energy readings';
  end if;
  if (select count(*) from public.energy_readings where household_id='e1000000-0000-4000-8000-000000000011'
      and created_by='e1000000-0000-4000-8000-000000000001') <> 2 then
    raise exception 'RPC actor does not match auth identity';
  end if;
  if not exists (
    select 1 from public.energy_readings newer join public.energy_readings older
      on older.household_id=newer.household_id and older.reading_date='2026-01-01'
    where newer.household_id='e1000000-0000-4000-8000-000000000011'
      and newer.reading_date='2026-02-01'
      and newer.vt_kwh-older.vt_kwh=20
      and newer.nt_kwh-older.nt_kwh=10
      and (newer.vt_kwh-older.vt_kwh)+(newer.nt_kwh-older.nt_kwh)=30
      and (newer.vt_kwh-older.vt_kwh)*newer.price_vt_kwh+
          (newer.nt_kwh-older.nt_kwh)*newer.price_nt_kwh=130
  ) then raise exception 'Energy interval values or price differ'; end if;
end;
$$;
do $$ begin
  insert into public.energy_readings(household_id,reading_date,vt_kwh,nt_kwh,price_vt_kwh,price_nt_kwh,created_by)
  values ('e1000000-0000-4000-8000-000000000011','2026-03-01',130,70,5,3,'e2000000-0000-4000-8000-000000000002');
  raise exception 'Direct insert or forged author succeeded';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  perform public.add_energy_reading('e2000000-0000-4000-8000-000000000022','2026-01-01',1,1,1,1);
  raise exception 'Foreign household write succeeded';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  perform public.add_energy_reading('e1000000-0000-4000-8000-000000000011','2026-03-01',119,60,5,3);
  raise exception 'Lower VT succeeded';
exception when invalid_parameter_value then null;
end $$;
do $$ begin
  perform public.add_energy_reading('e1000000-0000-4000-8000-000000000011','2026-03-01',121,59,5,3);
  raise exception 'Lower NT succeeded';
exception when invalid_parameter_value then null;
end $$;
do $$ begin
  perform public.add_energy_reading('e1000000-0000-4000-8000-000000000011','2026-01-15',121,61,5,3);
  raise exception 'Backdated reading succeeded';
exception when invalid_parameter_value then null;
end $$;
do $$ begin
  perform public.add_energy_reading('e1000000-0000-4000-8000-000000000011','2099-01-01',121,61,5,3);
  raise exception 'Future reading succeeded';
exception when invalid_parameter_value then null;
end $$;
reset role;

select set_config('request.jwt.claim.sub','e2000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$ begin
  if (select count(*) from public.energy_readings where household_id='e1000000-0000-4000-8000-000000000011') <> 0 then
    raise exception 'Member B read A readings';
  end if;
end $$;
do $$ begin
  perform public.add_energy_reading('e1000000-0000-4000-8000-000000000011','2026-03-01',130,70,5,3);
  raise exception 'Member B wrote A reading';
exception when insufficient_privilege then null;
end $$;
reset role;

do $$ begin
  if (select count(*) from public.household_audit_log where event_type='energy_reading_created' and household_id='e1000000-0000-4000-8000-000000000011') <> 2 then
    raise exception 'Expected exactly one audit event per successful reading';
  end if;
end $$;
rollback;
