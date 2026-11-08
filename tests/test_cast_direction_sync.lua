local Direction=require("nw/cast_direction")
local load_cb,writes,packets=nil,{},{}
local now,tasks=0,{}
local function timer(owner,delay,fn,period)
    local t={owner=owner,due=now+delay,fn=fn,period=period,Cancel=function(self) self.cancelled=true end}
    tasks[#tasks+1]=t
    return t
end
local function advance_to(finish)
    while true do
        local nexttask
        for _,t in ipairs(tasks) do
            if not t.cancelled and not t.done and t.due<=finish
                and (not nexttask or t.due<nexttask.due) then nexttask=t end
        end
        if not nexttask then break end
        now=nexttask.due
        if nexttask.period then nexttask.due=now+nexttask.period else nexttask.done=true end
        nexttask.fn()
    end
    now=finish
end
local function active(owner,periodic)
    local n=0
    for _,t in ipairs(tasks) do
        if t.owner==owner and not t.cancelled and not t.done and (t.period~=nil)==periodic then n=n+1 end
    end
    return n
end
TheSim={GetPersistentString=function(_,_,cb) load_cb=cb end,
    SetPersistentString=function(_,_,value,_,cb) writes[#writes+1]=value;cb() end}
local rpc,post,components={}, {},{}
local env={AddModRPCHandler=function(ns,key,fn) rpc[key]=fn end,
    AddPlayerPostInit=function(fn) post[#post+1]=fn end,
    AddComponentPostInit=function(name,fn) components[name]=fn end}
local G={TheNet={IsDedicated=function() return false end},TheWorld={ismastersim=false},
    MOD_RPC={nw_weave={cast_direction=42}},
    SendModRPCToServer=function(...) local packet={...};packet.at=now;packets[#packets+1]=packet end}
TheWorld=G.TheWorld
Direction.install(env,G)
assert(components.playeractionpicker and not components.playercontroller,"must not attach a controller hook")
assert(rpc.cast_direction==Direction.receive)
local function player()
    local p={components={},events={}}
    p.components.playercontroller={UsingMouse=function() return not p.gamepad end}
    function p:IsValid() return not self.dead end
    function p:ListenForEvent(name,fn)
        self.events[name]=self.events[name] or {};table.insert(self.events[name],fn)
    end
    function p:PushEvent(name) for _,fn in ipairs(self.events[name] or {}) do fn(self) end end
    function p:DoTaskInTime(delay,fn) return timer(self,delay,fn) end
    function p:DoPeriodicTask(interval,fn)
        assert(interval==60);return timer(self,interval,fn,interval)
    end
    for _,fn in ipairs(post) do fn(p) end
    return p
end
local p=player();G.ThePlayer=p;ThePlayer=p;advance_to(0)
assert(active(p,true)==1 and #packets==0,"wait for the persisted setting before first sync")
advance_to(60);assert(#packets==0,"heartbeat must not send a temporary default while disk loading")
load_cb(true,"mouse")
assert(#packets==1 and packets[1][1]==42 and packets[1][2]=="mouse" and packets[1][3]==true)
assert(Direction.uses_mouse(p))
p:PushEvent("playeractivated");assert(active(p,true)==1,"activation duplicated the heartbeat")
local count=#packets
Direction.set("target")
assert(#packets==count and writes[#writes]=="target" and Direction.get()=="target")
assert(Direction.uses_mouse(p),"prediction must keep the old mode while waiting to sync")
advance_to(60.5);Direction.set("mouse")
advance_to(61);Direction.set("target")
advance_to(61.999);assert(#packets==count and active(p,false)==1)
advance_to(62.001)
assert(#packets==count+1 and packets[#packets][2]=="target" and not Direction.uses_mouse(p))
assert(active(p,true)==1 and active(p,false)==0)
-- The minute heartbeat falls inside an edit's debounce window: it must wait.
advance_to(121.5);Direction.set("mouse");count=#packets
p:PushEvent("playeractivated");assert(#packets==count,"activation bypassed debounce")
advance_to(122.1);assert(#packets==count,"heartbeat bypassed debounce")
advance_to(122.51);assert(#packets==count+1 and packets[#packets][2]=="mouse")
assert(Direction.uses_mouse(p))
-- Edits restart the fallback interval, avoiding a redundant send immediately afterward.
count=#packets;advance_to(182.49);assert(#packets==count)
advance_to(182.51);assert(#packets==count+1 and packets[#packets][2]=="mouse")
local other=player();advance_to(now);other:PushEvent("playeractivated")
assert(active(other,true)==0 and #packets==count+1,"remote actors must not send local settings")
p.gamepad=true;advance_to(242.51)
assert(packets[#packets][2]=="mouse" and packets[#packets][3]==false and Direction.get()=="mouse")
-- Leaving cancels both the delayed edit and fallback. Disk persistence is immediate.
Direction.set("target");assert(writes[#writes]=="target")
p:PushEvent("playerdeactivated");assert(active(p,true)==0 and active(p,false)==0)
count=#packets;advance_to(245);assert(#packets==count)
-- Reconnection/shard entry sends the persisted preference without the edit delay.
local nextplayer=player();G.ThePlayer=nextplayer;ThePlayer=nextplayer;advance_to(now)
assert(active(nextplayer,true)==1 and #packets==count+1 and packets[#packets][2]=="target")
Direction.set("mouse");nextplayer:PushEvent("onremove")
assert(active(nextplayer,true)==0 and active(nextplayer,false)==0)
-- The listen host obeys the same delay, through the same server validation.
G.TheWorld.ismastersim=true
local host=player();G.ThePlayer=host;ThePlayer=host;advance_to(now)
assert(host._nw_cast_direction=="mouse" and host._nw_cast_mouse_input)
Direction.set("target");advance_to(245.999);assert(host._nw_cast_direction=="mouse")
advance_to(246.001);assert(host._nw_cast_direction=="target")
-- A late disk response cannot bypass or overwrite the last user choice.
host:PushEvent("onremove")
package.loaded["nw/cast_direction"]=nil
Direction=require("nw/cast_direction");post={};G.TheWorld.ismastersim=false
Direction.install(env,G)
local loadingplayer=player();G.ThePlayer=loadingplayer;ThePlayer=loadingplayer;advance_to(now)
Direction.set("mouse");count=#packets;load_cb(true,"target")
assert(#packets==count and Direction.get()=="mouse")
advance_to(247.01);assert(#packets==count+1 and packets[#packets][2]=="mouse")
-- Dedicated servers never load local preferences or start a sync timer.
package.loaded["nw/cast_direction"]=nil
local dedicated=require("nw/cast_direction")
G.TheNet.IsDedicated=function() return true end
TheSim.GetPersistentString=function() error("server accessed client storage") end
dedicated.install(env,G)
assert(dedicated.get()=="target")
print("cast direction sync: immediate saved entry, 1-second debounce, latest-only edits, 60-second fallback, lifecycle cleanup and host parity")
