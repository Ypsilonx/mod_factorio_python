# Stav projektu

Aktualizováno: 2026-11-22

## Cíl

Verze 0.2.0 pro Factorio 2.1 (hráči na 2.0 zůstávají na 0.1.1), pak údržba 0.2.x: opravy chyb (i podle zpětné
vazby z portálu), výkon a kompatibilita – viz `ROADMAP.md` M2–M4.

## Hotovo

- Verze 0.1.1 vydaná na portálu (2026-10-11) pro Factorio 2.0.
- Verze 0.2.0 vydaná na portálu (2026-10-23) pro Factorio 2.1: `factorio_version` 2.1, oprava pádu s Pyanodonem 3.1
  (metatabulka prototypů `pyntr-*` + regresní test), `recycler` a závislosti `+` v `run-tests.sh`/`run-perf.sh`,
  banner Buy Me a Coffee v `docs/mod-portal.md`, changelog, docs.
- Verze 0.2.1 vydaná (2026-11-13): jen titulek „Pythonator – Programmable Combinator“ a popis se slovem combinator
  (připomínka hráče: podle jména nikdo nepozná, že jde o kombinátor). `publish.sh`: titul přes soubor (ne-ASCII),
  `--details` u nahrané verze jen aktualizuje údaje, kontrola verze obchází cache API.
- Verze 0.2.2 vydaná (2026-11-17, Factorio 2.1.24): oprava `red['x']` / `green['x']` („'wire_connector_id': real number expected got nil“,
  hlášení hráče) – `io.lua` `source.get` předával enginu výslovné nil jako druhý konektor. Chyba od začátku; skryl ji
  benevolentní fake v `tests/unit/fake_game.lua` (teď přísný jako engine) a chybějící test ve hře (`cases/inputs.lua`).
  Ověřeno: unit 316/0, vanilla 34/0 (2 skip), Space Age 36/0; bez opravy nové testy padají.
- Ověřeno na 2.1.23 (0.2.0): unit 315/0, vanilla 33/0 (2 skip), Space Age 35/0, mods pymodpack 3.1.0 / bobrevamp 3.0.1 /
  aai-industry 0.7.5 ✓, výkon beze změny, starý save z 2.0.77 (255 budov) se načte a programy běží.

- Verze 0.3.0 vydaná (2026-11-22, Factorio 2.1.24): lišta šablon + výběr signálu pod editorem (vkládá na místo
  posledního psaní – API kurzor nezná), `config(label, icon)`, ALT režim s řadami čtených vstupů a výstupů po drátech
  a vlastními šipkami na hraně (`hide-alt-info`), ikona z výběru v uvozovkách = klíč signálu, podrobná nápověda
  (config(), Okno a ALT, Knihovna s PID). Revize kódu před vydáním našla 4 chyby (opraveny + regresní testy).
  Ověřeno: unit 339/0, vanilla 35/0, Space Age 37/0, výkon = 0.2.2 na téže verzi hry. Portál: popis, 5 obrázků, GIF.

## Rozpracováno

- Nic. GIF v popisu na portálu (`docs/screenshots/alt-mode.gif`) se zobrazí až po pushi na GitHub.

## Další krok

1. Odpovědět hráči na portálu (hlášení red/green): opraveno v 0.2.2.
2. Projít zpětnou vazbu a hlášení chyb na portálu → seznam bugů sem.
3. Odložené drobnosti (`docs/development.md` → „Známá omezení“): undo (Ctrl+Z) bez kódu; překlad všech programů
   v prvním ticku po načtení; varianta testů `mods …` bez uložení a načtení.

## Otevřené otázky / slepé uličky

- Ponaučení: falešné objekty enginu v unit testech musí být stejně přísné jako engine (výslovné nil u volitelného
  argumentu engine odmítne) a každá cesta k API (inp/red/green…) potřebuje aspoň jeden integrační test ve hře.

- ❌ Tab v editoru (`text-box`) – nedělá nic a skript ho nedoplní, API nezná pozici kurzoru. Nevracet se.
- ❌ Vlastní výběr signálu místo nativního `icon_selector` – nezná kurzor, rozhodnutí: nechat nativní.
- ❌ Logo Pythonu na budově – ochranná známka PSF; displej ukazuje jen řádky kódu.
- ❌ Posun šipek enginu přes `input/output_connection_bounding_box` – nemá vliv.
- ❌ Skrýt šipky enginu při najetí myší – `hide-alt-info` vypne jen ALT šipky, při najetí je hra kreslí dál.
  (Dřívější „nefunguje“ u `hide-alt-info` byl test bez restartu hry – prototypy se čtou jen při startu.)
- ❌ `rendering.draw_circle` jako podklad ikony – nemá `render_layer`, kreslí se přes ikonu.
