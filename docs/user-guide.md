# Pythonator – uživatelská příručka

Pythonator je budova pro obvodovou síť, kterou programuješ v podmnožině Pythonu. Místo spletité sítě
kombinátorů napíšeš čitelný kód: každý tick se načtou vstupy, proběhne `loop()` a zapíšou se výstupy.
Zpoždění je přesně 1 tick, stejně jako u kombinátoru.

## Jak začít

1. Vyzkoumej **Pythonator** (po obvodové síti a pokročilých obvodech), vyrob ho a postav.
2. Připoj dráty: vstupní strana čte, výstupní posílá signály (jako aritmetický kombinátor).
3. Klikni na budovu. Otevře se okno s editorem, napiš program a stiskni **▶**.

```python
def loop():
    if inp["iron-plate"] < 100:
        out["signal-A"] = 1
    else:
        out["signal-A"] = 0
```

## Okno

| Část | Co dělá |
|---|---|
| Editor | kód s čísly řádků. Ikonu signálu vložíš výběrem v rohu editoru. Odsazuj mezerami, Tab v editoru nefunguje. |
| ▶ Play | změněný kód přeloží a spustí od nuly. Nezměněný kód nechá pokračovat. |
| ⏸ Pauza | zastaví volání `loop()`, stav zůstane. Při pauze jde kód upravovat. |
| ⟳ Reset | vynuluje globální proměnné a znovu spustí inicializaci nahraného kódu. |
| ⏭ Krok | při pauze provede jeden `loop()`. |
| ? | nápověda s příklady, které jde vložit do editoru. |
| Stav | BĚŽÍ / PAUZA / CHYBA / BEZ PROUDU, tick a cena posledního běhu proti limitu watchdogu. |
| Panely | vstupy z červeného a zeleného drátu, výstupy (skutečný stav drátu), globální proměnné, prvky knihovny. |
| Log | výpis `print()` (posledních 50 řádků). |

Za běhu je editor jen pro čtení. Rozepsaný kód se uloží i se hrou a nezmizí, když okno zavřeš. Chyba se zobrazí
v červeném pruhu s číslem řádku a kliknutím na pruh se editor posune na chybný řádek. Když nový kód neprojde
překladem, nahraný program se nezmění.

## Programový model

- Kód na nejvyšší úrovni proběhne **jednou** při spuštění, je to inicializace. `loop()` se volá každý tick.
- **Globální proměnné** drží stav mezi ticky i po uložení hry. Přiřazení do nich uvnitř funkce vyžaduje
  `global jméno`, stejně jako v Pythonu.
- Čas: `tick` (ticky běhu programu), `game_tick` (tick hry), `dt` (ticků od minulého `loop()`).
- `config(interval=N, outputs="hold")`: `loop()` jen každých N ticků. Volba `outputs="clear"` výstupy
  před každým `loop()` vymaže.

## Signály

| Zápis | Význam |
|---|---|
| `inp[k]`, `red[k]`, `green[k]` | vstup z obou drátů, jen z červeného, jen ze zeleného. Chybějící signál čte 0. |
| `out[k] = v`, `out_red[k]`, `out_green[k]` | výstup na oba dráty nebo jen na jeden |
| `"iron-plate"`, `"iron-plate@rare"`, `"recipe:iron-plate"`, `[item=iron-plate]` | klíče signálů (kvalita, typ, ikona) |
| `for k, v in inp.items()`, `k in inp`, `len(inp)`, `out.clear()` | procházení signálů |

Recept montovny se nastaví signálem předmětu: `out["iron-gear-wheel"] = 1`.

## Knihovna kombinátorů

Vektorové operace nad celou sadou signálů jedním voláním:

```python
config(outputs="clear")

def loop():
    out.set(inp.where(">", 1000).each("-", 1000))   # přebytky nad 1000
    out["signal-A"] = inp.count(">", 0)              # počet nenulových signálů
```

| Funkce | Význam |
|---|---|
| `x.each(op, v)` | každý signál op v jako aritmetický kombinátor: `+ - * / % ** << >> & \| ^`. Celá čísla, `/` a `%` k nule, dělení nulou dá 0. |
| `x.where(op, v)` | jen signály splňující podmínku `< <= > >= == !=` |
| `x.count()`, `x.count(op, v)`, `x.sum()`, `x.max_key()`, `x.min_key()` | počet, součet a klíč s největší či nejmenší hodnotou |
| `out.set(d)`, `out.add(d)` | výstupy nahradí sadou, nebo ji k nim přičte |

Stavové prvky mají stav pod jménem. Ten přežije uložení hry a Reset ho smaže. Každý prvek potřebuje vlastní jméno.

| Funkce | Výsledek |
|---|---|
| `latch(jméno, set, reset)` | klopný obvod, přednost má reset |
| `timer(jméno, perioda)` | `True` jednou za periodu ticků |
| `edge(jméno, hodnota)` | `1` náběžná hrana, `-1` sestupná, `0` žádná |
| `counter(jméno, krok=1, reset=False)` | počítadlo |
| `delay(jméno, hodnota, n)` | hodnota z doby před n voláními `loop()` |
| `pid(jméno, žádaná, měřená, kp, ki, kd, lo, hi)` | PID regulátor s volitelnými mezemi |

## Jazyk

Podporované typy jsou `int`, `float`, `bool`, `None`, `str`, `list`, `dict` a `tuple`. Z příkazů jsou k dispozici
`if/elif/else`, `while`, `for`, `def`, `return` a `global`. Vestavěné funkce jsou `abs min max round int float str bool
len range sum sorted print`.

Nepodporuje třídy, `import`, `try/except`, `lambda`, comprehensions ani f-stringy.

Odchylky od Pythonu: `int` a `float` se nerozlišují, takže `6 / 2` vypíše `3`. Funkce `def` na nejvyšší úrovni
jsou dostupné i před svou definicí.

## Výkon (UPS)

Každé spuštění `loop()` stojí čas procesoru. Cenu všech budov ukáže F4 → `show-time-usage` → řádek
`mod-Pythonator`, cenu jednoho programu pruh v okně. Rozpočet ticku je 16,7 ms.

1. **Interval** je největší úspora: `config(interval=N)` spustí `loop()` jen každý N-tý tick. Pro bezpečnost
   a regulaci se hodí 1, pro výrobu a sklady 10–60, pro pomalé věci 300 a víc. Budovy se stejným intervalem
   běží každá v jiném ticku, takže nevzniká špička.
2. **Výstup zapisuj jen při změně.** `out.clear()` a nový zápis každý tick stojí víc než samotný program.
3. **Čti jen potřebné signály.** `inp["x"]` je levné, procházení všech signálů načte celou síť.

Orientačně, 150 budov s jednoduchou sekvencí (měřeno ve hře): zápis každý tick ~2,4 ms za tick, zápis
jen při změně ~1,2 ms, `config(interval=60)` ~0,2 ms. Pár desítek programů s intervalem 1 je v pořádku
i ve velké továrně. Stovky budov s intervalem 1 už je vhodné ladit.

## Pojistky

- **Watchdog** zastaví program, který v jednom ticku udělá víc operací než limit (výchozí 10 000).
- **Limit paměti** hlídá velikost globálních proměnných (výchozí 10 000 prvků).

Oba limity jsou v nastavení mapy. Překročení přepne budovu do stavu CHYBA a ukáže řádek.

## Blueprinty a kopírování

Blueprint, Ctrl+C/V i Shift+klik přenášejí kód a informaci, jestli program běžel. Stav programu ani rozepsaný kód
se nepřenášejí, nová budova začne inicializací.
