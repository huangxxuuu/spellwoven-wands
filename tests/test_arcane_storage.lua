local Storage=require("nw/arcane_storage")
local Rules=require("nw/acquisition")
local normal=Rules.materials.nw_dust[3]
assert(Storage.FULL_THRESHOLD==2*normal)
assert(Storage.DUST_SECONDS==60)
-- Restarting with a different material stack limit must update both containers'
-- shared half/full boundary, without changing either prefab or a second value.
for _,limit in ipairs({20,40,100}) do
    Rules.materials.nw_dust[3]=limit
    package.loaded["nw/arcane_storage"]=nil
    local configured=require("nw/arcane_storage")
    assert(configured.FULL_THRESHOLD==2*limit,"threshold must follow dust stack configuration")
    assert(configured.StateForCount(0)=="empty")
    assert(configured.StateForCount(1)=="half")
    assert(configured.StateForCount(2*limit)=="half","exactly two stacks must remain half-full")
    assert(configured.StateForCount(2*limit+1)=="full","more than two stacks must be full")
end
Rules.materials.nw_dust[3]=normal
package.loaded["nw/arcane_storage"]=Storage
for _,row in ipairs({{0,"empty"},{1,"half"},{80,"half"},{81,"full"},{12000,"full"}}) do
    assert(Storage.StateForCount(row[1])==row[2],"storage visual threshold")
end
assert(Storage.Count(nil)==0)

-- A native merge changes the retained stack without another itemget event.
local tasks={}
local function entity()
    local inst={components={},listeners={}}
    function inst:ListenForEvent(event,fn,source)
        source=source or self
        source.listeners[event]=source.listeners[event] or {}
        source.listeners[event][fn]=self
    end
    function inst:RemoveEventCallback(event,fn,source)
        source=source or self
        if source.listeners[event] then source.listeners[event][fn]=nil end
    end
    function inst:PushEvent(event,data)
        for fn in pairs(self.listeners[event] or {}) do fn(self,data) end
    end
    function inst:DoTaskInTime(_,fn)
        local task={fn=fn,inst=self}
        function task:Cancel() self.cancelled=true end
        tasks[#tasks+1]=task
        return task
    end
    return inst
end
local function flush()
    local due=tasks;tasks={}
    for _,task in ipairs(due) do if not task.cancelled then task.fn(task.inst) end end
end
local function item(n,prefab)
    local e=entity();e.prefab=prefab or "nw_dust"
    e.components.stackable={StackSize=function() return n end,
        SetStackSize=function(_,value) n=value;e:PushEvent("stacksizechange") end}
    return e
end
local holder=entity()
local slot
holder.components.container={GetItemInSlot=function(_,index) assert(index==1);return slot end}
local callbacks={}
local refresh=Storage.Watch(holder,function(inst,state,count)
    assert(inst==holder)
    callbacks[#callbacks+1]={state,count}
end)
assert(refresh==holder._nw_storage_refresh and #callbacks==0)
flush();assert(#callbacks==1 and callbacks[1][1]=="empty" and callbacks[1][2]==0)
slot=item(40);holder:PushEvent("itemget");flush()
assert(callbacks[#callbacks][1]=="half" and callbacks[#callbacks][2]==40)
local first=slot
local before=#callbacks
slot.components.stackable:SetStackSize(80)
slot.components.stackable:SetStackSize(81)
assert(#callbacks==before,"stack events must wait for transfer completion")
flush();assert(#callbacks==before+1 and callbacks[#callbacks][1]=="full" and callbacks[#callbacks][2]==81)
slot.components.stackable:SetStackSize(80);flush()
assert(callbacks[#callbacks][1]=="half" and callbacks[#callbacks][2]==80,"native split crosses boundary")
slot=nil;holder:PushEvent("itemlose")
slot=item(1);holder:PushEvent("itemget");flush()
assert(callbacks[#callbacks][2]==1)
before=#callbacks
first.components.stackable:SetStackSize(12000);flush()
assert(#callbacks==before,"removed stack still updates its old container")
assert(next(first.listeners.stacksizechange)==nil and next(first.listeners.onremove)==nil)
slot.components.stackable:SetStackSize(81);flush()
assert(callbacks[#callbacks][1]=="full","replacement stack not observed")
local second=slot
slot=nil;holder:PushEvent("itemlose");second:PushEvent("onremove");flush()
assert(callbacks[#callbacks][1]=="empty" and callbacks[#callbacks][2]==0)
slot=item(10,"redgem");assert(Storage.Count(holder.components.container)==0)
slot={prefab="nw_dust",components={}};assert(Storage.Count(holder.components.container)==1)
slot=item(4);holder:PushEvent("itemget");flush()
before=#callbacks
slot.components.stackable:SetStackSize(99)
holder:PushEvent("onremove");flush()
assert(#callbacks==before,"removed container ran a queued refresh")
assert(next(slot.listeners.stacksizechange)==nil and next(slot.listeners.onremove)==nil)
print("arcane storage: thresholds, native merge/split event boundary, replacement and listener cleanup")
