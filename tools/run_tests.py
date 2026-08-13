#!/usr/bin/env python3
"""Runs the Isaac-stub harness against main.lua.

There is no Lua interpreter on a typical Windows box and no way to script the
game itself, so the mod is exercised under `lupa`'s embedded Lua with the Isaac
API stubbed out. main.lua is loaded unmodified -- the harness only supplies the
globals the game would.

    pip install lupa
    python tools/run_tests.py
"""

import os
import sys

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit("lupa is not installed.  pip install lupa")

HERE = os.path.dirname(os.path.abspath(__file__))
HARNESS = os.path.join(HERE, "harness.lua")
MAIN = os.path.join(os.path.dirname(HERE), "main.lua")


def main():
    if not os.path.exists(MAIN):
        sys.exit("main.lua not found next to tools/")

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("arg = {}")
    run = lua.eval("function(harness, target)"
                   "  local chunk, err = loadfile(harness)"
                   "  if chunk == nil then error(err) end"
                   "  return chunk(target)"
                   "end")
    try:
        run(HARNESS.replace("\\", "/"), MAIN.replace("\\", "/"))
    except SystemExit:
        raise
    except Exception as exc:
        print("LUA ERROR:", exc)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
