local owner={valid=true,components={combat={}},IsValid=function(self) return self.valid end}
local attacker={valid=true,components={combat={}},IsValid=owner.IsValid}
local available=true
package.loaded["nw/persistent_fields"]={owner=function() return available and owner or nil end,
    caster=function(e) return e and e.valid and e or nil end}
local Fields=require("nw/expanded_fields")
local Effects=require("nw/spell_effects")
local Caster=require("nw/payload_caster")
local neutral={};Caster.neutral=function() return neutral end
local blasts,last=0
local actual_blast=Effects.blast
Effects.blast=function(who) blasts=blasts+1;last=who end
local function crystal()
    local e={events={},components={},valid=true,_nw_stored={p={id="sleep_crystal"}}}
    e.Transform={GetWorldPosition=function() return 2,0,3 end}
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false end
    function e:AddComponent(name)
        self.components[name]={SetMaxHealth=function() end,SetInvincible=function() end}
    end
    function e:ListenForEvent(name,fn) self.events[name]=fn end
    Fields.attackable(e)
    Fields.actions.sleep_crystal(e,owner,{id="sleep_crystal",radius=1.8,flags={}},2,3)
    return e
end
for _,event in ipairs({"attacked","blocked","explosion"}) do
    local e=crystal();local before=blasts
    assert(Fields.can_break(e,attacker))
    e.events[event](e,{attacker=attacker,explosive={components={},_nw_owner=attacker}})
    e.events[event](e,{attacker=attacker})
    assert(blasts==before+1 and last==owner and not e.valid,"any attack detonates exactly once with the live placer's attribution")
end
available=false
local e=crystal();local before=blasts
e._nw_break();assert(blasts==before and e.valid,"unavailable owner still pauses command activation")
e.events.attacked(e,{attacker=attacker})
assert(last==attacker and not e.valid,"an offline placer cannot prevent physical detonation")
e=crystal();e.events.explosion(e,nil);assert(last==neutral and not e.valid)
-- Area attacks must not discard crystals because nw_breakable is excluded
-- from ordinary creature targeting.
local hit=0
local field={_nw_stored={p={id="sleep_crystal"}},_nw_break=function(who) assert(who==attacker);hit=hit+1 end,
    IsValid=function() return true end,GetDistanceSqToPoint=function() return 0 end}
Effects.scan=function() return {field} end;Effects.fx=function() end
actual_blast(attacker,0,0,{radius=3,flags={}})
assert(hit==1 and require("nw/targeting").hittable(attacker,field,{}))
require("nw/targeting").damage(attacker,field,1,{})
assert(hit==2)
print("crystal attacks: weapon/blocked/explosion/area, exactly once, offline attribution, command pause")
