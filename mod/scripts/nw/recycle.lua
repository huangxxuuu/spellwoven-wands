local T=require("nw/locale").t
local M={}
local radius=4
local tags={"nw_spellcard","nw_spellpile","nw_wand"}

function M.amount(item)
    if item.prefab=="nw_spellcard" then return item.components.stackable:StackSize() end
    if item.prefab=="nw_spellpile" then return item.components.container:NumItems() end
    local wand=item.components.nw_wand
    local data=wand and wand.data
    if data then
        return (data.starter or data.source=="legacy" or data.source=="debug") and 1
            or ({4,8,12,20})[data.tier]
    end
end

local function ground(item)
    if not item:IsValid() or item:HasTag("INLIMBO") or item.entity:GetParent() then return false end
    local inv=item.components.inventoryitem
    return (not inv or not inv.owner) and (not item.components.container or not item.components.container:IsOpen())
end

local function valid(entry,station)
    local item=entry.item
    if not ground(item) or item._nw_claim~=station then return false end
    local x,_,z=item.Transform:GetWorldPosition()
    return (x-entry.x)^2+(z-entry.z)^2<.01 and item:IsNear(station,radius)
end

local function release(entry,station)
    local item=entry.item
    if item:IsValid() and item._nw_claim==station then
        item._nw_claim=nil
        item:SetNWMarked(false)
        for _,event in ipairs(entry.events) do
            station:RemoveEventCallback(event,entry.invalidate,item)
        end
    end
    entry.expired=true
end

-- Stage all outputs before consuming one ground object. Pile contents are real
-- entities; remove them explicitly so the vanilla container cannot spill them.
local function convert(item,station)
    local count=M.amount(item)
    if not count or count<1 then return end
    local dust=SpawnPrefab("nw_dust")
    if not dust then return end
    local outputs={dust}
    local wand=item.components.nw_wand
    if wand then
        for _,slot in ipairs(wand.data.cards) do
            if slot then
                local card=require("nw/cards").codes[slot.spell_id] and SpawnPrefab("nw_spellcard")
                if not card then
                    for _,out in ipairs(outputs) do out:Remove() end
                    return
                end
                card:SetSpell(slot.spell_id)
                card.card_uid,card.source=slot.card_uid,slot.source
                outputs[#outputs+1]=card
            end
        end
    end
    local x,y,z=item.Transform:GetWorldPosition()
    dust.components.stackable:SetStackSize(count)
    local box=item.components.container
    if box then
        for i=1,box:GetNumSlots() do
            local card=box:RemoveItemBySlot(i)
            if card then card:Remove() end
        end
    end
    for _,out in ipairs(outputs) do out.Transform:SetPosition(x,y,z) end
    local flash=SpawnPrefab("carnival_sparkle_fx")
    if flash then flash.Transform:SetPosition(x,y+.15,z) end
    item:Remove()
    if not station._nw_pulse or GetTime()-station._nw_pulse>.18 then
        station._nw_pulse=GetTime()
        station.AnimState:PlayAnimation("pulse")
        station.AnimState:PushAnimation("active",true)
    end
end

local function say(player,text,...)
    if player:IsValid() and player.components.talker then player.components.talker:Say(string.format(require("nw/locale").for_player(player,text),...)) end
end

function M.stop(station)
    local run=station._nw_run
    if not run then return end
    station._nw_run=nil
    run.task:Cancel()
    for _,entry in ipairs(run.entries) do release(entry,station) end
    station:SetNWActive(false)
end

function M.start(station,player)
    local x,y,z=station.Transform:GetWorldPosition()
    local run={entries={},start=GetTime(),phase=1,next=1,queue={}}
    station._nw_run=run
    station:SetNWActive(true)
    say(player,T("准备分解，检索地面物品。"))
    for _,item in ipairs(TheSim:FindEntities(x,y,z,radius,nil,{"INLIMBO"},tags)) do
        if ground(item) and not item._nw_claim then
            local ix,_,iz=item.Transform:GetWorldPosition()
            local entry={item=item,x=ix,z=iz,distance=math.sqrt((ix-x)^2+(iz-z)^2),
                events={"onputininventory","onopen","itemget","itemlose"}}
            item._nw_claim=station
            entry.invalidate=function() release(entry,station) end
            for _,event in ipairs(entry.events) do station:ListenForEvent(event,entry.invalidate,item) end
            run.entries[#run.entries+1]=entry
        end
    end
    local channel=station.components.channelable
    local function finish(message)
        channel:StopChanneling(false)
        say(player,message)
    end
    run.task=station:DoPeriodicTask(FRAMES,function()
        if channel.channeler~=player or not player:IsValid() or not channel:IsChanneling(player)
            or player.sg.statemem.target~=station or not player:IsNear(station,3)
            or player.components.health:IsDead() then
            channel:StopChanneling(true)
            return
        end
        local elapsed=GetTime()-run.start
        if run.phase==1 then
            local cards,wands=0,0
            for _,entry in ipairs(run.entries) do
                if not entry.expired then
                    if not valid(entry,station) then
                        release(entry,station)
                    elseif entry.distance<=radius*math.min(1,elapsed/2) then
                        if not entry.marked then
                            entry.item:SetNWMarked(true)
                            entry.marked=true
                        end
                        if elapsed>=2 then
                            local count=M.amount(entry.item)
                            if count and count>0 then
                                run.queue[#run.queue+1]=entry
                                if entry.item.prefab=="nw_wand" then wands=wands+1 else cards=cards+count end
                            end
                        end
                    end
                end
            end
            if elapsed>=2 then
                if #run.queue==0 then finish(T("附近没有可分解的物品。"));return end
                run.phase=2
                say(player,T("有 %d 张法术卡、%d 根法杖将被分解。"),cards,wands)
            end
        elseif run.phase==2 and elapsed>=3 then
            run.phase=3
            say(player,T("开始分解。"))
            for i=#run.queue,2,-1 do
                local j=math.random(i)
                run.queue[i],run.queue[j]=run.queue[j],run.queue[i]
            end
            for i,entry in ipairs(run.queue) do
                entry.at=3+2*(i-1+.15+.7*math.random())/#run.queue
            end
        elseif run.phase==3 then
            while run.queue[run.next] and run.queue[run.next].at<=elapsed do
                local entry=run.queue[run.next]
                run.next=run.next+1
                if not entry.expired and valid(entry,station) then
                    release(entry,station)
                    convert(entry.item,station)
                end
            end
            if elapsed>=5 then finish(T("分解完成。")) end
        end
    end)
end

function M.install(env)
    local action=Action({priority=12,rmb=true,distance=1.4,silent_fail=true})
    action.id,action.str="NW_RECYCLE",T("分解附近物品")
    action.fn=function(act)
        local target=act.target
        return target and target:IsValid() and target.prefab=="nw_disassembler"
            and not target._nw_run and act.doer:IsNear(target,3)
            and target.components.channelable:StartChanneling(act.doer)
    end
    env.AddAction(action)
    env.AddComponentAction("SCENE","inspectable",function(target,doer,actions,right)
        if right and target:HasTag("nw_disassembler") and not target:HasTag("channeled") then
            actions[#actions+1]=action
        end
    end)
    for _,sg in ipairs({"wilson","wilson_client"}) do
        env.AddStategraphActionHandler(sg,ActionHandler(action,"startchanneling"))
    end
end
return M
