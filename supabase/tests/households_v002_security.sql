-- Domov+ V0.0.2 – databázové integrační a RLS testy.
-- Celý běh je transakční a na konci se vrátí zpět.
begin;

create temp table v002_results (test_name text primary key);
grant select, insert on v002_results to authenticated;

create or replace function pg_temp.ok(p_condition boolean, p_name text)
returns void
language plpgsql
security definer
set search_path = pg_temp
as $$
begin
  if not coalesce(p_condition, false) then
    raise exception 'FAILED: %', p_name;
  end if;
  insert into v002_results(test_name) values (p_name) on conflict do nothing;
end;
$$;
grant execute on function pg_temp.ok(boolean, text) to authenticated;

-- Tři dočasné účty. C je příjemce scénářů, které se nemají přijmout.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'v002-a@example.invalid', crypt('Testovaci-heslo-A-2026', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"display_name":"Test A"}', now(), now()),
  ('20000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'v002-b@example.invalid', crypt('Testovaci-heslo-B-2026', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"display_name":"Test B"}', now(), now()),
  ('30000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'v002-c@example.invalid', crypt('Testovaci-heslo-C-2026', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"display_name":"Test C"}', now(), now());

-- User A vytvoří Household A přes veřejné RPC.
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","email":"v002-a@example.invalid","role":"authenticated"}', true);
set local role authenticated;
select public.create_household('Household A');
reset role;

select pg_temp.ok(
  (select count(*) = 1 from public.households where name = 'Household A' and created_by = '10000000-0000-4000-8000-000000000001'),
  '01 vytvoření domácnosti'
);
select pg_temp.ok(
  (select count(*) = 1 from public.household_memberships m join public.households h on h.id=m.household_id
   where h.name='Household A' and m.user_id='10000000-0000-4000-8000-000000000001' and m.role='owner'),
  '02 zakladatel je owner'
);

-- User B vytvoří zcela oddělenou Household B.
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-000000000002","email":"v002-b@example.invalid","role":"authenticated"}', true);
set local role authenticated;
select public.create_household('Household B');
reset role;

create temp table v002_ids as
select
  (select id from public.households where name='Household A')::uuid as household_a,
  (select id from public.households where name='Household B')::uuid as household_b;
grant select on v002_ids to authenticated;

-- Izolace A -> B včetně přímých write pokusů.
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","email":"v002-a@example.invalid","role":"authenticated"}', true);
set local role authenticated;
select pg_temp.ok((select count(*)=1 from public.households where id=(select household_a from v002_ids)), 'RLS A čte Household A');
select pg_temp.ok((select count(*)=0 from public.households where id=(select household_b from v002_ids)), 'RLS A nečte Household B');
select pg_temp.ok((select count(*)=0 from public.household_memberships where household_id=(select household_b from v002_ids)), 'RLS A nečte členství B');
select pg_temp.ok((select count(*)=0 from public.household_invitations where household_id=(select household_b from v002_ids)), 'RLS A nečte pozvánky B');
do $$ begin
  perform public.rename_household((select household_b from v002_ids), 'Útok A');
  raise exception 'FAILED: RLS A přejmenoval Household B';
exception when insufficient_privilege then perform pg_temp.ok(true, 'RLS A nepřejmenuje Household B'); end $$;
do $$ begin
  insert into public.household_memberships(household_id,user_id,role)
  values ((select household_b from v002_ids),'10000000-0000-4000-8000-000000000001','member');
  raise exception 'FAILED: RLS A vytvořil membership v B';
exception when insufficient_privilege then perform pg_temp.ok(true, 'RLS A nevytvoří membership v B'); end $$;
do $$ begin
  insert into public.household_memberships(household_id,user_id,role)
  values ((select household_b from v002_ids),'10000000-0000-4000-8000-000000000001','owner');
  raise exception 'FAILED: RLS A si přidělil owner v B';
exception when insufficient_privilege then perform pg_temp.ok(true, 'RLS A si nepřidělí owner v B'); end $$;
do $$ begin
  update public.household_memberships set role='owner'
  where household_id=(select household_b from v002_ids) and user_id='20000000-0000-4000-8000-000000000002';
  raise exception 'FAILED: RLS A obešel membership identifikátor';
exception when insufficient_privilege then perform pg_temp.ok(true, 'RLS A neobejde membership identifikátor'); end $$;
do $$ begin
  update public.household_memberships set household_id=(select household_a from v002_ids)
  where household_id=(select household_b from v002_ids) and user_id='20000000-0000-4000-8000-000000000002';
  raise exception 'FAILED: RLS A změnil household_id cizího membership';
exception when insufficient_privilege then perform pg_temp.ok(true, 'RLS A neobejde ochranu změnou household_id'); end $$;
reset role;

