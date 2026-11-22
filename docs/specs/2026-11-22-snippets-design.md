# Šablony a výběr signálu v editoru – návrh

Datum: 2026-11-22 · Factorio 2.1 · cílová verze 0.3.0

## Cíl

Novému hráči usnadnit první program: pod editorem lišta tlačítek se šablonami (podmínka, výstup, časovač,
prvky knihovny…) a nativní výběr signálu. Klik vloží kód se zástupnými slovy (`SIGNAL`, `NUMBER`, …), první
zástupné slovo se označí, takže ho hráč rovnou přepíše. Pruh nápovědy k psanému slovu je až další krok (0.3.x).

## Klíčová rozhodnutí

| Rozhodnutí | Důvod / trade-off |
|---|---|
| Vkládá se na **místo posledního psaní**, ne na kurzor | API `text-box` kurzor nezná (jen zápis `select`). Pozice se odvodí z rozdílu textů v `on_gui_text_changed` (společný začátek + konec). Klik myší bez psaní se nepozná – šablona pak přistane u posledního psaní; označení ukáže kam. Před prvním psaním = konec textu. |
| Šablona typu **výraz** (`inp["SIGNAL"]`) jde přímo na pozici, šablona typu **příkaz** (`if …:`) na nový řádek pod aktuální řádek s jeho odsazením (+4 za řádkem končícím `:`) | Příkaz vložený doprostřed řádku by byl vždy chybný. |
| Zástupná slova jsou **platné identifikátory / řetězce velkými písmeny** (`NUMBER`, `"SIGNAL"`) | Kód zůstane ASCII; nenahrazené slovo ohlásí překladač jako neznámé jméno / signál – hráč chybu vidí i v pruhu chyb. |
| Výběr signálu = nativní `choose-elem-button` (`elem_type = "signal"`), vloží kanonický klíč (`Resolver:canonical`) v uvozovkách | Hráči výběr znají; jméno se nepíše ručně. Pokud je označené zástupné `"SIGNAL"` z poslední šablony a text se od té doby nezměnil, signál ho nahradí. |
| Vložení jen když jde psát (`actions.view(ctl).can.edit`), jen na klik | V multiplayeru by automatický zápis mohl přepsat znaky na cestě; klik je vědomá akce. |
| Text šablon v kódu, popis (tooltip) v locale en+cs | Kód je Python (nepřekládá se), stejně jako příklady v `help.lua`. |

## Struktura modulů

- `scripts/gui/snippets.lua` (nový) – seznam šablon `{id, kind = "expr"|"stmt", code}` a čisté funkce:
  `caret_after(old, new)`, `insert(text, caret, snippet)` → `new_text, sel_start, sel_end, new_caret`.
  Pozice v **bajtech**; převod na znaky pro `select` (`char_index(text, byte)`), pokud se potvrdí, že `select` počítá znaky.
- `scripts/gui/editor.lua` – lišta pod editorem (`build_snippet_bar`), `select_range(refs, a, b)` (`focus` + `select`).
- `scripts/gui/events.lua` – klik `snippet`, `on_gui_elem_changed` (signál), sledování `st.caret` v `on_gui_text_changed`.
- `control.lua` – registrace `on_gui_elem_changed`.

## Otevřené otázky

- Počítá `select(a, b)` znaky, nebo bajty (čeština v komentářích)? Zůstane označení po zápisu `text` ze skriptu?
  → ověří task 1 ručně ve hře.
- Kolik tlačítek se vejde na šířku editoru (680 px) – jeden řádek ikonových tlačítek s tooltipem, nebo dva řádky textových.
