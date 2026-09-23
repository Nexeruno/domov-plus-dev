# Domov+ V0.0.3 (stabilizace před uzamčením)

Rodinná PWA: e-mailová autentizace, volitelné rychlé přihlášení, domácnosti s rovnocennými vlastníky, jednorázové e-mailové pozvánky a jeden sdílený online nákupní seznam pro každou domácnost. Nákup se mezi otevřenými klienty obnovuje přes Supabase Realtime. Bez internetu nelze provádět změny; offline fronta a synchronizace nejsou součástí V0.0.3.

## Technologie

- React + TypeScript + Vite
- Supabase Auth, PostgreSQL, RLS a Edge Functions
- Brevo transactional e-mail
- PWA pro Android a iPhone

## Lokální spuštění

1. Nainstalujte Node.js 22 nebo novější.
2. Spusťte `npm ci`.
3. Zkopírujte `.env.example` jako `.env.local`.
4. Doplňte pouze klientsky bezpečné hodnoty `VITE_SUPABASE_URL` a `VITE_SUPABASE_PUBLISHABLE_KEY`.
5. Spusťte `npm run dev`.

Do klientského prostředí nikdy nevkládejte `service_role`, Brevo klíč, SMTP klíč ani hesla.

## Databáze a serverová funkce

Migrace se aplikují v pořadí podle názvu ze složky `supabase/migrations/`.

Edge Function `send-household-invitation` vyžaduje serverové Supabase secrets:

- `BREVO_API_KEY`
- `INVITATION_SENDER_EMAIL`

Tyto hodnoty nejsou součástí repozitáře. Supabase URL a vestavěný klientský klíč poskytuje prostředí Edge Functions.

## Kontroly a vrstvy testů

```sh
npm test
npm run typecheck
npm run build
npm audit --omit=dev
```

Unit/component testy v `src/**/*.test.ts(x)` ověřují autentizační a domácnostní logiku, vykreslení chybového stavu, nákupní mutace a souběžné Realtime refreshe. Databázové/RLS sady `supabase/tests/households_v002_security.sql` a `supabase/tests/shopping_v003_security.sql` se spouštějí proti vývojové PostgreSQL databázi po aplikaci všech migrací v transakci a na konci provedou `rollback`. Samotné `npm test` databázové SQL testy nespouští.

Živé testy používají výhradně dočasné vývojové účty a proměnné prostředí z `.env.example`:

```sh
npm run test:e2e:api
npm run test:e2e:email
npm run test:e2e:shopping
```

`test:e2e:api` a `test:e2e:shopping` jsou živé API/Realtime integrační E2E skripty, ne test skutečného vykreslení v prohlížeči. Fyzický PWA test instalace, aktualizace a ovládání na Androidu a iPhonu je samostatný ruční krok. Živý E2E vyžaduje testovací účty a bezpečně poskytnuté proměnné prostředí; bez nich ho nelze považovat za spuštěný.

## Bezpečnost

- Izolace domácností je vynucena databázovým RLS a bezpečnými RPC.
- Klient nemá přímé oprávnění měnit členství, pozvánky ani audit.
- Pozvánkové tokeny jsou jednorázové; databáze ukládá pouze SHA-256 hash.
- E-mail pozvánky musí odpovídat e-mailu přihlášeného účtu.
- Skutečné secrets patří pouze do Supabase/GitHub nastavení, nikdy do Git historie.
- Nákupní položky se čtou jen v příslušné domácnosti; mutace jsou auditované RPC s kontrolou členství a verze. Aktivní duplicity omezuje databázový unikátní index.

## Rozsah V0.0.3

Obsahuje online nákup; Dnes a Energie jsou pouze nefunkční zástupné obrazovky. Neobsahuje offline synchronizaci, push notifikace, další části Energie, místnosti, smart-home ani AI. Verze není zatím označena tagem.
