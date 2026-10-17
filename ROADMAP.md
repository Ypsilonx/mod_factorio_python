# Roadmap

## Vize

Pythonator nahrazuje spletité sítě kombinátorů ve velkých továrnách čitelným kódem s průhledným a
deterministickým časováním (vstupy → `loop()` → výstupy každý tick). Další vývoj: stabilita, výkon a
kompatibilita s velkými modpacky.

## Milníky

### M1 – první vydání (0.1.0 / 0.1.1) ✅
- Cíl: jazyk, budova, GUI editor, knihovna kombinátorů, vlastní grafika na portálu.
- Hotovo když: vydáno na mods.factorio.com, testy zelené (splněno 2026-10-11).

### M2 – opravy chyb ⏳
- Cíl: opravené chyby nahlášené hráči a odložené drobnosti (undo bez kódu, …).
- Hotovo když: každá oprava má regresní test (unit nebo integrační) a je ve vydané verzi s changelogem.

### M3 – výkon ⏳
- Cíl: nižší cena na budovu – hlavní náklad je čtení signálů z enginu; žádné zaškobrtnutí po načtení hry
  (překlad všech programů v prvním ticku).
- Hotovo když: `run-perf.sh` ukáže zlepšení proti tabulce v `docs/development.md` a výsledky jsou tam zapsané.

### M4 – kompatibilita ⏳
- Cíl: ověření s dalšími overhauly a Space Age obsahem; varianta testů `mods …` přes uložení a načtení.
- Hotovo když: tabulka „Kompatibilita“ v `docs/development.md` má nové řádky s ✓ a aktuální verzí hry.

## Mimo rozsah (zatím neděláme)

- Displejové API, úlohy (multitasking), f-stringy, auto-odsazení, zvýraznění syntaxe, sdílené proměnné mezi
  kontroléry, čtení stavu entit mimo obvodovou síť – viz spec „Mimo rozsah v0.1“; otevřít jen na základě poptávky.
- Režim „koprocesor“ ze skrytých vanilla kombinátorů – jiný časový model (zpoždění), případně později jako volitelný.
