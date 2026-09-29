# Review odstranění Nákupu – 2026-09-28

## Hranice ověření

Pracovní větev `remove-shopping` vznikla z tagu `v0.0.3` (`b9e62eca74579364e14b22a22f03f46713917a6f`), nikoli revertováním rozpracované větve `v0.0.4-offline` (`b0daf94`). Veřejný klient stále používá starý release. Konektor poskytuje jeden dostupný Supabase projekt `ganyhcjzwgmiarkhcuej` (DEV); žádný zvlášť připojený produkční projekt nebyl zjištěn. V tomto review neproběhl žádný zápis do DB.

V `src` nezůstávají běhové importy, komponenty ani RPC Nákupu. Výjimka `'/nakup'` je pouze přesměrování starého odkazu na `/dnes` a jeho regresní test. Autentizace, domácnosti, pozvánky a jejich společná auditní infrastruktura nejsou v diffu funkčně změněny. Dnes a Energie jsou stále zástupné obrazovky.

## DEV preview

Samostatný vzdálený preview deployment není v tomto repozitáři nastaven. GitHub Pages workflow publikuje jedinou veřejnou stránku z `main`, proto preview větev nesmí použít tento workflow. Lokálně spuštěný produkční build s DEV klientskou konfigurací vrací HTTP 200 pro `/`, `/dnes`, `/energie`, `/nakup`, manifest, service worker a ikonu. Komponentové testy ověřují přepnutí Dnes/Energie a přesměrování `/nakup`; nejde o ověření reálného přihlášení, konzole prohlížeče ani telefonu. Žádné testovací přihlašovací údaje pro E2E nebyly k dispozici.

Při kontrole byl nalezen starší hashovaný balík v `dist`, který service worker zahrnul do precache. Build nyní před kompilací čistí pouze generované `dist`; opakovaný build obsahuje jeden aktuální aplikační JS a žádné nákupní RPC řetězce. Historické soubory v Git migracích se tím nemění.

## Přesná DEV inventura

| Objekt | Zjištění | Nový klient | Fáze B | Později |
| --- | --- | --- | --- | --- |
| `shopping_items` | 52 řádků, RLS zapnuto; `authenticated` má SELECT | Ne | REVOKE SELECT | Zachovat/archivovat data; DROP až po samostatném rozhodnutí |
| `shopping_sync_operations` | 103 řádků, RLS bez klientské policy a bez přímých grantů | Ne | Ponechat bez klientských grantů | Zachovat ledger do rozhodnutí o datech |
| `households.shopping_revision` a CHECK `households_shopping_revision_check` | Pouze nákupní revize | Ne | Ponechat | Odstranit až s datovým cleanupem |
| `household_audit_log` | Sdílená tabulka; 120 historických nákupních eventů šesti typů | Ne pro Nákup | Zachovat | Nákupní historii nemazat automaticky |
| `shopping_revision_changed` | BEFORE INSERT/DELETE/UPDATE trigger na `shopping_items` | Ne | Ponechat s historickou tabulkou | DROP až s tabulkou |
| `shopping_items` RLS policy | `Members can read household shopping items` | Ne | Ponechat jako obranu v hloubce při REVOKE | Později s tabulkou |
| `supabase_realtime` | Publikuje `public.shopping_items` | Ne | Odebrat tabulku z publikace | — |
| Indexy `shopping_items` | `shopping_items_pkey`, `shopping_items_one_active_name`, `shopping_items_household_recent`, `shopping_items_bought_recent`, `shopping_items_origin_revision` | Ne | Ponechat | S tabulkou |
| Indexy ledgeru | `shopping_sync_operations_pkey`, `shopping_sync_operations_add_item`, `shopping_sync_operations_household` | Ne | Ponechat | S ledgerem |
| Constraints nákupu | PK, FK na households/profiles, status/name/version/bought/deleted check; ledger PK/FK/operation_type check | Ne | Ponechat | S tabulkami |

Klientská RPC dostupná `authenticated`: `add_shopping_item`, `rename_shopping_item`, `mark_shopping_item_bought`, `restore_shopping_item`, `delete_shopping_item`, `undo_delete_shopping_item`, `list_current_shopping_items`, `get_shopping_snapshot`, `apply_shopping_operation`. `anon` k nim EXECUTE nemá. Tyto funkce nejsou volané novým klientem a po ověření fáze A lze jejich EXECUTE odebrat. Interní `shopping_error_for_unique` a trigger funkce `track_shopping_revision` nemají běžný klientský EXECUTE; jejich definice zůstávají do datového cleanupu. Žádná jiná `public` funkce neobsahuje v těle referenci na shopping.

DEV má migraci `20260925045351 shopping_offline_v004` aplikovanou. Dřívější V0.0.3 nákupní migrace jsou součástí Git historie a uzamčeného tagu; nelze je zpětně přepisovat ani považovat prázdnou migration history DEV za důkaz nepoužití.

## Rollout

1. **Fáze A:** Po review nasadit nový klient bez Nákupu, vyčistit výstupní build, ověřit online přihlášení, domácnost, pozvánky, Dnes/Energie, přímý starý odkaz a aktualizaci PWA na obou telefonech. Staré RPC a publikace v tomto kroku fungují pro dosud otevřené staré klienty.
2. Vyčkat na aktualizaci používaných PWA a ověřit, že nový klient nevyvolává žádný nákupní request ani Realtime subscription. Prohlédnout runtime logy a manuálně otestovat návrat starší PWA po offline období. Staré instalace mohou být dočasně aktivní; krátké prodlení je bezpečnější než okamžité odpojení backendu.
3. **Fáze B:** Až po ověření a koordinaci se starými klienty aplikovat a nejprve v DEV otestovat `supabase/pending/decommission_shopping_after_client_deploy.sql`: REVOKE přímého čtení tabulky a devíti klientských RPC, odebrání `shopping_items` z Realtime publication. Ověřit zamítnutí starých requestů a průchod auth/household/invitation RLS. Tento návrh zatím nebyl spuštěn.
4. **Pozdější cleanup:** Rozhodnout o exportu/retenci 52 položek, 103 ledger záznamů a 120 auditních eventů. Až poté samostatná forward-only migrace pro odstranění tabulek, indexů, triggeru, interních funkcí, policy a `households.shopping_revision`. Sdílený audit a domácnostní helpery zůstávají.

## Bezpečnost a otevřené hranice

Read-only kontrola potvrdila RLS na `profiles`, `households`, `household_memberships`, `household_invitations`, `household_audit_log`, `shopping_items` a ledgeru; domácnostní policy nebyly změněny. Neproběhly nové mutační adversariální testy ani browser E2E. Návrh odstavení API byl staticky porovnán s funkcemi a granty DEV, ale nesmí být považován za ověřenou DB migraci, dokud neprojde bezpečným transakčním testem na odděleném DEV prostředí. Aktuální veřejný klient by po jejím předčasném použití přišel o Nákup.
