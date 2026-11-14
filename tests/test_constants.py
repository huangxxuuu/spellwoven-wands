from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]


class ConstantsTests(unittest.TestCase):
    def test_pure_data_modules_import_without_gameplay_dependencies(self):
        modules = sorted((ROOT / "mod/scripts/nw/constants").rglob("*.lua"))
        self.assertTrue(modules)
        for path in modules:
            name = path.relative_to(ROOT / "mod/scripts").with_suffix("").as_posix()
            with self.subTest(module=name):
                lua = LuaRuntime(unpack_returned_tuples=True)
                lua.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix()
                lua.execute("""
                    local load=require
                    function require(name)
                        assert(name:match('^nw/constants/'), 'gameplay dependency: '..name)
                        return load(name)
                    end
                    function check(value,seen)
                        local kind=type(value)
                        assert(kind=='table' or kind=='number' or kind=='string' or kind=='boolean',kind)
                        if kind~='table' then return end
                        assert(getmetatable(value)==nil,'constant table has a metatable')
                        seen=seen or {}
                        if seen[value] then return end
                        seen[value]=true
                        for key,child in pairs(value) do check(key,seen);check(child,seen) end
                    end
                """)
                lua.globals().check(lua.globals().require(name))


if __name__ == "__main__":
    unittest.main()
