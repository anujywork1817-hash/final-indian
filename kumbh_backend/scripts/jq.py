import sys, json

# Tiny JSON path reader: "a.b.0.c", and "path.#" for length.
try:
    d = json.load(sys.stdin)
    path = sys.argv[1] if len(sys.argv) > 1 else ""
    for k in path.split("."):
        if k == "":
            continue
        if k == "#":
            d = len(d)
            break
        d = d[int(k)] if k.lstrip("-").isdigit() else d[k]
    if d is None:
        print("")
    elif isinstance(d, bool):
        print("true" if d else "false")
    elif isinstance(d, (dict, list)):
        print(json.dumps(d))
    else:
        print(d)
except Exception:
    print("")
