#!/usr/bin/env python3
"""Headless tests for the raid test module (Ensemble_Raid, raid-prototype branch).

  python3 tests/raid/run_raid_tests.py      # LuaJIT and plain Lua 5.1

Loads Ensemble (from its TOC) and then Ensemble_Raid (from its TOC) into the same stub the
core tests use (tests/wowstub.lua). Exit code is non-zero when any test fails.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))

def main():
    import lupa
    engines = []
    for name in ("luajit21", "lua51"):
        try:
            engines.append((name, __import__("lupa." + name, fromlist=["LuaRuntime"])))
        except ImportError:
            pass
    if not engines:
        engines = [("default", lupa)]
    bad = 0
    for name, mod in engines:
        print("=== %s ===" % name)
        L = mod.LuaRuntime(unpack_returned_tuples=True)
        L.globals().ADDON_DIR = os.path.join(ROOT, "Ensemble")
        L.globals().RAID_DIR = os.path.join(ROOT, "Ensemble_Raid")
        L.execute(open(os.path.join(ROOT, "tests", "wowstub.lua"), encoding="utf-8").read())
        fails = L.execute(open(os.path.join(HERE, "test_raid.lua"), encoding="utf-8").read())
        bad += int(fails or 0)
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
