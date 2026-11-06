local U=require("nw/util")
local clock=0
GetTime=function() return clock end
Class=function(constructor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_, ...)
        local obj=setmetatable({},cls);constructor(obj,...);return obj
    end})
end
local function net()
    return { current=0, set=function(self,v) self.current=v end, value=function(self) return self.current end }
end
local function entity()
    return {_nw_capacity=net(),_nw_mana=net(),_nw_ready=net()}
end
local Component=require("components/nw_wand")
local a=Component(entity());a:InitializePrototype()
assert(a.data.stats.capacity==4 and a.inst._nw_ready.current)
a.data.runtime.mana=5
a.data.runtime.remaining_cast=2
clock=1
local saved=a:OnSave()
assert(saved.wand.runtime.mana==23 and saved.wand.runtime.remaining_cast==1)
assert(saved.wand.stats.sanity_conversion==20)
saved.wand.appearance={appearance_schema=1,head_id="plain_1_1"}
saved.wand.stats.sanity_conversion=nil -- a wand saved by 0.8.4
clock=100
local b=Component(entity());b:OnLoad(saved)
assert(b.data.runtime.mana==23) -- no offline regeneration
assert(b.data.stats.sanity_conversion==20 and b.data.stats.mana_regen==18)
local paint=b.data.appearance.roll;assert(paint>=0 and paint<18 and b.data.appearance.appearance_schema==3)
local again=Component(entity());again:OnLoad(b:OnSave());assert(again.data.appearance.roll==paint)
saved.wand.runtime.mana=0
assert(b.data.runtime.mana==23) -- owns a deep copy
local corrupt=b:OnSave()
corrupt.wand.stats.sanity_conversion=30
corrupt.wand.runtime.deck={"prototype:1","prototype:1"}
b:OnLoad(corrupt)
assert(#b.data.runtime.deck==1)
assert(b.data.stats.sanity_conversion==30)
assert(b.data.runtime.remaining_recharge>=b.data.stats.recharge)
local invalid=U.copy(corrupt);invalid.wand.stats.mana_max=0/0
local c=Component(entity());c:OnLoad(invalid);assert(c.data==nil)
invalid=U.copy(corrupt);invalid.wand.cards[1]=true
c:OnLoad(invalid);assert(c.data==nil)
local old_target=U.copy(saved)
old_target.wand.cards[1].spell_id="target_players_all"
local migrated=Component(entity());migrated:OnLoad(old_target)
assert(migrated.data.cards[1].spell_id=="target_players_other")
assert(migrated.data.cards[1].card_uid==old_target.wand.cards[1].card_uid)
assert(migrated:OnSave().wand.cards[1].spell_id=="target_players_other")
local snapshot=U.copy(b.data)
assert(b:PreviewCast())
assert(b.data.runtime.mana==snapshot.runtime.mana) -- preview does not spend
for _,extreme in ipairs({{24,320,.08,.10},{1200,2,2.4,6}}) do
    local fixture=U.copy(saved)
    local s=fixture.wand.stats
    s.draw_count=6
    s.mana_max,s.mana_regen,s.cast_delay,s.recharge=unpack(extreme)
    local restored=Component(entity())
    restored:OnLoad(fixture)
    assert(restored.data.stats.draw_count==6 and restored.data.stats.recharge==s.recharge)
    assert(restored.data.stats.mana_regen==s.mana_regen and restored.inst._nw_ready.current)
end
print("component: save/load, offline time, invalid input, deck repair, preview isolation")
