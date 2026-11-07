local globals={}
require("nw/dev_commands").install(globals,{ListenForEvent=function() end})
local function wand(cast,recharge)
    local cmp={data={runtime={remaining_cast=cast,remaining_recharge=recharge,mana=17,cursor=3},
        stats={recharge=2},cards={"unchanged"}},cool_total=240,_ready_cache={}}
    function cmp:UpdateTime() self.updated=true end
    function cmp:Sync()
        assert(self.updated and self.data.runtime.remaining_cast==0 and self.data.runtime.remaining_recharge==0)
        assert(self.cool_total==0 and self._ready_cache==nil)
        self.synced=true
    end
    return {components={nw_wand=cmp},IsValid=function() return true end}
end
local held,stored,sleeping=wand(240,0),wand(0,60),wand(3,2)
local invalid=wand(10,10);invalid.IsValid=function() return false end
Ents={held,stored,sleeping,invalid,{components={}}, {components={nw_wand={}},IsValid=function() return true end}}
TheWorld={ismastersim=false}
assert(globals.nw_recharge()==0 and not held.components.nw_wand.synced)
TheWorld.ismastersim=true
assert(globals.nw_recharge()==3)
for _,e in ipairs({held,stored,sleeping}) do
    local cmp=e.components.nw_wand
    assert(cmp.synced and cmp.data.runtime.mana==17 and cmp.data.runtime.cursor==3)
    assert(cmp.data.stats.recharge==2 and cmp.data.cards[1]=="unchanged")
end
assert(not invalid.components.nw_wand.updated)
print("developer recharge: all loaded wands, star cooldown, sync, guards and preserved loadout")
