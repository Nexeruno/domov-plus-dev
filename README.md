# Domov+ V0.0.2

Vývojový milník rodinné PWA: bezpečná autentizace, volitelné passkey přihlášení, domácnosti, rovnocenní vlastníci a jednorázové e-mailové pozvánky.

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

## Kontroly

```sh
npm test
npm run typecheck
npm run build
npm audit --omit=dev
```

Databázová/RLS sada je v `supabase/tests/households_v002_security.sql`. Běží v transakci a na konci provede `rollback`.

Živé testy používají výhradně dočasné vývojové účty a proměnné prostředí z `.env.example`:

```sh
npm run test:e2e:api
npm run test:e2e:email
```

## Bezpečnost

- Izolace domácností je vynucena databázovým RLS a bezpečnými RPC.
- Klient nemá přímé oprávnění měnit členství, pozvánky ani audit.
- Pozvánkové tokeny jsou jednorázové; databáze ukládá pouze SHA-256 hash.
- E-mail pozvánky musí odpovídat e-mailu přihlášeného účtu.
- Skutečné secrets patří pouze do Supabase/GitHub nastavení, nikdy do Git historie.

## Rozsah V0.0.2

Verze obsahuje pouze autentizaci, PWA, domácnosti a pozvánky. Neobsahuje nákupy, energii, notifikace, místnosti, smart-home ani AI.