-- Stejná izolace opačným směrem B -> A.
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-000000000002","email":"v002-b@example.invalid","role":"authenticated"}', true);
set local role authenticated;
select pg_temp.ok((select count(*)=1 from public.households where id=(select household_b from v002_ids)), 'RLS B čte Household B');
select pg_temp.ok((select count(*)=0 from public.households where id=(select household_a from v002_ids)), 'RLS B nečte Household A');
select pg_temp.ok((select count(*)=0 from public.household_memberships where household_id=(select household_a from v002_ids)), 'RLS B nečte členství A');
select pg_temp.ok((select count(*)=0 from public.household_invitations where household_id=(select household_a from v002_ids)), 'RLS B nečte pozvánky A');
do $$ begin
  perform public.rename_household((select household_a from v002_ids), 'Útok B');
  raise exception 'FAILED: RLS B přejmenoval Household A';
exception when insufficient_privilege then perform pg_temp.ok(true, 'RLS B nepřejmenuje Household A'); end $$;
do $$ begin
  insert into public.household_memberships(household_id,user_id,role)
  values ((select household_a from v002_ids),'20000000-0000-4000-8000-000000000002','owner');
  raise exception 'FAILED: RLS B si přidělil owner v A';
exception when insufficient_privilege then perform pg_temp.ok(true, 'RLS B si nepřidělí owner v A'); end $$;
do $$ begin
  insert into public.household_memberships(household_id,user_id,role)
  values ((select household_a from v002_ids),'20000000-0000-4000-8000-000000000002','member');
  raise exception 'FAILED: RLS B vytvořil membership v A';
exception when insufficient_privilege then perform pg_temp.ok(true, 'RLS B nevytvoří membership v A'); end $$;
do $$ begin
  update public.household_memberships set role='owner'
  where household_id=(select household_a from v002_ids) and user_id='10000000-0000-4000-8000-000000000001';
  raise exception 'FAILED: RLS B obešel membership identifikátor';
exception when insufficient_privilege then perform pg_temp.ok(true, 'RLS B neobejde membership identifikátor'); end $$;
do $$ begin
  update public.household_memberships set household_id=(select household_b from v002_ids)
  where household_id=(select household_a from v002_ids) and user_id='10000000-0000-4000-8000-000000000001';
  raise exception 'FAILED: RLS B změnil household_id cizího membership';
exception when insufficient_privilege then perform pg_temp.ok(true, 'RLS B neobejde ochranu změnou household_id'); end $$;
reset role;

-- Vytvoření pozvánky A -> B a zákaz duplicity.
create temp table v002_invites (kind text primary key, invitation_id uuid, token text);
grant select, insert on v002_invites to authenticated;

-- Opačný e-mailový útok: B pozve C do B, účet A jej nesmí přijmout.
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-000000000002","email":"v002-b@example.invalid","role":"authenticated"}', true);
set local role authenticated;
insert into v002_invites(kind,invitation_id,token)
select 'reverse-email', invitation_id, invitation_token
from public.create_household_invitation((select household_b from v002_ids),'v002-c@example.invalid');
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","email":"v002-a@example.invalid","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  perform public.respond_to_household_invitation((select token from v002_invites where kind='reverse-email'), true);
  raise exception 'FAILED: A přijal pozvánku B určenou C';
exception when insufficient_privilege then
  if sqlerrm <> 'invitation_email_mismatch' then raise; end if;
  perform pg_temp.ok(true, 'RLS opačný směr nepoužije pozvánku jiného e-mailu');
end $$;
reset role;

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","email":"v002-a@example.invalid","role":"authenticated"}', true);
set local role authenticated;
insert into v002_invites(kind,invitation_id,token)
select 'valid', invitation_id, invitation_token
from public.create_household_invitation((select household_a from v002_ids),'v002-b@example.invalid');
select pg_temp.ok((select count(*)=1 from v002_invites where kind='valid'), '03 vytvoření pozvánky');
select pg_temp.ok(
  (select count(*)=1 from public.get_invitation_preview((select token from v002_invites where kind='valid'))
   where invitation_status='pending' and target_email='v002-b@example.invalid'),
  'regrese náhled platné pozvánky bez nejednoznačného expires_at'
);
do $$ begin
  perform public.create_household_invitation((select household_a from v002_ids),'v002-b@example.invalid');
  raise exception 'FAILED: vznikla druhá aktivní pozvánka';
exception when unique_violation then
  if sqlerrm <> 'active_invitation_exists' then raise; end if;
  perform pg_temp.ok(true, '04 zákaz druhé aktivní pozvánky');
end $$;
reset role;

