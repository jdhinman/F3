"""Index every Namespace.Function call in the decompiled corpus, with a shipped call site.

    python tools/api-index.py                 # write work/api-index.txt, print a summary
    python tools/api-index.py search <text>   # find matching calls and where they are used

The corpus is a complete API reference, and the whole project has been grepping it
reactively instead. SearchTools - a general entity finder that solved a problem worked
around for weeks - was in dozens of shipped scripts the entire time. Index first.

Each entry records how many times a call appears and one file:line, because Rule 1 means a
call is only usable once a shipped site passing literals has been read.
"""

import collections
import glob
import os
import re
import sys

CALL = re.compile(r'\b([A-Z][A-Za-z0-9_]{2,30})\.([A-Za-z_][A-Za-z0-9_]{2,40})\s*\(')
CORPUS = "work/decompiled/**/*.lua"
OUT = "work/api-index.txt"


def build():
    hits = collections.Counter()
    where = {}
    for path in glob.glob(CORPUS, recursive=True):
        rel = path.replace("\\", "/")
        for n, line in enumerate(open(path, encoding="utf-8", errors="ignore"), 1):
            for m in CALL.finditer(line):
                key = f"{m.group(1)}.{m.group(2)}"
                hits[key] += 1
                # Prefer a call site that passes a string literal: that is what Rule 1 wants.
                if key not in where or ('"' in line and '"' not in where[key][2]):
                    where[key] = (rel, n, line.strip()[:120])
    return hits, where


def main():
    hits, where = build()
    if len(sys.argv) > 2 and sys.argv[1] == "search":
        needle = sys.argv[2].lower()
        found = sorted(k for k in hits if needle in k.lower())
        if not found:
            print(f"no API call matching {needle!r}")
            return 1
        for k in found:
            f, n, src = where[k]
            print(f"{k}  ({hits[k]} uses)\n    {f}:{n}\n    {src}")
        return 0

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        for k in sorted(hits):
            f, n, src = where[k]
            fh.write(f"{k}\t{hits[k]}\t{f}:{n}\t{src}\n")
    per_ns = collections.Counter(k.split(".")[0] for k in hits)
    print(f"{len(hits)} distinct calls, {len(per_ns)} namespaces -> {OUT}")
    print("\nlargest namespaces:")
    for ns, n in per_ns.most_common(15):
        print(f"  {ns:26} {n:4}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
