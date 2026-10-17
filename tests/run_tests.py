#!/usr/bin/env python3
"""Headless tests for Ensemble (no game needed).

  pip install lupa            (once)
  python3 tests/run_tests.py            # LuaJIT and plain Lua 5.1 (WoW's dialect)
  python3 tests/run_tests.py --examples # print sample kick/dispel plans and chat posts
  python3 tests/run_tests.py --data     # print the game data as tables (for update sessions)
  python3 tests/run_tests.py --fit      # fit rating measurement report (spread and band counts)

Exit code is non-zero when any test fails. The stub (wowstub.lua) fakes just enough of the
WoW API; lines like "[FAIL] spec 102 ... unknown to the client" are /ens verify output run
against that stub and are expected - only lines starting "FAIL:" are test failures.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.normpath(os.path.join(HERE, "..", "Ensemble"))

def runtime(mod):
    L = mod.LuaRuntime(unpack_returned_tuples=True)
    L.globals().ADDON_DIR = ADDON
    L.execute(open(os.path.join(HERE, "wowstub.lua"), encoding="utf-8").read())
    return L

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
    for flag, script in (("--examples", "plan_examples.lua"), ("--data", "data_report.lua"), ("--fit", "fit_report.lua")):
        if flag in sys.argv:
            L = runtime(engines[0][1])
            L.execute(open(os.path.join(HERE, script), encoding="utf-8").read())
            return 0
    bad = 0
    for name, mod in engines:
        print("=== %s ===" % name)
        fails = runtime(mod).execute(open(os.path.join(HERE, "test_addon.lua"), encoding="utf-8").read())
        bad += int(fails or 0)
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
