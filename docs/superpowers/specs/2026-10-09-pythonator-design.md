# Pythonator – návrh (v0.1)

Datum: 2026-10-09 · Factorio 2.0 (vanilla i Space Age)

## Cíl

Programovatelná budova pro obvodovou síť, ve které hráč píše řídicí logiku v podmnožině Pythonu.
Hlavní požadavek je **průhledné a deterministické časování**: je vždy jasné, ve kterém ticku se čtou vstupy,
kdy proběhne logika a kdy se objeví výstupy. Budova má nahradit spletité sítě kombinátorů ve velkých továrnách
(hystereze, PID, sekvence, zpracování mnoha signálů) čitelným kódem.

Inspirace: fCPU (mikrokontrolér ve hře), Moon Logic 2 / LuaComb++ (Lua v kombinátoru). Odlišení: jazyk podobný
Pythonu, model mikrokontroléru se superloop (ne instrukce za tick), ikony signálů přímo v kódu.

## Co hráč dostane

- Budovu **Pythonator** (2×2, vstupní a výstupní strana jako u aritmetického kombinátoru).
- Editor kódu ve vlastním okně se stavem, proměnnými, vstupy a výstupy, tlačítky Start/Stop/Krok.
- Jazyk = podmnožina Pythonu, programy jdou 1:1 spustit i v normálním Pythonu (s náhradou `inp`/`out`).

## Programový model (mikrokontrolér se superloop)

```python
config(interval=1, outputs="hold")   # volitelné, jen na nejvyšší úrovni

count = 0                            # nejvyšší úroveň = inicializace, proběhne jednou

def loop():                          # povinná, volá se 1× za interval
    global count
    count += 1
    if inp[item=iron-plate] < 100:   # v editoru zobrazeno jako ikona (rich text)
        out["recipe:iron-plate"] = 1
```

### Časová garance

```
tick T:   načtení vstupů (= co ostatní poslali v T−1) → loop() → zápis výstupů
tick T+1: ostatní entity vidí naše výstupy
```
Zpoždění vstup → výstup je přesně 1 tick, stejně jako u vanilla kombinátoru. `loop()` vždy doběhne v rámci
ticku – složitější program tick neprodlouží „přes hranu“, jen stojí víc času CPU (UPS).

### Proměnné a stav

- **Globální proměnné** (nejvyšší úroveň modulu) = stav; přežijí tick, uložení i načtení hry.
- **Lokální proměnné** ve funkcích se po návratu zahodí.
- Zápis do globální proměnné uvnitř funkce vyžaduje `global` (jako v Pythonu). Chybějící `global` při
  přiřazení do jména, které je globální, ohlásí překladač jako chybu s řádkem (místo tiché lokální proměnné).
  Mutace (`d[k] = v`, `l.append(x)`) `global` nepotřebuje.
- Uložitelné hodnoty: `int/float`, `bool`, `None`, `str`, `list`, `dict`, tuple. Funkce nejsou hodnoty
  (nelze je přiřadit do proměnné ani předat) – nejdou uložit do savu.
- `def` na nejvyšší úrovni se **vyzdvihnou** (jsou definované před spuštěním inicializace). Odchylka od
  Pythonu, nutná proto, aby po načtení hry šly funkce znovu přeložit bez opakování inicializace.

### Životní cyklus

| Událost | Chování |
|---|---|
| Stop / Start (tlačítko) | `loop()` se přestane / začne volat, stav zůstává |
| Výpadek proudu | jako Stop; `tick` stojí; výstupy zůstanou |
| Nahrání nového kódu | překlad; při úspěchu inicializace od nuly (globály z nového kódu), výstupy vymazány; při chybě překladu běží dál starý program a zobrazí se chyba |
| Chyba (překlad, běh, watchdog, paměť) | stav CHYBA, `loop()` se nevolá, výstupy zůstanou, zobrazí se řádek a zpráva |
| Zbourání | stav zmizí |
| Copy-paste / blueprint | přenáší se kód (a běží/stojí), ne stav; nová budova začne inicializací |
| Načtení hry | kód se znovu přeloží, globály se obnoví ze `storage`, inicializace **neproběhne** |

### Čas

| Jméno | Význam |
|---|---|
| `tick` | ticky běhu programu od nahrání kódu; stojí při Stop a výpadku proudu |
| `game_tick` | absolutní tick hry (synchronizace více budov) |
| `dt` | ticků od minulého volání `loop()` (= `interval`, po výpadku proudu víc) |
| `config(interval=N)` | `loop()` každých N ticků (výchozí 1) |

Časovače nejsou vestavěné – vzor `start = tick` / `tick - start >= N` (v2 případně `Timer`, `rising()`).
Pozn.: signál je int32 – poslat `tick` na výstup přeteče po ~414 dnech běhu (dokumentovat, doporučit rozdíly).

