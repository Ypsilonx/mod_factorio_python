# ticks: 2
# Knihovna kombinátorů: vektorové operace (out_red slouží jako sada vstupních signálů). Ve hře se drží jen 50 řádků print().


def show(label, d):
    print(label, sorted(d.items()))


def loop():
    out_red.clear()
    out_red["copper-plate"] = 3 + tick
    out_red["iron-plate"] = -7
    out_red["signal-A"] = 2147483647
    out_red["signal-B"] = 3 + tick
    show("each+", out_red.each("+", 1))
    show("each*", out_red.each("*", 3))
    show("each/", out_red.each("/", 2))
    show("each%", out_red.each("%", 3))
    show("each/0", out_red.each("/", 0))
    show("each**", out_red.each("**", 2))
    show("each<<", out_red.each("<<", 33))
    show("each>>", out_red.each(">>", 1))
    show("each&", out_red.each("&", 6))
    show("where>", out_red.where(">", 3))
    show("chain", out_red.where("!=", -7).each("-", 3 + tick))
    print("count", out_red.count(), out_red.count("<", 4), out_red.count("==", 3 + tick))
    print("sum", out_red.sum(), out_red.where("<", 100).sum())
    print("max", out_red.max_key(), out_red.where("<", 100).max_key(), out_red.min_key())
    print("empty", out_red.where(">", 2147483647).max_key(), out_red.where(">", 2147483647).sum())
    out.set(out_red.where("<", 100))
    out.add(out_red.each("*", 0 - 1).where(">", 0))
    print("out", sorted(out.items()))
    out.set(out)
    print("out-self", sorted(out.items()))
