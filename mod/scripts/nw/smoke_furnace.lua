-- Exercise the original player channel state and real world/container entities.
local M={}
function M.run(x,z)
    local origin=x
    for step=0,80 do
        x=origin+step*5
        if TheWorld.Map:IsPassableAtPoint(x,0,z) and TheWorld.Map:IsPassableAtPoint(x+4,0,z)
            and #TheSim:FindEntities(x,0,z,6,nil,{"INLIMBO"},{"nw_disassembler","nw_spellcard","nw_wand","nw_spellpile"})==0 then break end
    end
    local furnace=SpawnPrefab("nw_disassembler")
    furnace.Transform:SetPosition(x,0,z)
    local player=SpawnPrefab("wilson")
    player.entity:SetCanSleep(false)
    player.userid=""
    player:AddComponent("playeractionpicker");player:AddComponent("playercontroller")
    local pc=player.components.playercontroller
    pc:Enable(true)
    player.Physics:Teleport(x+1.3,0,z)
    local function put(id,dx,dz)
        local item=SpawnPrefab(id)
        item.Transform:SetPosition(x+dx,0,z+dz)
        return item
    end
    local function start()
        local act=BufferedAction(player,furnace,ACTIONS.NW_RECYCLE)
        player.sg:GoToState("idle")
        pc:DoAction(act)

    end
    local cards={}
    for i=1,5 do cards[i]=put("nw_spellcard",i*.3,1) end
    local distant=put("nw_spellcard",4.25,0)
    start()
    local function live()
        local n=0
        for _,c in ipairs(cards) do if c:IsValid() then n=n+1 end end
        return n
    end
    local watch
    watch=furnace:DoPeriodicTask(FRAMES,function()
        if live()<5 then
            watch:Cancel()
            local remain=live()
            assert(remain>0,"NW_FURNACE: no interval between conversions")
            pc:OnRemoteDirectWalking(1,0);pc:DoDirectWalking(FRAMES)
            player.Physics:Teleport(x+6,0,z)
            furnace:DoTaskInTime(2.2,function()
                assert(live()==remain and not furnace._nw_run and distant:IsValid(),"NW_FURNACE: cancellation lost")
                for _,c in ipairs(cards) do
                    if c:IsValid() then assert(not c._nw_mark:value());c:Remove() end
                end
                local box=put("nw_spellpile",0,2)
                for i=1,4 do assert(box.components.container:GiveItem(SpawnPrefab("nw_spellcard"))) end
                local wand=put("nw_wand",0,-2)
                wand.components.nw_wand:InitializeNew(0,"smoke")
                local uid=wand.components.nw_wand.data.cards[1].card_uid
                player.Physics:Teleport(x+1.3,0,z)
                pc:OnRemoteStopWalking()
                player.components.locomotor:Stop()
                player.sg:GoToState("idle")
                start()
                furnace:DoTaskInTime(6.5,function()
                    assert(not box:IsValid() and not wand:IsValid() and not furnace._nw_run and distant:IsValid(),"NW_FURNACE: completion")
                    local result=TheSim:FindEntities(x,0,z-2,.4,{"nw_spellcard"})
                    assert(#result==1 and result[1].card_uid==uid and result[1].spell_id=="spark","NW_FURNACE: wand card lost")
                    local dust=TheSim:FindEntities(x,0,z+2,.4,{"_inventoryitem"})
                    local count=0
                    for _,item in ipairs(dust) do if item.prefab=="nw_dust" then count=count+item.components.stackable:StackSize() end end
                    assert(count==4,"NW_FURNACE: pile refund")
                    print("NW_FURNACE_PASS: cancelled after first conversion, pile refund, original wand card and four-unit boundary")
                    player:Remove();furnace:Remove();distant:Remove()
                end)
            end)
        end
    end)
    furnace:DoTaskInTime(10,function()
        assert(live()<5,"NW_FURNACE: native action never converted an item")
    end)
end
return M
