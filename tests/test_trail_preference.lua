local reads,writes={},{}
TheSim={GetPersistentString=function(_,key,cb) reads[#reads+1]={key=key,callback=cb} end,
    SetPersistentString=function(_,key,value,encode,cb)
        assert(not encode);writes[#writes+1]={key=key,value=value,callback=cb}
    end}
local Trail=require("nw/trail_budget")
local env={GetModConfigData=function(key,local_only) assert(local_only);return 500 end}
local client={TheNet={IsDedicated=function() return false end}}
local dedicated={TheNet={IsDedicated=function() return true end}}
Trail.install(env,dedicated);assert(#reads==0)
Trail.install(env,client);assert(Trail.limit==500 and #reads==1)
local refreshed=0
Trail.load(function() refreshed=refreshed+1 end);assert(#reads==1)
-- Anyone may edit immediately; a late saved value cannot overwrite the edit.
assert(Trail.set(900) and Trail.limit==900 and writes[1].value=="900")
reads[1].callback(true,"100")
assert(Trail.limit==900 and refreshed==1)
-- Rapid edits serialize disk writes and save only the latest queued value.
assert(Trail.set(1300) and Trail.set(0) and Trail.limit==0 and #writes==1)
writes[1].callback();assert(#writes==2 and writes[2].value=="0")
writes[2].callback()
assert(not Trail.set(123) and not Trail.set("900") and #writes==2)
Trail.install(env,client);assert(Trail.limit==0 and #reads==1,"re-entering a world retains the personal choice")
Trail.load(function() refreshed=refreshed+1 end);assert(refreshed==2)
-- A new process restores the saved override, including explicit unlimited.
package.loaded["nw/trail_budget"]=nil
Trail=require("nw/trail_budget");Trail.install(env,client)
reads[2].callback(true,"0");assert(Trail.limit==0)
package.loaded["nw/trail_budget"]=nil
Trail=require("nw/trail_budget");Trail.install(env,client)
reads[3].callback(true,"1300");assert(Trail.limit==1300)
-- Previous personal choices migrate to the nearest available higher tier.
for old,new in pairs({[200]=500,[400]=500,[600]=900,[700]=900,[800]=900,
    [1000]=1300,[1600]=1700,[1900]=2100,[2000]=2100}) do
    package.loaded["nw/trail_budget"]=nil
    Trail=require("nw/trail_budget");Trail.install(env,client)
    reads[#reads].callback(true,tostring(old));assert(Trail.limit==new)
    Trail.configure(old);assert(Trail.limit==new,"mod defaults use the same migration")
end
-- Corrupt/missing preferences keep the mod's initial default.
for _,value in ipairs({"garbage","123",""}) do
    package.loaded["nw/trail_budget"]=nil
    Trail=require("nw/trail_budget");Trail.install(env,client)
    reads[#reads].callback(true,value);assert(Trail.limit==500)
end
print("trail preference: local-only edits, dedicated skip, defaults, disk restoration, explicit unlimited, late-read race and serialized latest-value writes")
