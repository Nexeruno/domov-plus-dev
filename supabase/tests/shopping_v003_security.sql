-- Domov+ V0.0.3 shopping integration, audit, duplicate and RLS tests.
-- Transactional: no fixture survives the run.
begin;
create temp table v003_results(name text primary key);
grant select,insert on v003_results to authenticated;
create or replace function pg_temp.ok(v boolean,n text) returns void language plpgsql security definer set search_path=pg_temp as $$begin if not coalesce(v,false) then raise exception 'FAILED: %',n; end if; insert into v003_results values(n); end$$;
grant execute on function pg_temp.ok(boolean,text) to authenticated;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('31000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','v003-a@example.invalid',crypt('temporary',gen_salt('bf')),now(),'{}','{"display_name":"A"}',now(),now()),
('32000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','v003-b@example.invalid',crypt('temporary',gen_salt('bf')),now(),'{}','{"display_name":"B"}',now(),now());

select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000001',true); set local role authenticated;
select public.create_household('V003 A'); reset role;
select set_config('request.jwt.claim.sub','32000000-0000-4000-8000-000000000002',true); set local role authenticated;
select public.create_household('V003 B'); reset role;
create temp table ids as select (select id from households where name='V003 A') ha,(select id from households where name='V003 B') hb;
grant select on ids to authenticated;

-- Core behavior as A.
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000001',true); set local role authenticated;
select public.add_shopping_item((select ha from ids),'33000000-0000-4000-8000-000000000003','  Mléko  ');
select pg_temp.ok((select name='Mléko' from shopping_items where id='33000000-0000-4000-8000-000000000003'),'01 add trims whitespace');
select pg_temp.ok((select created_by=auth.uid() from shopping_items where id='33000000-0000-4000-8000-000000000003'),'02 created_by');
do $$begin perform public.add_shopping_item((select ha from ids),'33000000-0000-4000-8000-000000000004','   '); raise exception 'empty accepted'; exception when others then perform pg_temp.ok(sqlerrm='invalid_shopping_item_name','03 empty rejected'); end$$;
do $$begin perform public.add_shopping_item((select ha from ids),'33000000-0000-4000-8000-000000000005','mléko'); raise exception 'duplicate accepted'; exception when others then perform pg_temp.ok(sqlerrm='active_shopping_item_exists','04 case-insensitive duplicate'); end$$;
select public.rename_shopping_item('33000000-0000-4000-8000-000000000003','Plnotučné mléko',1);
select pg_temp.ok((select name='Plnotučné mléko' and version=2 from shopping_items where id='33000000-0000-4000-8000-000000000003'),'05 rename and version');
select public.add_shopping_item((select ha from ids),'33000000-0000-4000-8000-000000000006','Chléb');
do $$begin perform public.rename_shopping_item('33000000-0000-4000-8000-000000000006','PLNOTUČNÉ MLÉKO',1); raise exception 'rename duplicate accepted'; exception when others then perform pg_temp.ok(sqlerrm='active_shopping_item_exists','06 rename duplicate rejected'); end$$;
select public.mark_shopping_item_bought('33000000-0000-4000-8000-000000000003',2);
select pg_temp.ok((select status='bought' from shopping_items where id='33000000-0000-4000-8000-000000000003'),'07 bought status');
select pg_temp.ok((select bought_by=auth.uid() from shopping_items where id='33000000-0000-4000-8000-000000000003'),'08 bought_by');
select pg_temp.ok((select bought_at is not null from shopping_items where id='33000000-0000-4000-8000-000000000003'),'09 bought_at');
select public.add_shopping_item((select ha from ids),'33000000-0000-4000-8000-000000000007','Plnotučné mléko');
select pg_temp.ok((select count(*)=2 from shopping_items where lower(name)=lower('Plnotučné mléko')),'10 re-add bought name');
do $$begin perform public.restore_shopping_item('33000000-0000-4000-8000-000000000003',3); raise exception 'restore duplicate accepted'; exception when others then perform pg_temp.ok(sqlerrm='active_shopping_item_exists','11 restore duplicate rejected'); end$$;
select public.mark_shopping_item_bought('33000000-0000-4000-8000-000000000007',1);
select public.restore_shopping_item('33000000-0000-4000-8000-000000000003',3);
select pg_temp.ok((select status='active' and bought_by is null and bought_at is null from shopping_items where id='33000000-0000-4000-8000-000000000003'),'12 restore bought');
select public.delete_shopping_item('33000000-0000-4000-8000-000000000006',1);
select pg_temp.ok((select deleted_at is not null and deleted_by=auth.uid() from shopping_items where id='33000000-0000-4000-8000-000000000006'),'13 soft delete');
select public.undo_delete_shopping_item('33000000-0000-4000-8000-000000000006',2);
select pg_temp.ok((select deleted_at is null and version=3 from shopping_items where id='33000000-0000-4000-8000-000000000006'),'14 undo delete');
do $$begin perform public.rename_shopping_item('33000000-0000-4000-8000-000000000006','Starý request',1); raise exception 'stale accepted'; exception when others then perform pg_temp.ok(sqlerrm='shopping_item_not_available','15 stale version rejected'); end$$;

