# Domov+ – pracovní větev bez Nákupu

Rodinná PWA pro e-mailové přihlášení, volitelné rychlé přihlášení, domácnosti a jednorázové e-mailové pozvánky. Přihlášený člen domácnosti vidí dvě části hlavní navigace: **Dnes** a **Energie**. V této verzi jde pouze o zástupné obrazovky; jejich budoucí funkce nejsou implementované.

## Lokální spuštění

Node.js 22+, `npm ci`, zkopírovat `.env.example` do `.env.local` a doplnit klientsky bezpečné `VITE_SUPABASE_URL` a `VITE_SUPABASE_PUBLISHABLE_KEY`. Potom `npm run dev`. Nikdy nevkládat serverové klíče ani hesla do klientské konfigurace.

## Kontroly

`npm test`, `npm run typecheck`, `npm run build` a `npm audit --omit=dev`.

Testy aplikace ověřují autentizaci, domácnosti, načtení domácnosti, pozvánkové cesty a dvoupoložkovou hlavní navigaci. `supabase/tests/households_v002_security.sql` je samostatná databázová/RLS sada; `npm test` ji nespouští. `npm run test:e2e:api` a `npm run test:e2e:email` vyžadují oddělené vývojové účty a prostředí. Fyzické PWA ověření na Androidu/iPhonu je samostatný ruční krok.

## Databáze a historie

`supabase/migrations/` obsahuje historické migrační soubory včetně schématu předchozího uzamčeného releasu. Neměnit je zpětně. Aplikovaná delta V0.0.4 na DEV je pro dohledatelnost uložena v `supabase/history/applied-dev/`; **není to instrukce ji znovu spustit**. Současný DEV obsahuje historická nákupní data a synchronizační evidenci. Tato větev je nečte ani nemění. Jejich případné odstranění bude samostatný krok po záloze a posouzení dat.

`supabase/pending/` obsahuje návrh nedestruktivního odstavení starých nákupních API. **Není aplikovaný ani otestovaný transakčním spuštěním v databázi.** Musí se zkontrolovat vůči cílovému prostředí a časovat až po nahrazení veřejného klienta. Dokud nebude aplikován, staré API zůstává dostupné pro oprávněné uživatele starší verze.

Edge Function `send-household-invitation` vyžaduje serverové `BREVO_API_KEY` a `INVITATION_SENDER_EMAIL`. Pozvánky, členství a audit domácností zůstávají chráněné stávajícími RLS a RPC pravidly. Tato větev nemění databázi, `main`, tagy ani veřejné nasazení.
