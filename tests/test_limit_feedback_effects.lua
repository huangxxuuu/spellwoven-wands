local Limits=require("nw/entity_limits")
local reports={}
require("nw/limit_feedback").limited=function(owner) reports[#reports+1]=owner end
TheWorld={}
local a={userid="KU_a"}
Limits.configure("permanent_fields",25)
local fields={}
for i=1,26 do
    local inst={ListenForEvent=function(self,event,fn) self.onremove=fn end}
    function inst:Remove() self.removed=true;self.onremove() end
    local release=assert(Limits.acquire(a,"permanent_fields"))
    Limits.bind(inst,release);fields[i]=inst
    assert(#reports==(i==26 and 1 or 0),"only actual eviction reports a limit")
end
assert(fields[1].removed and reports[1]==a)
-- Save restoration may exceed the current cap but is not a new limit effect.
Limits.restore_field({ListenForEvent=function() end},"KU_a","permanent_fields",100)
assert(#reports==1)
Limits.configure("fields",25)
for i=1,25 do assert(Limits.acquire(a,"fields")) end
assert(not Limits.acquire(a,"fields") and reports[2]==a)
assert(Limits.acquire({userid="KU_b"},"fields") and #reports==2,"other players have independent pools")
print("limit feedback effects: silent permanent eviction, no false report during restoration, actual timed denial and independent owners")