select pg_temp.ok((select count(*)=1 from household_audit_log where event_type='shopping_item_added' and metadata->>'item_id'='33000000-0000-4000-8000-000000000003'),'16 audit add');
select pg_temp.ok((select count(*)=1 from household_audit_log where event_type='shopping_item_renamed' and metadata->>'item_id'='33000000-0000-4000-8000-000000000003'),'17 audit rename');
select pg_temp.ok((select count(*)=1 from household_audit_log where event_type='shopping_item_bought' and metadata->>'item_id'='33000000-0000-4000-8000-000000000003'),'18 audit bought');
select pg_temp.ok((select count(*)=1 from household_audit_log where event_type='shopping_item_restored'),'19 audit restore');
select pg_temp.ok((select count(*)=1 from household_audit_log where event_type='shopping_item_deleted'),'20 audit delete');
select pg_temp.ok((select count(*)=1 from household_audit_log where event_type='shopping_item_delete_undone'),'21 audit undo');

-- A cannot cross the boundary to B.
select pg_temp.ok((select count(*)=0 from shopping_items where household_id=(select hb from ids)),'22 A cannot read B');
do $$begin perform public.add_shopping_item((select hb from ids),'34000000-0000-4000-8000-000000000001','Útok'); raise exception 'foreign create'; exception when others then perform pg_temp.ok(sqlerrm='not_household_member','23 A cannot create in B'); end$$;
reset role;

-- B creates its own target, then A attacks it by item id.
select set_config('request.jwt.claim.sub','32000000-0000-4000-8000-000000000002',true); set local role authenticated;
select public.add_shopping_item((select hb from ids),'34000000-0000-4000-8000-000000000002','Cizí položka'); reset role;
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000001',true); set local role authenticated;
do $$begin perform public.rename_shopping_item('34000000-0000-4000-8000-000000000002','Útok',1); raise exception 'foreign rename'; exception when others then perform pg_temp.ok(sqlerrm='shopping_item_not_available','24 A cannot rename B'); end$$;
do $$begin perform public.mark_shopping_item_bought('34000000-0000-4000-8000-000000000002',1); raise exception 'foreign buy'; exception when others then perform pg_temp.ok(sqlerrm='shopping_item_not_available','25 A cannot buy B'); end$$;
do $$begin perform public.delete_shopping_item('34000000-0000-4000-8000-000000000002',1); raise exception 'foreign delete'; exception when others then perform pg_temp.ok(sqlerrm='shopping_item_not_available','26 A cannot delete B'); end$$;
do $$begin update shopping_items set name='direct attack' where id='34000000-0000-4000-8000-000000000002'; raise exception 'direct write'; exception when insufficient_privilege then perform pg_temp.ok(true,'27 direct update denied'); end$$;
do $$begin insert into shopping_items(id,household_id,name,created_by) values(gen_random_uuid(),(select hb from ids),'direct','31000000-0000-4000-8000-000000000001'); raise exception 'direct insert'; exception when insufficient_privilege then perform pg_temp.ok(true,'28 direct insert denied'); end$$;
select pg_temp.ok((select count(*)=0 from household_audit_log where household_id=(select hb from ids)),'29 A cannot read B audit');
select pg_temp.ok((select timezone='Europe/Prague' from households where id=(select ha from ids)),'30 household timezone default');
reset role;
select count(*) as passed_v003_tests from v003_results;
rollback;
