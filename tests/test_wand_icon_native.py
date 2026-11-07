"""Run the installed game's actual layered image helpers against our descriptors."""
from pathlib import Path
import unittest
import zipfile
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
SCRIPTS=Path("E:/SteamLibrary/steamapps/common/Don't Starve Together/data/databundles/scripts.zip")

@unittest.skipUnless(SCRIPTS.is_file(),'requires local DST scripts')
class NativeWandIconTests(unittest.TestCase):
    def test_item_recipe_and_drag_helpers(self):
        vm=LuaRuntime(unpack_returned_tuples=True)
        vm.globals().package.path=(ROOT/'mod/scripts/?.lua').as_posix()+';'+vm.globals().package.path
        vm.execute('''
            GetGameModeProperty=function() return true end
            GetInventoryItemAtlas=function() error("every layer must specify its atlas") end
            PREFAB_SKINS_SHOULD_NOT_SELECT={}
            TheInventory={GetUnlockableItems=function() return {} end}
            function Image()
                local im={children={},tint={1,1,1,1}}
                function im:SetTexture(a,t) self.atlas,self.texture=a,t end
                function im:SetTint(...) self.tint={...} end
                function im:SetPosition(...) self.pos={...} end
                function im:SetEffect(v) self.effect=v end
                function im:Kill() self.killed=true end
                function im:AddChild(v) self.children[#self.children+1]=v;return v end
                return im
            end
            local make=Image
            Image=function(a,t) local im=make();if a then im:SetTexture(a,t) end;return im end
        ''')
        with zipfile.ZipFile(SCRIPTS) as z:
            for name,fn in [('itemtile','SetImageFromItem'),('recipetile','SetImageFromRecipe')]:
                source=z.read('scripts/widgets/'+name+'.lua').decode('utf8')
                start=source.index('local function '+fn+'(')
                end=source.index('\nlocal ItemTile',start) if name=='itemtile' else source.index('\n--static function',start)
                helper=vm.execute(source[start:end]+'\nreturn '+fn)
                vm.globals()[fn]=helper
            for name in ('inventorybar','containerwidget'):
                self.assertIn('ItemTile.sSetImageFromItem',z.read('scripts/widgets/'+name+'.lua').decode('utf8'))
        vm.execute('''
            local Icon=require("nw/wand_icon")
            local V=require("nw/visual")
            local item={code=0,broken=false,events={}}
            item._nw_look={value=function() return item.code end}
            item._nw_broken={value=function() return item.broken end}
            function item:ListenForEvent(name,fn) self.events[name]=fn end
            function item:PushEvent(name) assert(name=="imagechange");SetImageFromItem(im,self) end
            Icon.install(item)
            im=Image();SetImageFromItem(im,item)
            assert(#im.layers==2 and im.texture=="body_01_short.tex")
            local head=im.layers[2]
            assert(head.effect=="shaders/ui_cc.ksh")
            item.code=4373;item.broken=true;item.events.nw_lookdirty()
            assert(im.layers[2]==head and head.texture:find("_broken_",1,true))
            assert(im.texture=="body_09_long.tex")
            item.broken=false;item.events.nw_lookdirty()
            assert(not head.texture:find("_broken_",1,true))
            local native={replica={inventoryitem={GetAtlas=function() return "native.xml" end,GetImage=function() return "native.tex" end}}}
            SetImageFromItem(im,native)
            assert(im.layers==nil and head.killed and im.texture=="native.tex")
            SetImageFromItem(im,item);assert(#im.layers==2)
            for tier=0,3 do
                local recipe={product="nw_wand",layeredimagefn=Icon.recipe(tier)}
                local image=Image();SetImageFromRecipe(image,recipe,nil,.2,.3,.4)
                assert(#image.layers==2)
                assert(image.texture==V.icon_parts(V.recipe_code(tier),false)[1])
                for _,layer in ipairs(image.layers) do assert(layer.tint[1]==.2 and layer.tint[3]==.4) end
            end
        ''')

if __name__=='__main__':unittest.main()
