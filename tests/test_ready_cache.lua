local now=0;GetTime=function() return now end
Class=function(ctor) local c={};c.__index=c;return setmetatable(c,{__call=function(_,...) local o=setmetatable({},c);ctor(o,...);return o end}) end
EQUIPSLOTS={HANDS="hands"}
local function net() return {set=function(self,v) self.v=v end,value=function(self) return self.v end} end
local C=require("nw/compiler");local compile=C.compile;local calls=0
C.compile=function(...) calls=calls+1;return compile(...) end
for _,d in pairs(require("nw/definitions").spells) do assert(d.mana==math.floor(d.mana),"fractional mana requires finer readiness cache key") end
local W=require("components/nw_wand")
local inst={_nw_capacity=net(),_nw_mana=net(),_nw_ready=net(),_nw_cancast=net()}
inst.AddTag=function() end;inst.RemoveTag=function() end
local w=W(inst);w:InitializePrototype()
local player={IsValid=function() return true end,components={health={IsDead=function() return false end},inventory={GetEquippedItem=function() return inst end}}}
calls=0;for i=1,1000 do assert(w:CanCast(player)) end;assert(calls==0)
w.data.runtime.mana=4.9;assert(not w:CanCast(player));assert(calls==1 and not inst._nw_cancast:value())
w.data.runtime.mana=4.99;assert(not w:CanCast(player));assert(calls==1)
w.data.runtime.mana=5;assert(w:CanCast(player));assert(calls==2 and inst._nw_cancast:value())
for m=6,119 do w.data.runtime.mana=m;assert(w:CanCast(player)) end
assert(calls==2,"affordable shots recompiled on each mana point during regeneration")
w.data.runtime.remaining_cast=1;assert(not w:CanCast(player) and not inst._nw_cancast:value())
w.data.runtime.remaining_cast=0;assert(w:CanCast(player));assert(calls==2)
w:SetTestLoadout("double");assert(w:CanCast(player));local n=calls
w.data.config_revision=w.data.config_revision+1;assert(w:CanCast(player));assert(calls==n+1)
local saved=w:OnSave();w:OnLoad(saved);assert(w:CanCast(player));assert(calls==n+2)
local oldplan=assert(w:ReadyPlan())
local Limits=require("nw/spell_limits");Limits.depth=1
local before=calls
assert(w:ReadyPlan()==oldplan and calls==before,"runtime emission limits must not invalidate the spell draw")
assert(w:CanCast(player,oldplan),"emission limits must not reject an already prepared cast")
Limits.depth=0
print("readiness cache: draw remains valid across runtime emission-limit changes")