## Signály

### Čtení a zápis

| Jméno | Význam |
|---|---|
| `red[k]`, `green[k]` | vstup jen z jednoho drátu |
| `inp[k]` | součet obou (jako vanilla kombinátor) |
| `out[k] = v` | výstup na oba dráty |
| `out_red[k]`, `out_green[k]` | výstup jen na jeden drát |
| `.items() .keys() .values()`, `k in inp`, `len()` | procházení příchozích / nastavených signálů |
| `out.clear()` | vymazat výstupy |

Chybějící signál čte 0 (žádná `KeyError`). `config(outputs="hold")` (výchozí) – výstupy drží poslední hodnotu;
`"clear"` – výstupy se před každým `loop()` vymažou. Zapsaná hodnota se na výstupu ořízne na celé číslo
(`int()` směrem k nule) a přeteče do int32 jako u vanilla kombinátoru.

### Klíče signálů

Signál ve hře = `SignalID {type, name, quality}`. Zápisy v kódu:

| Zápis | SignalID |
|---|---|
| `"iron-plate"` | item / fluid / virtual – podle toho, kde jméno existuje |
| `"iron-plate@rare"` | totéž s kvalitou |
| `"recipe:iron-plate"`, `"entity:…"`, `"space-location:…"`, `"asteroid-chunk:…"`, `"quality:…"` | explicitní typ |
| `[item=iron-plate]`, `[item=iron-plate,quality=rare]`, `[fluid=…]`, `[virtual-signal=…]`, `[recipe=…]`, … | rich text tag = literál klíče |

- Bez prefixu se hledá jen mezi item/fluid/virtual; existuje-li jméno ve více z nich, je to chyba překladu
  s návrhem prefixu. Ostatní typy vyžadují prefix vždy.
- Rich text tag je v lexeru samostatný token (v Pythonu by byl neplatnou syntaxí, kolize se seznamem nehrozí).
- Konstantní klíče se ověřují **při překladu** proti `prototypes.*` (včetně cizích modů); překlep → chyba
  s řádkem a nápovědou nejbližšího jména. Klíče skládané za běhu se ověřují při použití (chyba za běhu).
- Klíče vracené při procházení mají kanonický tvar (prefix jen kde je nutný, `@quality` jen pokud není normal).

## Jazyk (podmnožina Pythonu)

| Oblast | v0.1 |
|---|---|
| Typy | `int`, `float` (interně Lua double), `bool`, `None`, `str`, `list`, `dict`, `tuple` |
| Operátory | `+ - * / // % **`, porovnání vč. řetězení `0 < x < 10`, `and or not`, `in`, `not in`, `is`, `is not`, bitové `& \| ^ ~ << >>` (32 bitů se znaménkem), podmíněný výraz `a if c else b` |
| Příkazy | přiřazení, rozbalení (`a, b = …`), rozšířené přiřazení (`+=` …), `if/elif/else`, `while`, `for … in` (range, list, tuple, dict, `.items()`…), `break`, `continue`, `pass`, `return`, `global` |
| Funkce | `def` s pozičními parametry, `return`; rekurze povolená (hlídá watchdog) |
| Vestavěné | `abs min max round int float str bool len range sum sorted print` |
| Metody | `list`: `append pop insert remove index clear`; `dict`: `get items keys values pop clear`; `str`: `upper lower startswith endswith split join replace` |
| Indexy | `x[i]`, záporné indexy, řezy `x[a:b]` u list/str/tuple |
| Komentáře | `#` |
| Odsazení | libovolné konzistentní mezery; tabulátor = 1 úroveň; míchání v rámci jednoho bloku = chyba |

**Mimo v0.1:** třídy, `import`, `try/except`, `lambda`, comprehensions, f-stringy (kandidát v2), `with`,
generátory/`yield`, `*args/**kwargs`, výchozí a pojmenované argumenty, `nonlocal`, vnořené `def`, `set`, `del`.

Sémantika čísel: `/` vždy desetinné, `//` a `%` s pythonovským zaokrouhlením dolů, dělení nulou = chyba běhu.
`str()` formátuje jako Python (`3`, `0.1`, `1e+20`), nezávisle na `tostring` Lua. `int` a `float` se
nerozlišují (všechna čísla jsou Lua double), takže celé desetinné číslo se vypíše bez `.0` (`6 / 2` → `3`) –
zdokumentovaná odchylka; sledování typu čísla by zpomalilo každou operaci.

Chyby běhu (`TypeError`, `IndexError`, dělení nulou …) zastaví kontrolér ve stavu CHYBA s řádkem zdrojového kódu.
`print()` zapisuje do ladicího logu budovy (posledních 50 řádků, zobrazeno v GUI; log se neukládá do globálů).

## Překladač a běh

