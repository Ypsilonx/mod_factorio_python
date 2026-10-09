"""Spustí program Pythonatoru v CPythonu a vypíše řádky print() – referenční výstup pro Lua implementaci."""
import sys


def wrap32(x: int) -> int:
    """Zabalí celé číslo do int32 se znaménkem (jako obvodová síť)."""
    x &= 0xFFFFFFFF
    return x - 0x100000000 if x >= 0x80000000 else x


def trunc(x) -> int:
    """Ořez k nule (signál je celé číslo)."""
    return int(x)


def _div(a: int, b: int) -> int:
    """Dělení k nule, dělení nulou = 0 (aritmetický kombinátor)."""
    if b == 0:
        return 0
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


ARITH = {
    "+": lambda a, b: a + b,
    "-": lambda a, b: a - b,
    "*": lambda a, b: a * b,
    "/": _div,
    "%": lambda a, b: 0 if b == 0 else a - b * _div(a, b),
    "**": lambda a, b: 0 if b < 0 else pow(a, b, 1 << 32),
    "<<": lambda a, b: a << (b % 32),
    ">>": lambda a, b: a >> (b % 32),
    "&": lambda a, b: a & b,
    "|": lambda a, b: a | b,
    "^": lambda a, b: a ^ b,
}

COMPARE = {
    "<": lambda a, b: a < b,
    "<=": lambda a, b: a <= b,
    ">": lambda a, b: a > b,
    ">=": lambda a, b: a >= b,
    "==": lambda a, b: a == b,
    "!=": lambda a, b: a != b,
}


class Signals(dict):
    """Náhrada objektů signálů a výsledků knihovny kombinátorů: chybějící klíč čte 0, nula se neukládá."""

    def __missing__(self, key):
        return 0

    def __setitem__(self, key, value):
        v = wrap32(trunc(value))
        if v == 0:
            self.pop(key, None)
        else:
            super().__setitem__(key, v)

    def each(self, op, v):
        """Každý signál op v se sémantikou aritmetického kombinátoru."""
        f, b = ARITH[op], trunc(v)
        out = Signals()
        for k, x in self.items():
            out[k] = wrap32(f(wrap32(trunc(x)), b))
        return out

    def where(self, op, v):
        """Signály splňující podmínku, s původní hodnotou."""
        f = COMPARE[op]
        out = Signals()
        for k, x in self.items():
            if f(x, v):
                out[k] = x
        return out

    def count(self, op=None, v=None):
        """Počet signálů, případně jen splňujících podmínku."""
        if op is None:
            return len(self)
        return len(self.where(op, v))

    def sum(self):
        """Součet hodnot (bez přetečení)."""
        return sum(self.values())

    def _extreme(self, sign):
        """Klíč s extrémní hodnotou; při shodě menší klíč po bajtech."""
        best = None
        for k, x in self.items():
            if best is None or x * sign > best[1] * sign or (x == best[1] and k.encode() < best[0].encode()):
                best = (k, x)
        return None if best is None else best[0]

    def max_key(self):
        return self._extreme(1)

    def min_key(self):
        return self._extreme(-1)

    def set(self, d):
        """Nahradí obsah sadou d."""
        items = list(d.items())
        self.clear()
        for k, x in items:
            self[k] = x

    def add(self, d):
        """Přičte sadu d."""
        for k, x in list(d.items()):
            self[k] = self[k] + x


def main(path: str) -> None:
    """Spustí inicializaci a `# ticks: N`× loop() programu ze souboru path."""
    with open(path, encoding="utf-8") as f:
        src = f.read()
    ticks = 1
    first = src.splitlines()[0] if src else ""
    if first.startswith("# ticks:"):
        ticks = int(first.split(":")[1])
    ns = {name: Signals() for name in ("inp", "red", "green", "out", "out_red", "out_green")}
    ns.update(tick=0, game_tick=0, dt=1, config=lambda **kw: None)
    exec(compile(src, path, "exec"), ns)
    for t in range(ticks):
        ns["tick"] = t
        ns["game_tick"] = t
        ns["loop"]()


if __name__ == "__main__":
    sys.stdout.reconfigure(newline="\n")
    main(sys.argv[1])
