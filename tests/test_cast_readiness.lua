local clock=0;GetTime=function() return clock end
Class=function(ctor) local t={};t.__index=t;return setmetatable(t,{__call=function(_,...) local o=setmetatable({},t);ctor(o,...);return o end}) end
EQUIPSLOTS={HANDS="hands"}
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
local function net() return {set=function(self,v) self.v=v end,value=function(self) return self.v end} end
local C=require("nw/compiler")
local U=require("nw/util")
local W=require("components/nw_wand")
local wand={_nw_capacity=net(),_nw_mana=net(),_nw_ready=net(),components={}}
local cmp=W(wand);wand.components.nw_wand=cmp;cmp:InitializePrototype()
local shots=0
local player={components={inventory={GetEquippedItem=function() return wand end},health={IsDead=function() return false end}},
    Transform={GetWorldPosition=function() return 0,0,0 end},IsValid=function() return true end,
    ForceFacePoint=function() end}
local lastplan
package.loaded['nw/executor']={execute=function(plan) shots=shots+1;lastplan=plan;return true end}
local function setup(ids,mana)
    cmp.data.cards={false,false,false,false};cmp.data.stats.mana_regen=8
    for i,id in ipairs(ids) do cmp.data.cards[i]={card_uid=tostring(i),spell_id=id} end
    cmp.data.runtime=C.initial(cmp.data.cards,cmp.data.stats,91);cmp.data.runtime.mana=mana
    cmp.last_time=clock
end
local function same(a,b)
    if type(a)~="table" then return a==b end
    if type(b)~="table" then return false end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
setup({"heavy"},0)
local before=U.copy(cmp.data.runtime)
for i=1,20 do local ok,why=cmp:CanCast(player);assert(not ok and why=="NO_MANA") end
assert(same(before,cmp.data.runtime),"dry readiness checks advanced mana/deck/RNG/cooldown")
assert(not cmp:Cast(player,{x=4,z=0}) and shots==0 and same(before,cmp.data.runtime))
-- Resource recovery by itself must not execute or schedule a cast.
clock=2.26;cmp:UpdateTime();assert(shots==0)
local ready,_,prepared=cmp:CanCast(player);assert(ready)
clock=2.4;assert(cmp:Cast(player,{x=4,z=0},prepared));assert(shots==1 and lastplan.mana_spent==18)
assert(math.abs(cmp.data.runtime.mana-1.2)<.00001,"wind-up regeneration was lost")
-- No mana spent on modifiers while the whole attempt produces no bullet.
setup({"damage_up","heavy"},8);before=U.copy(cmp.data.runtime)
local ok,why=cmp:CanCast(player);assert(not ok and why=="NO_MANA" and same(before,cmp.data.runtime))
-- Preserve Noita-style skip rules: an affordable later bullet may still fire.
setup({"heavy","spark"},5)
local plan;ok,why,plan=cmp:CanCast(player)
assert(ok and plan.mana_spent==5 and plan.projectile_count==1)
assert(cmp.data.runtime.mana==5 and #cmp.data.runtime.deck==2)
-- Regeneration can make an earlier modifier affordable but leave no bullet.
-- Use the accepted plan through the wind-up instead of changing its draw.
setup({"damage_up","spark"},5)
ok,why,plan=cmp:CanCast(player);assert(ok and plan.mana_spent==5)
cmp.data.runtime.mana=8
assert(not cmp:CanCast(player))
assert(cmp:Cast(player,{x=4,z=0},plan) and cmp.data.runtime.mana==3)
-- Replaying a prepared cast or changing its configuration cannot spend twice.
cmp.data.runtime.remaining_cast=0;cmp.data.runtime.remaining_recharge=0
ok,why=cmp:Cast(player,{x=4,z=0},plan);assert(not ok and why=="STALE_CAST")
setup({"spark"},5);ok,why,plan=cmp:CanCast(player);assert(ok)
cmp.data.config_revision=cmp.data.config_revision+1
ok,why=cmp:Cast(player,{x=4,z=0},plan);assert(not ok and why=="STALE_CAST")
-- Empty / modifier-only decks do not gesture or consume mana either.
for _,ids in ipairs({{}, {"damage_up"}}) do
    setup(ids,120);before=U.copy(cmp.data.runtime)
    ok,why=cmp:CanCast(player);assert(not ok and why=="NO_PROJECTILES" and same(before,cmp.data.runtime))
end
print("mana readiness: zero dry spend/draws; no automatic cast on recovery; stable accepted plan and stale guards")

setup({"mana_reduce","recharge_down","spark"},0)
ok,why,plan=cmp:CanCast(player)
assert(ok and plan.mana_spent==-13 and plan.next_state.mana==13)
assert(cmp:Cast(player,{x=4,z=0},plan) and cmp.data.runtime.mana==13)
setup({"mana_reduce","spark"},cmp.data.stats.mana_max-1)
ok,why,plan=cmp:CanCast(player);assert(ok)
clock=clock+1
assert(cmp:Cast(player,{x=4,z=0},plan) and cmp.data.runtime.mana==cmp.data.stats.mana_max)
setup({"repeat_2","mana_reduce","spark"},35)
ok,why,plan=cmp:CanCast(player);assert(ok and plan.mana_spent==10 and plan.mana_required==35)
cmp.data.runtime.mana=34
ok,why=cmp:Cast(player,{x=4,z=0},plan);assert(not ok and why=="NO_MANA")
require("nw/spell_limits").cast=12
for _,ids in ipairs({{"mana_reduce"},{"repeat_3","repeat_3","scatter"}}) do
    setup(ids,120);before=U.copy(cmp.data.runtime)
    assert(not cmp:Cast(player,{x=4,z=0}) and same(before,cmp.data.runtime))
end

require("nw/spell_limits").cast=0
setup({"repeat_3","repeat_3","scatter"},120)
ok,why,plan=cmp:CanCast(player)
assert(ok and plan.projectile_count==27)
assert(cmp:Cast(player,{x=4,z=0},plan))

local sanity={current=5,calls=0}
function sanity:DoDelta(delta) self.current=self.current+delta;self.calls=self.calls+1 end
player.components.sanity=sanity
for _,row in ipairs({
    {{"double","spark","arrow"},20,.75},
    {{"pierce","arrow_hit","double","explosion","whirl"},20,2.7},
    {{"mana_reduce","recharge_down","spark"},20,.1},
    {{"spark"},40,.125},
}) do
    setup(row[1],120);cmp.data.stats.sanity_conversion=row[2]
    sanity.current=10
    local calls=sanity.calls
    local yes,_,accepted=cmp:CanCast(player)
    assert(yes and sanity.calls==calls)
    assert(cmp:Cast(player,{x=4,z=0},accepted))
    assert(math.abs(sanity.current-(10-row[3]))<1e-8 and sanity.calls==calls+1)
    assert(not cmp:Cast(player,{x=4,z=0},accepted) and sanity.calls==calls+1)
end
sanity.current=.02
setup({"spark"},5);assert(cmp:Cast(player,{x=4,z=0}) and sanity.current==0)
setup({"spark"},5);assert(cmp:Cast(player,{x=4,z=0}) and sanity.current==0)
sanity.current=3
setup({"heavy"},0);assert(not cmp:Cast(player,{x=4,z=0}) and sanity.current==3)
setup({"spark"},120)
package.loaded['nw/executor'].execute=function() return false,"LIMIT" end
assert(not cmp:Cast(player,{x=4,z=0}) and sanity.current==3)