```
zdroj → lexer → parser (AST) → kontrola (global/local, klíče signálů, nepodporované konstrukce)
      → generátor Lua 5.2 → load() v sandboxu → zkompilované funkce (cache mimo storage)
```

- Generuje se zdroj Lua 5.2 a kompiluje `load()` (text, ne bytecode) s prostředím obsahujícím jen runtime
  knihovnu – žádný přístup k `game`, `storage`, `script`.
- **Řádek zdroje**: každý příkaz ve vygenerovaném kódu nejdřív zapíše své číslo řádku do lokální proměnné
  (`_ln = 5;`); při chybě ho VM přečte. Stojí to jedno přiřazení na příkaz, ale nezávisí to na knihovně
  `debug` ani na formátu chybových hlášek Lua (původně zvažovaná mapa řádků Lua → zdroj by se neobešla bez
  rozboru textu chyby, který u chyb vyhozených jako tabulka nemá pozici).
- Globály v generovaném kódu = pole tabulky stavu ve `storage` (ne upvalues Lua) → uložení hry je triviální.
- Cache zkompilovaných funkcí je odvozená ze `storage` (kód), na každém klientovi se sestaví stejně a líně
  při prvním použití → deterministické, multiplayer bezpečné.

### Uložení stavu ve `storage` (pravidla Factoria)

Stav kontroléru: `storage.controllers[unit_number] = {code, running, error, globals, outputs, tick, …}`.

| Past | Řešení |
|---|---|
| Metatabulky se do savu neukládají | runtime typy `list`, `dict`, `tuple`, `None` mají metatabulky registrované přes `script.register_metatable` (registrace při načtení modulu, ne v `on_load`) |
| Lua tabulka nemá pořadí vložení | `dict` drží vlastní pole klíčů v pořadí vložení → iterace jako v CPythonu |
| `nil` v tabulce = díra, špatná délka | `None` je samostatná hodnota (sentinel), `list` drží vlastní délku `n` |
| Funkce / closures nejdou uložit | přeložený kód jen v cache mimo `storage` (viz výše); funkce nejsou hodnoty jazyka |
| `on_load` nesmí měnit `storage` | cache se staví líně při prvním použití, `storage` se nemění |
| Sdílené reference a cykly (`a = []; b = a`) | serializace `storage` je zachovává; počítání paměti používá množinu navštívených tabulek |

Tyto vlastnosti pokrývá integrační test „uložit → načíst → pokračovat“ (list/dict/None/tuple/sdílená reference
v globálech, pořadí iterace dict po načtení).

### Pojistky (skrytá vrstva v generovaném kódu)

| Pojistka | Mechanismus | Výchozí limit | Nastavení |
|---|---|---|---|
| **Watchdog** | odečtení rozpočtu na každém průchodu smyčkou a volání funkce; rozpočet se obnoví na začátku každého `loop()` i inicializace | 10 000 operací / tick | map setting |
| **Paměť** | po `loop()` se jednou za 60 ticků (a po inicializaci) spočítají prvky všech globálů (s předčasným ukončením nad limitem) | 10 000 prvků | map setting |

Překročení → stav CHYBA s řádkem (watchdog: řádek smyčky/volání; paměť: kontrola neví řádek, hlásí název
největší proměnné). Obě pojistky jsou nezávislé na délce běhu hry (rozpočet je per tick, paměť je velikost).

### Vstupy a výstupy (runtime)

- `inp`/`red`/`green` jsou líné proxy: `x[k]` volá `get_signal` jen pro daný signál; procházení načte
  `get_signals` jednou za tick a výsledek se v ticku uloží.
- Výstupy: rozdíl proti minulému ticku se zapíše do dvou skrytých konstantních kombinátorů (jeden napojený na
  červený, druhý na zelený výstupní konektor). Nezměněné výstupy nic nestojí.

## Budova, recept, výzkum

| Parametr | Hodnota | Důvod |
|---|---|---|
| Interní jméno modu | `Pythonator` (ověřeno volné na portálu 2026-10-09; po publikaci neměnné) | |
| Prefix | `pyntr` / `pyntr-` | krátký, bez kolize (samotné `py` používá Pyanodon) |
| Prototyp | odvozený z `arithmetic-combinator` (rotace, dráty, vstup/výstup, blueprint zdarma), vlastní chování vypnuté | vzor Moon Logic |
| Velikost | 2×2 | jiná kategorie než kombinátor (1×2) |
| Energie | elektrická, 50 kW (konstanta v `prototypes/entity.lua`) | „počítač“, dražší než kombinátor |
| Výzkum | vlastní `pyntr-pythonator`; prerekvizity `circuit-network`, `advanced-circuit`; věda červená + zelená + modrá | úroveň za kombinátory |
| Recept | 5× advanced-circuit, 2× decider-combinator, 2× arithmetic-combinator, 5× steel-plate | vzniká z kombinátorů |
| Grafika v0.1 | tint/zvětšení vanilla kombinátoru; vlastní model z Blenderu později | nejdřív logika |

