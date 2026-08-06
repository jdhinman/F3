"""Syntax-check decompiled Lua with a real Lua 5.1 parser (lupa.lua51 -> loadstring).

Usage: python syntaxcheck.py <dir-of-lua-files>
Prints one line per failure, then a tally.
"""
import sys, os
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
check = lua.eval("function(s) local f, e = loadstring(s) if f then return nil else return e end end")

root = sys.argv[1]
files = []
for dirpath, _, names in os.walk(root):
    for n in names:
        if n.endswith(".lua"):
            files.append(os.path.join(dirpath, n))
files.sort()

bad = 0
for f in files:
    src = open(f, "r", encoding="utf-8", errors="replace").read()
    err = check(src)
    if err is not None:
        bad += 1
        print("SYNTAX", os.path.relpath(f, root), str(err).split("]:", 1)[-1].strip())

print(f"\n{len(files) - bad} of {len(files)} parse as valid Lua 5.1 ({bad} failed)")