-- Jiný e-mail C nesmí přijmout pozvánku pro B.
select set_config('request.jwt.claim.sub', '30000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"30000000-0000-4000-8000-000000000003","email":"v002-c@example.invalid","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  perform public.respond_to_household_invitation((select token from v002_invites where kind='valid'), true);
  raise exception 'FAILED: pozvánku přijal jiný e-mail';
exception when insufficient_privilege then
  if sqlerrm <> 'invitation_email_mismatch' then raise; end if;
  perform pg_temp.ok(true, '09 odmítnutí účtu s jiným e-mailem');
end $$;
reset role;

-- B přijme platnou pozvánku a stane se druhým ownerem.
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-000000000002","email":"v002-b@example.invalid","role":"authenticated"}', true);
set local role authenticated;
select public.respond_to_household_invitation((select token from v002_invites where kind='valid'), true);
select pg_temp.ok((select count(*)=1 from public.household_memberships where household_id=(select household_a from v002_ids) and user_id='20000000-0000-4000-8000-000000000002'), '05 přijetí platné pozvánky');
select pg_temp.ok((select role='owner' from public.household_memberships where household_id=(select household_a from v002_ids) and user_id='20000000-0000-4000-8000-000000000002'), '10 pozvaný uživatel je owner');
do $$ begin
  perform public.respond_to_household_invitation((select token from v002_invites where kind='valid'), true);
  raise exception 'FAILED: pozvánka byla použita opakovaně';
exception when invalid_parameter_value then perform pg_temp.ok(true, '06 zákaz opakovaného použití pozvánky'); end $$;
do $$ begin
  insert into public.household_memberships(household_id,user_id,role)
  values ((select household_a from v002_ids),'20000000-0000-4000-8000-000000000002','owner');
  raise exception 'FAILED: vzniklo duplicitní členství';
exception when insufficient_privilege then perform pg_temp.ok(true, '11 zákaz duplicitního membership klientem'); end $$;
reset role;

-- Přejmenování vlastní domácnosti.
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","email":"v002-a@example.invalid","role":"authenticated"}', true);
set local role authenticated;
select public.rename_household((select household_a from v002_ids),'Household A přejmenovaná');
reset role;
select pg_temp.ok((select name='Household A přejmenovaná' from public.households where id=(select household_a from v002_ids)), '12 změna názvu vlastní domácnosti');

-- Čekající pozvánka pro C a její zrušení.
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","email":"v002-a@example.invalid","role":"authenticated"}', true);
set local role authenticated;
insert into v002_invites(kind,invitation_id,token)
select 'cancelled', invitation_id, invitation_token
from public.create_household_invitation((select household_a from v002_ids),'v002-c@example.invalid');
select public.cancel_household_invitation((select invitation_id from v002_invites where kind='cancelled'));
reset role;
select pg_temp.ok((select status='cancelled' from public.household_invitations where id=(select invitation_id from v002_invites where kind='cancelled')), '13 zrušení čekající pozvánky');

select set_config('request.jwt.claim.sub', '30000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"30000000-0000-4000-8000-000000000003","email":"v002-c@example.invalid","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  perform public.respond_to_household_invitation((select token from v002_invites where kind='cancelled'), true);
  raise exception 'FAILED: zrušená pozvánka byla přijata';
exception when invalid_parameter_value then perform pg_temp.ok(true, '08 odmítnutí zrušené pozvánky'); end $$;
do $$ begin
  perform public.respond_to_household_invitation((select token from v002_invites where kind='valid'), false);
  raise exception 'FAILED: již přijatá pozvánka byla odmítnuta';
exception when invalid_parameter_value then perform pg_temp.ok(true, '14 odmítnutí již přijaté pozvánky'); end $$;
do $$ begin
  perform public.respond_to_household_invitation('zcela-nahodny-neplatny-token', true);
  raise exception 'FAILED: náhodný token byl přijat';
exception when invalid_parameter_value then perform pg_temp.ok(true, '15 odmítnutí náhodného tokenu'); end $$;
reset role;

-- Expirovaná pozvánka vytvořená pouze jako test fixture.
insert into public.household_invitations(id,household_id,target_email,invited_by,token_hash,status,created_at,expires_at)
values (
  'eeeeeeee-0000-4000-8000-000000000001',(select household_a from v002_ids),'v002-c@example.invalid',
  '10000000-0000-4000-8000-000000000001',encode(digest('expired-token','sha256'),'hex'),'pending',now()-interval '8 days',now()-interval '1 day'
);
select set_config('request.jwt.claim.sub', '30000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"30000000-0000-4000-8000-000000000003","email":"v002-c@example.invalid","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  perform public.respond_to_household_invitation('expired-token', true);
  raise exception 'FAILED: expirovaná pozvánka byla přijata';
exception when invalid_parameter_value then
  if sqlerrm <> 'invitation_expired' then raise; end if;
  perform pg_temp.ok(true, '07 odmítnutí expirované pozvánky');
end $$;
reset role;

-- Audit musí obsahovat všechny události vytvořené v tomto běhu.
select pg_temp.ok(
  (select
    count(*) filter(where event_type='household_created')=1 and
    count(*) filter(where event_type='invitation_created')=2 and
    count(*) filter(where event_type='invitation_accepted')=1 and
    count(*) filter(where event_type='invitation_cancelled')=1 and
    count(*) filter(where event_type='household_name_changed')=1
   from public.household_audit_log where household_id=(select household_a from v002_ids)),
  '16 správné auditní záznamy'
);

-- Výsledek musí obsahovat všech 16 funkčních scénářů a obousměrné RLS útoky.
select test_name from v002_results order by test_name;
select pg_temp.ok((select count(*) >= 30 from v002_results), 'souhrn minimálně 30 databázových kontrol');
select count(*) as passed_database_checks from v002_results;

rollback;
