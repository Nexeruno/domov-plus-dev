# Domov+ – Energy foundation V0.1 (pracovní větev)

Rodinná PWA pro e-mailové přihlášení, volitelné rychlé přihlášení, domácnosti a jednorázové e-mailové pozvánky. Navigace obsahuje **Dnes** (zástupná obrazovka) a **Energie** (ruční odečty jednoho elektroměru na domácnost). Nákup je odstraněný.

## Lokální spuštění

Node.js 22+, `npm ci`, zkopírovat `.env.example` do `.env.local` a doplnit klientsky bezpečné `VITE_SUPABASE_URL` a `VITE_SUPABASE_PUBLISHABLE_KEY`. Potom `npm run dev`. Nikdy nevkládat serverové klíče ani hesla do klientské konfigurace.

## Kontroly

`npm test`, `npm run typecheck`, `npm run build` a `npm audit --omit=dev`.

Testy aplikace ověřují autentizaci, domácnosti, navigaci a výpočty/UI Energie. `supabase/tests/energy_v01_security.sql` je transakční DB/RLS test, který se spouští **až po migraci na odděleném DEV projektu**; `npm test` ho nespouští. Starší `supabase/tests/households_v002_security.sql` ověřuje domácnosti. Fyzické PWA ověření na Androidu/iPhonu je samostatný ruční krok.

## Energie

`supabase/migrations/20260929120000_energy_foundation_v01.sql` je aditivní delta nad existujícím schématem. Na výslovný pokyn vlastníka byla aplikována do jediného připojeného, veřejně používaného projektu jako migrace `20260929071711_energy_foundation_v01`. Nespouštějte ji znovu. Klient této pracovní větve dosud není veřejně nasazen. DB/RLS test `supabase/tests/energy_v01_security.sql` proběhl transakčně s rollbackem; souběžný zápis na dočasné domácnosti potvrdil serializaci a testovací data byla odstraněna. Přihlášené browser E2E zatím chybí. Klient čte pouze odečty své domácnosti přes RLS; nový odečet přidává přes ověřené RPC. Zápisy jsou jen v rostoucím pořadí dat a kumulativních stavů. První odečet je baseline. Každý další interval počítá `VT = nový VT − předchozí VT`, obdobně NT, celkem jejich součet a orientační cenu `VT × cena VT z nového odečtu + NT × cena NT z nového odečtu`. Délka je rozdíl kalendářních dat. Ceny jsou uživatelské odhady za kWh, ne fakturační rozpis. Neexistuje editace, mazání ani reset elektroměru.

## Databáze a historie

`supabase/migrations/` obsahuje historické migrační soubory včetně schématu předchozího uzamčeného releasu. Neměnit je zpětně. Aplikovaná delta V0.0.4 na DEV je pro dohledatelnost uložena v `supabase/history/applied-dev/`; **není to instrukce ji znovu spustit**. Současný DEV obsahuje historická nákupní data a synchronizační evidenci. Tato větev je nečte ani nemění. Jejich případné odstranění bude samostatný krok po záloze a posouzení dat.

Po veřejném nasazení klienta bez Nákupu byla do připojeného DEV projektu aplikována migrace `20260929062456_decommission_shopping_api_after_client_deploy.sql`. Odebrala klientská oprávnění k nákupním tabulkám a RPC a vyřadila `shopping_items` z Realtime. Historické položky, synchronizační ledger a audit zůstaly uložené. Skript je ve složce `supabase/history/applied-dev/`; znovu jej nespouštějte.

Edge Function `send-household-invitation` vyžaduje serverové `BREVO_API_KEY` a `INVITATION_SENDER_EMAIL`. Pozvánky, členství a audit domácností zůstávají chráněné stávajícími RLS a RPC pravidly. Fyzický test aktualizace dříve nainstalované PWA a přihlášený browser E2E zatím čekají na ověření.
