local reads,writes,rpcs={},{},{}
TheSim={GetPersistentString=function(_,key,cb) reads[#reads+1]=cb end,
    SetPersistentString=function(_,key,value,encode,cb) writes[#writes+1]={value=value,cb=cb} end}
local Feedback=require("nw/limit_feedback")
local handlers,post={},nil
local env={AddModRPCHandler=function(_,name,fn) handlers[name]=fn end,
    AddPlayerPostInit=function(fn) post=fn end}
local G={TheNet={IsDedicated=function() return true end}}
Feedback.install(env,G);assert(#reads==0 and not post)
local now=0
GetTime=function() return now end
TheWorld={ismastersim=true}
local function player(id,lang)
    local p={userid=id,_nw_language=lang,components={},said={},IsValid=function() return true end,HasTag=function() return false end}
    p.components.talker={Say=function(_,line) p.said[#p.said+1]=line end}
    p.ListenForEvent=function(self,event,fn) self[event]=fn end
    p.DoTaskInTime=function(self,delay,fn) self.activate=fn end
    return p
end
local a,b=player("KU_a","zh"),player("KU_b","en")
AllPlayers={a,b}
assert(not Feedback.limited(a),"no speech before personal preference arrives")
handlers.limit_speech(a,true);handlers.limit_speech(b,true)
assert(Feedback.limited(a) and Feedback.limited(b))
assert(a.said[1]=="这世界限制了我的发挥。" and b.said[1]=="This world is holding my magic back.")
assert(not Feedback.limited(a));now=29.99;assert(not Feedback.limited(a))
now=30;assert(Feedback.limited(a) and a.said[2]~=a.said[1])
handlers.limit_speech(a,false);now=60
assert(not Feedback.limited(a) and Feedback.limited(b),"one player cannot disable another")
handlers.limit_speech(a,"true");assert(not a._nw_limit_speech_enabled)
handlers.limit_speech(a,true)
assert(Feedback.limited("KU_a"),"saved owner ids target the live player")
assert(not Feedback.limited({GUID=5,_nw_neutral=true}) and not Feedback.limited("offline"))
now=90
local replacement=player("KU_a","zh");replacement._nw_limit_speech_enabled=true
AllPlayers={replacement,b};assert(Feedback.limited(replacement))
local line=replacement.said[1];assert(line~=a.said[2],"rotation survives reconnect")
now=91;assert(not Feedback.limited(replacement),"cooldown survives player-entity replacement")
now=120;replacement.HasTag=function() return true end;assert(not Feedback.limited(replacement))
replacement.HasTag=function() return false end
replacement.components.health={IsDead=function() return true end};assert(not Feedback.limited(replacement))
TheWorld.ismastersim=false;assert(not Feedback.limited(b));TheWorld.ismastersim=true
-- A fresh world has a new clock and cannot inherit old cooldown timestamps.
TheWorld={ismastersim=true};now=0
assert(Feedback.limited(b),"world restart clears old timestamps")
handlers.limit_speech(nil,true)
-- Local preference defaults, serialization and stale-read protection.
ThePlayer=a;G.ThePlayer=a
MOD_RPC={nw_weave={limit_speech="speech"}}
SendModRPCToServer=function(rpc,value) rpcs[#rpcs+1]=value end
G.TheNet.IsDedicated=function() return false end
Feedback.install(env,G);assert(#reads==1)
assert(Feedback.set(false) and writes[1].value=="false" and rpcs[#rpcs]==false)
reads[1](true,"true");assert(not Feedback.enabled,"late disk reads cannot overwrite a current choice")
assert(Feedback.set(true) and Feedback.set(false) and #writes==1)
writes[1].cb();assert(#writes==2 and writes[2].value=="false");writes[2].cb()
assert(not Feedback.set("false"))
post(a);a.activate();assert(rpcs[#rpcs]==false,"re-entering syncs the local choice")
package.loaded["nw/limit_feedback"]=nil
Feedback=require("nw/limit_feedback");Feedback.install(env,G);reads[2](true,"false")
assert(not Feedback.enabled and rpcs[#rpcs]==false,"a fresh process restores explicit off")
print("limit feedback: server speech, per-user ownership/localization/rotation, 30-second shared cooldown, reconnect, ghosts/dead/neutral/offline safety, own-player RPC, local persistence and races")
