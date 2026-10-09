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


class Elements:
    """Stavové prvky knihovny kombinátorů (stav pod jménem, dt čte z jmenného prostoru programu)."""

    def __init__(self, ns: dict):
        self.ns = ns
        self.state = {}

    def _get(self, name, kind):
        """Stav prvku; jiný druh pod stejným jménem je chyba."""
        s = self.state.setdefault(name, {"kind": kind})
        if s["kind"] != kind:
            raise ValueError(f"element {name} is {s['kind']}")
        return s

    def latch(self, name, set_, reset):
        s = self._get(name, "latch")
        if reset:
            s["q"] = False
        elif set_:
            s["q"] = True
        return s.get("q", False)

    def timer(self, name, period):
        s = self._get(name, "timer")
        s["acc"] = s.get("acc", 0) + self.ns["dt"]
        if s["acc"] >= period:
            s["acc"] %= period
            return True
        return False

    def edge(self, name, value):
        s = self._get(name, "edge")
        now, prev = bool(value), s.get("prev", False)
        s["prev"] = now
        return 1 if now and not prev else -1 if prev and not now else 0

    def counter(self, name, step=1, reset=False):
        s = self._get(name, "counter")
        s["value"] = 0 if reset else s.get("value", 0) + step
        return s["value"]

    def delay(self, name, value, n):
        s = self._get(name, "delay")
        if s.get("n") != n:
            s.update(n=n, buf=[None] * n, pos=0)
        old = s["buf"][s["pos"]]
        s["buf"][s["pos"]] = value
        s["pos"] = (s["pos"] + 1) % n
        return 0 if old is None else old

    def pid(self, name, sp, pv, kp, ki, kd, lo=None, hi=None):
        s = self._get(name, "pid")
        dt = self.ns["dt"]
        e = sp - pv
        integral = s.get("integral", 0) + e * dt
        deriv = (e - s["prev_e"]) / dt if "prev_e" in s and dt > 0 else 0
        out = kp * e + ki * integral + kd * deriv
        if hi is not None and out > hi:
            out = hi
            if e > 0:
                integral = s.get("integral", 0)
        elif lo is not None and out < lo:
            out = lo
            if e < 0:
                integral = s.get("integral", 0)
        s["integral"], s["prev_e"] = integral, e
        return out


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
    lib = Elements(ns)
    for name in ("latch", "timer", "edge", "counter", "delay", "pid"):
        ns[name] = getattr(lib, name)
    exec(compile(src, path, "exec"), ns)
    for t in range(ticks):
        ns["tick"] = t
        ns["game_tick"] = t
        ns["loop"]()


if __name__ == "__main__":
    sys.stdout.reconfigure(newline="\n")
    main(sys.argv[1])
