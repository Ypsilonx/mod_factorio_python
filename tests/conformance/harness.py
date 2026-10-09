"""Spustí program Pythonatoru v CPythonu a vypíše řádky print() – referenční výstup pro Lua implementaci."""
import sys


class Signals(dict):
    """Náhrada objektů signálů: chybějící klíč čte 0."""

    def __missing__(self, key):
        return 0


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
