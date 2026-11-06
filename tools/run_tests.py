"""Execute pure rules with Lua 5.1, not Python reimplementations."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
def runtime():
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path = str(ROOT / "mod/scripts/?.lua").replace("\\", "/") + ";" + vm.globals().package.path
    vm.execute("local seq=0; TheWorld={components={nw_identity={Next=function() seq=seq+1; return 'test:'..seq end}}}")
    return vm

lua = runtime()
syntax = lua.eval("function(source, name) local fn, err = loadstring(source, name); assert(fn, err); return true end")
files = sorted((ROOT / "mod").rglob("*.lua"))
for path in files:
    syntax(path.read_text(encoding="utf-8"), str(path))
print(f"Lua 5.1 syntax: {len(files)} files OK", flush=True)
for path in sorted((ROOT / "tests").glob("test_*.lua")):
    runtime().execute(path.read_text(encoding="utf-8"))
    print(f"PASS {path.name}", flush=True)
