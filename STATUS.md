# Stav projektu

Aktualizováno: 2026-10-23

## Cíl

Verze 0.2.0 pro Factorio 2.1 (hráči na 2.0 zůstávají na 0.1.1), pak údržba 0.2.x: opravy chyb (i podle zpětné
vazby z portálu), výkon a kompatibilita – viz `ROADMAP.md` M2–M4.

## Hotovo

- Verze 0.1.1 vydaná na portálu (2026-10-11) pro Factorio 2.0.
- Verze 0.2.0 vydaná na portálu (2026-10-23) pro Factorio 2.1: `factorio_version` 2.1, oprava pádu s Pyanodonem 3.1
  (metatabulka prototypů `pyntr-*` + regresní test), `recycler` a závislosti `+` v `run-tests.sh`/`run-perf.sh`,
  banner Buy Me a Coffee v `docs/mod-portal.md`, changelog, docs.
- Ověřeno na 2.1.23: unit 315/0, vanilla 33/0 (2 skip), Space Age 35/0, mods pymodpack 3.1.0 / bobrevamp 3.0.1 /
  aai-industry 0.7.5 ✓, výkon beze změny, starý save z 2.0.77 (255 budov) se načte a programy běží.

## Rozpracováno

- Nic.

## Další krok

1. Projít zpětnou vazbu a hlášení chyb na portálu → seznam bugů sem.
2. Odložené drobnosti (`docs/development.md` → „Známá omezení“): undo (Ctrl+Z) bez kódu; překlad všech programů
   v prvním ticku po načtení; varianta testů `mods …` bez uložení a načtení.

## Otevřené otázky / slepé uličky

- ❌ Tab v editoru (`text-box`) – nedělá nic a skript ho nedoplní, API nezná pozici kurzoru. Nevracet se.
- ❌ Vlastní výběr signálu místo nativního `icon_selector` – nezná kurzor, rozhodnutí: nechat nativní.
- ❌ Logo Pythonu na budově – ochranná známka PSF; displej ukazuje jen řádky kódu.
