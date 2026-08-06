"""Compare decompiled output against original source, token by token.

Fable III shipped a handful of scripts as plaintext alongside their compiled form, which
is the only ground truth available. Comments, whitespace, parenthesisation and
elseif-vs-nested-if all legitimately differ, so this compares the multisets that must not:
string literals, numbers, and identifiers.

Usage: python groundtruth.py <original.txt> <decompiled.lua>
"""
import sys, re
from collections import Counter

TOKEN = re.compile(r"""
    (?P<comment>--\[\[.*?\]\]|--[^\n]*)
  | (?P<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')
  | (?P<number>\d+\.?\d*(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
""", re.X | re.S)

KEYWORDS = {"and","break","do","else","elseif","end","false","for","function","if","in",
            "local","nil","not","or","repeat","return","then","true","until","while"}

def toks(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    strings, numbers, names = Counter(), Counter(), Counter()
    for m in TOKEN.finditer(src):
        if m.group("comment"):
            continue
        if m.group("string"):
            strings[m.group("string")[1:-1]] += 1
        elif m.group("number"):
            numbers[float(m.group("number"))] += 1
        elif m.group("name") and m.group("name") not in KEYWORDS:
            names[m.group("name")] += 1
    return strings, numbers, names

a_s, a_n, a_i = toks(sys.argv[1])
b_s, b_n, b_i = toks(sys.argv[2])

def report(label, a, b):
    missing = a - b       # in original, absent from output
    extra = b - a
    total = sum(a.values())
    print(f"{label}: original {total}, output {sum(b.values())}, "
          f"missing {sum(missing.values())}, extra {sum(extra.values())}")
    for k, v in list(missing.most_common(6)):
        print(f"    missing x{v}: {k!r}")
    for k, v in list(extra.most_common(6)):
        print(f"    extra   x{v}: {k!r}")

report("strings    ", a_s, b_s)
report("numbers    ", a_n, b_n)
report("identifiers", a_i, b_i)
