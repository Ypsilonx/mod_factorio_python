# Stav projektu

Aktualizováno: 2026-10-17

## Cíl

Údržbová verze 0.1.x: opravy chyb (i podle zpětné vazby z portálu), výkon a kompatibilita – viz `ROADMAP.md` M2–M4.

## Hotovo

- Verze 0.1.1 vydaná na portálu (2026-10-11): jazyk, budova, GUI editor, knihovna kombinátorů, grafika z Blenderu.
- Testy zelené (2026-10-17): unit 315/0, integrační vanilla 33/0 (2 skip).
- Integrační runner generuje povrch podle počtu testů (nové testy nevyjedou z mapy).

## Rozpracováno

- Nic.

## Další krok

1. Projít zpětnou vazbu a hlášení chyb na portálu → seznam bugů sem.
2. Kandidáti z odložených drobností (`docs/development.md` → „Známá omezení“): undo (Ctrl+Z) vrátí budovu bez
   kódu (undo-redo API 2.0); po načtení hry se všechny programy překládají v prvním ticku (rozložit);
   varianta testů `mods …` bez uložení a načtení.

## Otevřené otázky / slepé uličky

- Které chyby nahlásili hráči? (zatím nezjištěno)
- ❌ Tab v editoru (`text-box`) – nedělá nic a skript ho nedoplní, API nezná pozici kurzoru. Nevracet se.
- ❌ Vlastní výběr signálu místo nativního `icon_selector` – nezná kurzor, rozhodnutí: nechat nativní.
- ❌ Logo Pythonu na budově – ochranná známka PSF; displej ukazuje jen řádky kódu.
