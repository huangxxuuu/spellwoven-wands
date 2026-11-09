-- Count only actual live entities. Future payloads never reserve capacity.
-- Persistent placements use stable user IDs so reconnecting cannot reset a cap.
local Ledger=require("nw/budget")
local M={projectiles=0,fields=0,permanent_fields=0}
local ledgers={projectiles=Ledger.new(math.huge,math.huge),fields=Ledger.new(math.huge,math.huge),
    permanent_fields=Ledger.new(math.huge,math.huge)}
local records,queues={},{}
function M.category(p)
    if p.kind~="field" and p.kind~="note" then return "projectiles" end
    if p.id=="crystal_mine" or p.id=="sleep_crystal" or p.id=="payload_egg" then return "permanent_fields" end
    return "fields" -- native stars save to disk but still have an extinguish timer
end
local function unlink(record)
    local queue=record.queue
    if not queue then return end
    if record.prev then record.prev.next=record.next else queue.head=record.next end
    if record.next then record.next.prev=record.prev else queue.tail=record.prev end
    record.queue,record.prev,record.next=nil,nil,nil
    if not queue.head then queues[record.owner]=nil end
end
local allowed={[0]=true,[25]=true,[50]=true,[100]=true,[200]=true,[300]=true,[400]=true,
    [500]=true,[600]=true,[700]=true,[800]=true}
function M.configure(kind,value)
    if value==true then value=200 elseif value==false then value=0 end -- old boolean saves
    value=allowed[value] and value or 0
    M[kind]=value;ledgers[kind].per_player=value>0 and value or math.huge
end
function M.key(owner)
    if type(owner)=="string" then return owner end
    return owner and type(owner.userid)=="string" and owner.userid~="" and owner.userid
        or tostring(owner and owner.GUID or "neutral")
end
function M.acquire(owner,kind,loading)
    local ledger=ledgers[kind]
    local cap=ledger.per_player
    local key=M.key(owner)
    if kind=="permanent_fields" and not loading then
        while (ledger.owners[key] or 0)>=cap do
            local queue=queues[key]
            local oldest=queue and queue.head
            if not oldest then return end
            oldest.inst._nw_budget_evicted=true
            oldest.inst:Remove() -- silent removal: never break/detonate/release the payload
            oldest.release() -- idempotent, also supports native removal callbacks
        end
    end
    if loading then ledger.per_player=math.huge end
    local token=ledger:reserve(key,1)
    ledger.per_player=cap
    if not token then return end
    ledger:activate(token,1)
    local done=false
    local record={owner=key,kind=kind}
    local function release()
        if done then return end
        done=true;unlink(record);records[record.release]=nil;ledger:release(token,1,false)
    end
    record.release=release;records[release]=record
    return release
end
function M.bind(inst,release,order)
    inst._nw_live_budget=release
    local record=records[release]
    if record and record.kind=="permanent_fields" and not record.queue then
        local world=TheWorld
        if type(order)~="number" or order~=order or order==math.huge or order<0 then order=nil end
        world._nw_placement_order=math.max(world._nw_placement_order or 0,order or 0)
        if not order then world._nw_placement_order=world._nw_placement_order+1;order=world._nw_placement_order end
        record.inst,record.order=inst,order;inst._nw_permanent_order=order
        local queue=queues[record.owner] or {};queues[record.owner]=queue
        -- New runtime creations append in O(1). Only out-of-order save loading
        -- walks backward to restore the original creation order.
        local previous=queue.tail
        while previous and previous.order>order do previous=previous.prev end
        local following
        if previous then following=previous.next else following=queue.head end
        record.queue,record.prev,record.next=queue,previous,following
        if previous then previous.next=record else queue.head=record end
        if following then following.prev=record else queue.tail=record end
    end
    if inst.ListenForEvent then inst:ListenForEvent("onremove",release) end
end
function M.restore_field(inst,owner,kind,order)
    if inst._nw_live_budget then return end
    -- Loading never deletes saved objects, even when their count exceeds a cap.
    M.bind(inst,M.acquire(owner,kind or "fields",true),order)
end
function M.stats(kind) return ledgers[kind or "projectiles"].used end
function M.owner_used(owner,kind) return ledgers[kind or "projectiles"].owners[M.key(owner)] or 0 end
return M
