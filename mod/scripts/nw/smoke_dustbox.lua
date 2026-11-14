local M={}
function M.run()
    local storage=require("nw/arcane_storage")
    local entities={}
    local x,z=0,0
    for _,e in pairs(Ents) do
        if e:HasTag("multiplayer_portal") then x,_,z=e.Transform:GetWorldPosition();break end
    end
    local function remember(e) entities[#entities+1]=e;return e end
    local function spawn(name,dx,dz)
        local e=remember(assert(SpawnPrefab(name),name))
        e.Transform:SetPosition(x+(dx or 0),0,z+(dz or 0))
        e.entity:SetCanSleep(false)
        if e.components.health then e.components.health:SetInvincible(true) end
        return e
    end
    local function cleanup()
        for _,e in ipairs(entities) do if e:IsValid() then e:Remove() end end
    end
    local function wait(frames) coroutine.yield((frames or 3)*FRAMES) end
    local function count(inst) return storage.Count(inst.components.container) end
    local function animation(inst,name)
        for _=1,90 do
            if inst.AnimState:IsCurrentAnimation(name) then return end
            wait(1)
        end
        error(inst.prefab..": expected animation "..name)
    end
    local function near(a,b,label,tolerance)
        assert(math.abs(a-b)<(tolerance or .001),
            string.format("%s: actual=%.9f expected=%.9f",label,a,b))
    end
    local function hasaction(inst,kind,doer,action,right)
        local actions={}
        inst:CollectActions(kind,doer,actions,right)
        for _,found in ipairs(actions) do if found==action then return true end end
        return false
    end
    local function rummage(player,inst,carried)
        local action=BufferedAction(player,not carried and inst or nil,
            ACTIONS.RUMMAGE,carried and inst or nil)
        if carried then
            local wasopen=inst.components.container:IsOpenedBy(player) and true or false
            player:PushBufferedAction(action)
            for _=1,90 do
                wait(1)
                local opened=inst.components.container:IsOpenedBy(player) and true or false
                if opened~=wasopen then return end
            end
            error("native pocket RUMMAGE did not change open state")
        end
        assert(ACTIONS.RUMMAGE.fn(action),"native RUMMAGE failed")
    end
    local function empty(inst)
        local total=0
        while inst.components.container:GetItemInSlot(1) do
            local before=count(inst)
            local item=remember(assert(inst.components.container:RemoveItemBySlot(1,true)))
            total=total+item.components.stackable:StackSize()
            item:Remove()
            assert(count(inst)<before,"native withdrawal made no progress")
        end
        return total
    end
    local function put(inst,n)
        while n>0 do
            local amount=math.min(n,40)
            local dust=spawn("nw_dust")
            dust.components.stackable:SetStackSize(amount)
            assert(inst.components.container:GiveItem(dust,1),"native stack merge")
            n=n-amount
        end
    end
    local function containerchecks(inst)
        local c=inst.components.container
        assert(c:GetNumSlots()==1 and c.infinitestacksize,"one native infinite slot")
        assert(inst.replica.container:IsInfiniteStackSize(),"infinite mode replicated")
        assert(inst.DynamicShadow==nil,"R3 baked shadow must not have DynamicShadow")
        local widget=c:GetWidget()
        assert(widget.animbank_upgraded=="ui_chest_1x1" and
            widget.animbuild_upgraded=="ui_chest_1x1","infinite UI needs upgraded bank/build")
        for _,name in ipairs({"redgem","nw_beast_core","nw_overlord_core","nw_blank","nw_dustbox"}) do
            local item=spawn(name)
            assert(not c:CanTakeItemInSlot(item,1),"accepted forbidden item: "..name)
            assert(not inst.replica.container:CanTakeItemInSlot(item,1),"client accepted: "..name)
        end
    end
    local function light(inst,radius)
        assert(inst.Light:IsEnabled(),"lit lamp light disabled")
        near(inst.Light:GetRadius(),radius,"light radius")
        near(inst.Light:GetIntensity(),storage.LIGHT.intensity,"light intensity")
        near(inst.Light:GetFalloff(),storage.LIGHT.falloff,"light falloff")
        local r,g,b=inst.Light:GetColour()
        near(r,storage.LIGHT.colour[1],"light red",1/255+.00001)
        near(g,storage.LIGHT.colour[2],"light green",1/255+.00001)
        near(b,storage.LIGHT.colour[3],"light blue",1/255+.00001)
    end
    local function switch(player,inst,on)
        inst.components.machine:StopCooldown()
        local action=on and ACTIONS.TURNON or ACTIONS.TURNOFF
        assert(hasaction(inst,"SCENE",player,action,true),"native right-click machine action missing")
        assert(action.fn(BufferedAction(player,inst,action)),"machine action failed")
    end
    local function grounddust(dx,dz)
        local total=0
        for _,e in ipairs(TheSim:FindEntities(x+dx,0,z+dz,6)) do
            if e.prefab=="nw_dust" and e.components.inventoryitem.owner==nil then
                total=total+e.components.stackable:StackSize()
                remember(e)
            end
        end
        return total
    end
    local function suite()
        TheWorld:PushEvent("ms_setphase","day")
        local player=spawn("wilson")
        local inv=player.components.inventory
        local box=spawn("nw_dustbox",1)
        local c=box.components.container
        wait();containerchecks(box);animation(box,"closed_empty")
        put(box,1);wait();animation(box,"closed_half")
        put(box,79);wait()
        assert(count(box)==80,"80-dust boundary")
        animation(box,"closed_half")
        put(box,1);wait();animation(box,"closed_full")
        local single=remember(c:RemoveItem(c:GetItemInSlot(1),false))
        wait();assert(count(box)==80 and single.components.stackable:StackSize()==1)
        animation(box,"closed_half")
        assert(c:GiveItem(single,1));wait();animation(box,"closed_full")
        assert(empty(box)==81);wait()
        assert(count(box)==0);animation(box,"closed_empty")

        put(box,12000);wait()
        assert(count(box)==12000,"count above 999 must be preserved")
        animation(box,"closed_full")
        assert(hasaction(box,"SCENE",player,ACTIONS.RUMMAGE,false),"ground open action")
        rummage(player,box,false)
        assert(c:IsOpenedBy(player) and box.AnimState:IsCurrentAnimation("open_full"),"open transition")
        animation(box,"opened_full")
        if box.OnEntityWake then box:OnEntityWake();animation(box,"opened_full") end
        c:TakeActiveItemFromAllOfSlot(1,player)
        local taken=assert(inv:GetActiveItem(),"native cursor withdrawal")
        assert(taken.components.stackable:StackSize()==40 and taken.components.stackable.maxsize==40,
            "withdrawal must restore normal dust stack size")
        assert(count(box)==11960,"withdrawal conservation")
        inv:RemoveItem(taken,true)
        assert(c:GiveItem(taken,1) and count(box)==12000,"return cursor stack")
        single=remember(c:RemoveItem(c:GetItemInSlot(1),false))
        assert(single.components.stackable:StackSize()==1 and count(box)==11999,"single withdrawal")
        assert(c:GiveItem(single,1) and count(box)==12000)
        c:Close(player)
        assert(box.AnimState:IsCurrentAnimation("close_full"),"close transition")
        animation(box,"closed_full")
        if box.OnEntityWake then box:OnEntityWake();animation(box,"closed_full") end

        assert(inv:GiveItem(box),"box must fit inventory");wait()
        assert(hasaction(box,"INVENTORY",player,ACTIONS.RUMMAGE,true),"inventory RUMMAGE missing")
        rummage(player,box,true);wait()
        assert(c:IsOpenedBy(player) and box.components.inventoryitem.owner==player,"inventory open dropped box")
        animation(box,"opened_full")
        assert(box.components.inventoryitem.imagename=="nw_dustbox_open_full","open inventory image")
        rummage(player,box,true);wait()
        assert(not c:IsOpen() and box.components.inventoryitem.owner==player,"inventory close ownership")
        inv:RemoveItem(box,true)
        local pack=spawn("backpack")
        assert(inv:Equip(pack),"equip native backpack")
        assert(pack.components.container:GiveItem(box,1),"box must fit backpack");wait()
        assert(box.components.inventoryitem:GetGrandOwner()==player and count(box)==12000)
        assert(not c:IsOpen(),"pickup closes box")
        rummage(player,box,true);wait()
        assert(c:IsOpenedBy(player) and box.components.inventoryitem.owner==pack and
            pack.components.container:GetItemInSlot(1)==box,"backpack RUMMAGE must not drop box")
        assert(pack.components.container:IsOpenedBy(player),"equipped backpack stays open")
        c:Close(player);wait()
        local restored=remember(assert(SpawnSaveRecord(pack:GetSaveRecord()),"restore nested backpack"))
        wait()
        local restoredbox=assert(restored.components.container:GetItemInSlot(1),"restored box")
        assert(restoredbox.prefab=="nw_dustbox" and count(restoredbox)==12000,"nested stack persistence")
        assert(restoredbox.components.container.infinitestacksize,"restored native unlimited mode")
        animation(restoredbox,"closed_full")
        pack.components.container:DropItemBySlot(1);wait()
        assert(box.components.inventoryitem.owner==nil and count(box)==12000,"drop keeps contents")
        local other=spawn("wilson",1)
        c:Open(player);c:Open(other);animation(box,"opened_full")
        c:Close(player);wait()
        assert(c:IsOpenedBy(other),"one opener closing must not close another")
        animation(box,"opened_full")
        c:Close(other);animation(box,"closed_full")
        c:Open(player);animation(box,"opened_full")
        c:MoveItemFromAllOfSlot(1,pack,player)
        local moved=pack.components.container:GetItemInSlot(1)
        assert(moved and moved.components.stackable:StackSize()==40,"shift-transfer normal stack")
        assert(count(box)==11960,"shift-transfer conservation")
        c:Close(player);animation(box,"closed_full")
        local recipe=assert(AllRecipes.nw_dustbox,"coffer recipe registered")
        assert(recipe.product=="nw_dustbox" and recipe.station_tag=="nw_workbench")
        local station=spawn("nw_workbench",2)
        local found=false
        for _,name in ipairs(station.components.craftingstation:GetItems()) do
            if name=="nw_dustbox" then found=true end
        end
        assert(found,"workbench must list coffer recipe")
        print("NW_ARCANE_STORAGE_STAGE: coffer actions, threshold, 12000 dust and nested save passed")

        local lamp=spawn("nw_emberlamp",2,1)
        local lc,machine=lamp.components.container,lamp.components.machine
        wait();containerchecks(lamp)
        print("NW_EMBERLAMP_GEOMETRY: capsule",lamp.Physics:GetRadius(),
            "interaction_radius",lamp:GetPhysicsRadius(),"placement_spacing",AllRecipes.nw_emberlamp.min_spacing)
        assert(not lamp.components.inventoryitem,"lamp is a fixed ground structure")
        animation(lamp,"off_empty")
        assert(lamp:HasTag("fueldepleted") and not machine:CanInteract(),"empty lamp interact guard")
        assert(not hasaction(lamp,"SCENE",player,ACTIONS.TURNON,true),"empty lamp exposes ignite")
        machine:TurnOn();wait()
        assert(not machine:IsOn() and not lamp.Light:IsEnabled(),"empty lamp opened through component")
        assert(hasaction(lamp,"SCENE",player,ACTIONS.RUMMAGE,false),"lamp left-click container action")
        rummage(player,lamp,false);assert(lc:IsOpenedBy(player),"ground lamp container did not open")
        put(lamp,80);wait();animation(lamp,"off_half")
        put(lamp,1);wait();animation(lamp,"off_full")
        lc:GetItemInSlot(1).components.stackable:SetStackSize(12000);wait()
        assert(count(lamp)==12000,"lamp native unlimited stack")
        lc:GetItemInSlot(1).components.stackable:SetStackSize(81);wait()
        assert(not hasaction(lamp,"SCENE",player,ACTIONS.TURNON,false),"left click must remain container interaction")
        switch(player,lamp,true)
        assert(lamp.AnimState:IsCurrentAnimation("ignite_full"),"ignite transition")
        single=remember(lc:RemoveItem(lc:GetItemInSlot(1),false))
        wait();animation(lamp,"burn_half");light(lamp,storage.LIGHT.half_radius)
        assert(lc:GiveItem(single,1));wait();animation(lamp,"burn_full")
        light(lamp,storage.LIGHT.full_radius)
        lamp:LongUpdate(57);wait()
        assert(count(lamp)==81,"dust consumed before a minute of light")
        lamp:LongUpdate(4);wait()
        assert(count(lamp)==80,"one minute must consume exactly one dust")
        animation(lamp,"burn_half");light(lamp,storage.LIGHT.half_radius)
        switch(player,lamp,false)
        assert(lamp.AnimState:IsCurrentAnimation("extinguish_half"),"extinguish transition")
        animation(lamp,"off_half")
        assert(not lamp.Light:IsEnabled(),"off lamp still lights world")
        local paused=lamp._nw_burnprogress
        lamp:LongUpdate(600);wait()
        assert(count(lamp)==80 and math.abs(lamp._nw_burnprogress-paused)<.001,"off lamp consumed fuel")
        switch(player,lamp,true);animation(lamp,"burn_half")
        lamp:LongUpdate(20);wait()
        local saved=lamp:GetSaveRecord()
        local progress=lamp._nw_burnprogress
        lamp:Remove()
        local restoredlamp=remember(assert(SpawnSaveRecord(saved),"restore burning lamp"))
        restoredlamp.entity:SetCanSleep(false);wait()
        assert(count(restoredlamp)==80 and restoredlamp.components.machine:IsOn(),"lit lamp save/load state")
        assert(restoredlamp._nw_burnprogress>=progress-.2 and
            restoredlamp._nw_burnprogress<progress+2,"partial minute lost or duplicated on load")
        animation(restoredlamp,"burn_half");light(restoredlamp,storage.LIGHT.half_radius)
        restoredlamp:LongUpdate(61-progress);wait()
        assert(count(restoredlamp)==79,"saved partial minute not applied once")
        assert(restoredlamp.OnEntitySleep and restoredlamp.OnEntityWake,"lamp sleep callbacks")
        restoredlamp:OnEntitySleep()
        restoredlamp:LongUpdate(120)
        restoredlamp:OnEntityWake();wait()
        assert(count(restoredlamp)==77,"sleep/LongUpdate consumed twice")
        assert(empty(restoredlamp)==77)
        wait();animation(restoredlamp,"off_empty")
        assert(not restoredlamp.components.machine:IsOn() and not restoredlamp.Light:IsEnabled(),"taking fuel must extinguish")

        local exhausted=spawn("nw_emberlamp",8,-8)
        put(exhausted,81);wait()
        local before=grounddust(8,-8)
        switch(player,exhausted,true)
        exhausted:LongUpdate(81*storage.DUST_SECONDS+1);wait()
        animation(exhausted,"off_empty")
        assert(count(exhausted)==0 and not exhausted.components.machine:IsOn() and
            not exhausted.Light:IsEnabled(),"last dust depletion")
        assert(grounddust(8,-8)==before,"consuming infinite stack spawned duplicated ground dust")
        put(exhausted,1);wait()
        assert(not exhausted.components.machine:IsOn(),"refill must not auto-ignite")

        local dismantled=spawn("nw_emberlamp",8,8)
        put(dismantled,97);wait()
        before=grounddust(8,8)
        local refund=0
        for _,prefab in ipairs(dismantled.components.lootdropper:GetRecipeLoot(AllRecipes.nw_emberlamp)) do
            if prefab=="nw_dust" then refund=refund+1 end
        end
        dismantled.components.workable:WorkedBy(player,dismantled.components.workable:GetWorkLeft())
        wait()
        assert(not dismantled:IsValid() and grounddust(8,8)-before==97+refund,"dismantling swallowed unconsumed dust")
        local lamprecipe=assert(AllRecipes.nw_emberlamp,"lamp recipe registered")
        assert(lamprecipe.product=="nw_emberlamp" and lamprecipe.level.SCIENCE==2,"lamp requires alchemy engine")
        local costs={}
        for _,ingredient in ipairs(lamprecipe.ingredients) do costs[ingredient.type]=ingredient.amount end
        assert(costs.cutstone==2 and costs.goldnugget==2 and costs.purplegem==1 and costs.nw_dust==4,"lamp recipe costs")
    end
    local thread=coroutine.create(suite)
    local function resume()
        local ok,delay=coroutine.resume(thread)
        if not ok then
            cleanup()
            error("NW_ARCANE_STORAGE: "..tostring(delay))
        elseif coroutine.status(thread)=="dead" then
            cleanup()
            print("NW_DUSTBOX_PASS: R3 coffer/lamp, native actions, 12000 dust, split/transfer, backpack save, thresholds, light, timed fuel, sleep/save, no duplication, dismantle, recipes")
        else
            TheWorld:DoTaskInTime(delay,resume)
        end
    end
    resume()
end
return M