Hodnoty energie, receptu a limitů pojistek budou v tabulce „Kde ladit hodnoty“ v `docs/development.md`.

## GUI

Vlastní okno místo vanilla okna kombinátoru (`on_gui_opened`):

```
┌─ Pythonator ──────────────────────────────────────────────┐
│ ┌─ kód (text-box, icon_selector, rich text) ┐ ┌─ stav ────┐│
│ │ ...                                       │ │ ● BĚŽÍ    ││
│ │                                           │ │ tick, cena││
│ │                                           │ ├─ globály ─┤│
│ │                                           │ ├─ vstupy R|G┤│
│ └───────────────────────────────────────────┘ ├─ výstupy ─┤│
│ [vložit signál]                               └───────────┘│
│ ⚠ chyba: řádek, zpráva          print log (rozbalovací)    │
│ [▶ Nahrát a spustit] [⏸ Stop] [⏭ Krok 1 tick] [? Nápověda] │
└────────────────────────────────────────────────────────────┘
```
- „Krok 1 tick“ funguje jen ve stavu Stop: provede jeden `loop()` a obnoví zobrazení.
- „Cena“ = počet operací posledního `loop()` (z watchdogu) vůči limitu.
- Panely stavu se obnovují jen při otevřeném okně (`on_nth_tick`, interval jako konstanta).
- Úpravy textu se neprojeví, dokud hráč nestiskne „Nahrát a spustit“.

## Nastavení (map settings)

`pyntr-watchdog-limit` (10 000), `pyntr-memory-limit` (10 000).

## Plánování (UPS)

Kontroléry se spouštějí plánovačem po ticích podle `interval`, ne průchodem všech entit každý tick.
Zastavené / v chybě / bez proudu se nezařazují (bez proudu: kontrola stavu v plánovaném ticku, přeplánování
s delším intervalem, dokud proud nebude).

## Testy

1. **Unit (Lua)** – lexer, parser, kontroly, generátor, runtime knihovna (čísla, `str()`, `//`, `%`, bitové
   operace, klíče signálů, pojistky). Pozor: lokální Lua je 5.3, hra 5.2 – generovaný kód nesmí používat
   konstrukce 5.3 a testy nesmí záviset na `tostring` čísel.
2. **Konformita s Pythonem** – sada ukázkových programů `tests/conformance/*.py`; očekávaný výstup (`print`
   a výstupy po N tickách) vygenerovaný jednou v CPythonu s náhradou `inp`/`out`, uložený v repu; náš
   interpret musí dát stejný výsledek.
3. **Integrační (headless)** – časová garance (vstup v T → výstup v T+1), hold/clear, out_red/out_green,
   výpadek proudu, uložení a načtení, blueprint, watchdog a paměť, vanilla i Space Age (kvalita v klíčích).
4. **Výkon** – N kontrolérů s typickým programem vs. prázdná mapa, ms/tick do `docs/development.md`.

## Rizika k ověření prototypem (jako první)

1. `text-box` s `icon_selector` a rich textem ve víceřádkovém editoru – použitelnost, kurzor, kopírování.
2. Klávesa Tab v `text-box`.
3. Čísla řádků vedle `text-box` (synchronní posun) – podívat se, jak to řeší fCPU.
4. Velikost 2×2 u prototypu odvozeného z kombinátoru (body drátů, vstup/výstup).
5. Montovna se „Set recipe“ a signál typu `recipe` vs. `item`.

## Mimo rozsah v0.1

Displejové API, vestavěné časovače a detekce hran, úlohy (multitasking), f-stringy, auto-odsazení,
zvýraznění syntaxe, sdílené proměnné mezi kontroléry, čtení stavu entit mimo obvodovou síť, vlastní grafika.

## Klíčová rozhodnutí

| Rozhodnutí | Volba | Důvod |
|---|---|---|
| Časový model | superloop, celý `loop()` v jednom ticku | předvídatelnost; instrukce/tick (fCPU) zpomaluje reakci bez užitku |
| Provedení jazyka | překlad do Lua + `load()` | 10–50× rychlejší než interpret v Lua |
| Stav | globály v `storage`, inicializace na nejvyšší úrovni | uložitelnost; coroutine / closures uložit nejdou |
| `global` | vyžadovat jako Python | kód jde testovat v CPythonu |
| Výstupy | volitelně hold / clear, výchozí hold | model mikrokontroléru (`digitalWrite`) |
| Klíče | text + rich text tagy, ověření při překladu | jména jako ve hře, ikony místo psaní |
| Nový kód | reset globálů | změna konstant se musí projevit |
| Watchdog | zastavit s chybou | žádné napůl provedené ticky s nekonzistentním stavem |
