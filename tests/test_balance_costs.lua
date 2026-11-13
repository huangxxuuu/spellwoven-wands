local B=require("nw/balance")
local G=require("nw/generator")
local R=require("nw/wand_generation")
local C=require("nw/compiler")
local D=require("nw/definitions")
local function near(a,b) assert(math.abs(a-b)<.000001,tostring(a).." ~= "..tostring(b)) end

-- Switching modes must invalidate Gaussian CDFs without modifying old rolls.
B.configure("fun")
local old=G.starter()
local rolls,distributions={},{}
for tier=1,4 do
    for _,kind in ipairs(D.archetypes) do
        local key=tier..kind
        rolls[key]=G.generate(123456,tier,kind)
        distributions[key]={R.distribution(tier,kind,"recharge")}
    end
end
B.configure("balanced")
near(G.starter().stats.recharge,2.1)
near(G.sanity_conversion_for(old.stats),10)
near(old.stats.recharge,1.4)
for tier=1,4 do
    for _,kind in ipairs(D.archetypes) do
        local key=tier..kind
        local balanced=G.generate(123456,tier,kind)
        local dist={R.distribution(tier,kind,"recharge")}
        for i=1,5 do near(dist[i],distributions[key][i]*1.5) end
        for _,stat in ipairs(R.keys) do
            near(balanced.stats[stat],rolls[key].stats[stat]*(stat=="recharge" and 1.5 or 1))
        end
    end
end
B.configure("fun")
near(G.sanity_conversion_for(old.stats),20)
near(G.generate(123456,1,"sprout").stats.recharge,rolls["1sprout"].stats.recharge)

GetTime=function() return 0 end
Class=function(ctor) local c={};c.__index=c;return setmetatable(c,{__call=function(_,...) local o=setmetatable({},c);ctor(o,...);return o end}) end
EQUIPSLOTS={HANDS="hands"}
local function net() return {set=function(self,v) self.v=v end,value=function(self) return self.v end} end
local inst={_nw_capacity=net(),_nw_mana=net(),_nw_ready=net(),AddTag=function() end,RemoveTag=function() end}
local w=require("components/nw_wand")(inst)
w:InitializePrototype()
local success=true
package.loaded["nw/executor"]={execute=function() return success,"FAILED" end}
package.loaded["nw/muzzle"]={origin=function() return 0,0,0 end}
package.loaded["nw/dummy_trials"]={cast=function() end}
local charges={}
local function resource(value,name)
    return {current=value,DoDelta=function(self,delta)
        charges[#charges+1]=name;self.current=self.current+delta
        assert(self.current>=0)
    end}
end
local player={IsValid=function() return true end,Transform={GetWorldPosition=function() return 0,0,0 end},components={
    inventory={GetEquippedItem=function() return inst end},
    health={IsDead=function() return false end,DoDelta=function() error("cast must not charge health") end}}}
local function setup(mode,sanity,hunger,ids)
    B.configure(mode)
    w.data.cards={false,false,false,false}
    for i,id in ipairs(ids or {"heavy"}) do w.data.cards[i]={card_uid=tostring(i),spell_id=id} end
    w.data.runtime=C.initial(w.data.cards,w.data.stats,123)
    w.data.config_revision=w.data.config_revision+1
    player.components.sanity=sanity~=nil and resource(sanity,"sanity") or nil
    player.components.hunger=resource(hunger,"hunger")
    charges={}
end
local function cast() assert(w:Cast(player,{x=4,z=0})) end
setup("balanced",1,10);cast()
near(player.components.sanity.current,0);near(player.components.hunger.current,9.6)
assert(charges[1]=="sanity" and charges[2]=="hunger")
setup("balanced",0,.1);cast();near(player.components.hunger.current,0)
setup("balanced",0,0);cast()
setup("balanced",nil,10);cast();near(player.components.hunger.current,9.1)
setup("balanced",10,10);cast();near(player.components.sanity.current,8.2);near(player.components.hunger.current,10)
setup("fun",1,10);cast();near(player.components.sanity.current,.1);near(player.components.hunger.current,10)
setup("fun",0,10);cast();near(player.components.hunger.current,10)
setup("balanced",0,10,{"mana_reduce","spark"});cast();near(player.components.hunger.current,9.95)
setup("balanced",1,10);success=false
assert(not w:Cast(player,{x=4,z=0}));near(player.components.sanity.current,1);near(player.components.hunger.current,10)
success=true

-- Cached/prepared draws must not retain the other mode's mana reduction.
setup("fun",10,10,{"mana_reduce","heavy"})
local fun=assert(w:ReadyPlan());near(fun.mana_spent,-12)
B.configure("balanced")
assert(D.spells.mana_reduce.mana==-20)
local balanced=assert(w:ReadyPlan());near(balanced.mana_spent,-2)
assert(fun~=balanced)
local ok,why=w:CanCast(player,fun);assert(not ok and why=="STALE_CAST")
near(w:PreviewCast().mana_spent,-2)
-- Recharge is already saved in stats; casts never multiply it or impose a floor.
w.data.stats.recharge=0
w.data.cards={{card_uid="one",spell_id="spark"},false,false,false}
w.data.runtime=C.initial(w.data.cards,w.data.stats,123)
near(assert(C.compile(w.data)).next_state.remaining_recharge,0)
w.data.stats.recharge=1.4
local saved=w:OnSave()
for _,mode in ipairs({"fun","balanced","balanced","fun"}) do
    B.configure(mode);w:OnLoad(saved);saved=w:OnSave()
    near(saved.wand.stats.recharge,1.4);near(saved.wand.stats.sanity_conversion,20)
    near(G.sanity_conversion_for(saved.wand.stats),mode=="balanced" and 10 or 20)
end
print("balance costs: mode-aware generation/cache, unchanged old rolls, SAN then hunger, no health fee, zero resource casts, minimum fee and save round trips")
