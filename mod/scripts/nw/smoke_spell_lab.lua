local Executor=require("nw/executor")
local Compiler=require("nw/compiler")
local function close(a,b) return math.abs(a-b)<.03 end
local M={}
function M.run(x,z,done)
    TheWorld:PushEvent("ms_setclocksegs",{day=16,dusk=0,night=0})
    -- Leave prior performance/combat fixtures behind. Pick a clear passable strip.
    local found
    for offset=-20,25 do
        for side=-10,10,2 do
            local ax,az=x+offset,z+side
            local ok=true
            for n=0,14 do if not TheWorld.Map:IsPassableAtPoint(ax+n,0,az) then ok=false;break end end
            if ok and #TheSim:FindEntities(ax+6,0,az,9,nil,{"INLIMBO","FX"},{"_combat","wall","tree","plant","boulder","pickable"})==0 then
                x,z=ax,az;found=true;break
            end
        end
        if found then break end
    end
    assert(found,"NW_LAB: no open test strip")
    local finish_persistent=require("nw/smoke_persistent_fields").start(x,z)
    local owner=SpawnPrefab("wilson");owner.Transform:SetPosition(x,0,z)
    local boxes,bench,wand=require("nw/spellkit").all(owner)
    assert(#boxes==#require("nw/spellkit").pages and wand.components.nw_wand.data.stats.capacity==12)
    local spells={}
    owner.components.inventory:Equip(wand)
    for _,box in ipairs(boxes) do
        local container=box.components.container
        for i=1,container:GetNumSlots() do
            local card=container:GetItemInSlot(i)
            if card then
                local id=card.spell_id
                assert(not spells[id]);spells[id]=true
                container:RemoveItem(card,true)
                owner.components.inventory:GiveItem(card)
                local w=wand.components.nw_wand
                assert(require("nw/editing").commit(owner,wand,1,card,w.data.config_revision),"NW_LAB: cannot install "..id)
                assert(w.data.cards[1].spell_id==id)
                assert(require("nw/editing").commit(owner,wand,1,nil,w.data.config_revision))
                local returned=owner.components.inventory:FindItem(function(e) return e.spell_id==id end)
                assert(returned);returned:Remove()
            end
        end
        box:Remove()
    end
    assert(GetTableSize(spells)==181)
    bench:Remove()
    local targets={}
    -- Wildlife can wander into the strip during this multi-minute suite.
    -- Restrict the synthetic caster to this stage's fixtures, then apply the
    -- original engine eligibility check to each one.
    local native_can_target=owner.components.combat.CanTarget
    owner.components.combat.CanTarget=function(combat,e)
        for _,fixture in ipairs(targets) do
            if fixture==e then return native_can_target(combat,e) end
        end
        return false
    end
    local function target(a,b)
        local e=SpawnPrefab("nw_target_dummy");e.Transform:SetPosition(x+a,0,z+b)
        targets[#targets+1]=e;return e
    end
    local function cast(ids,defer_copies,aim)
        local w=require("nw/generator").starter();w.stats.spread=0;w.stats.mana_max=600
        w.cards={}
        for i,id in ipairs(ids) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
        w.runtime=Compiler.initial(w.cards,w.stats,71)
        local plan=assert(Compiler.compile(w,nil,{defer_copies=defer_copies}))
        assert(Executor.execute(plan,owner,x,z,1,0,1.4,aim))
        return plan
    end
    local function compare_electric_hops(...)
        local ref=SpawnPrefab("nightstick")
        local losses={}
        for i,e in ipairs({...}) do
            local hp=e.components.health.currenthealth
            losses[i]=1000-hp
            ref.components.weapon:SetDamage(i==1 and 15 or 10)
            owner.components.combat:DoAttack(e,ref,ref,nil,nil,6,e:GetPosition())
            assert(close(hp-e.components.health.currenthealth,losses[i]),"NW_LAB: native electric mismatch")
        end
        ref:Remove()
        return losses
    end
    local stages={}
    stages[#stages+1]=function()
        local plan=cast({"orbit","long_life","long_life","long_life","spark"})
        local life=plan.blocks[1].projectiles[1].lifetime
        assert(life>9,"NW_LIFETIME: uncapped orbit compile")
        local bolt
        for _,e in ipairs(TheWorld._nw_projectiles.items) do
            if e:IsValid() and e._shot.owner==owner then bolt=e end
        end
        assert(bolt,"NW_LIFETIME: missing orbit body")
        owner:DoTaskInTime(8,function()
            assert(bolt:IsValid() and bolt._shot.remaining>0,"NW_LIFETIME: premature 7.5 second expiry")
        end)
        return life+.4,function()
            assert(not bolt:IsValid() and Executor.stats()==0,"NW_LIFETIME: extended expiry / budget release")
        end
    end
    stages[#stages+1]=function()
        local e=target(10,0)
        local plan=cast({"short_life","short_life","arrow_timer","explosion"})
        assert(plan.blocks[1].projectiles[1].lifetime<.5,"NW_LIFETIME: shortened timer carrier")
        return .8,function()
            assert(close(e.components.health.currenthealth,975) and Executor.stats()==0,"NW_LIFETIME: early expiry must fire the unopened timer once")
            print("NW_LIFETIME_PASS: extended orbit / shortened timer / budget cleanup")
        end
    end
    stages[#stages+1]=function()
        local e=target(10,0)
        cast({"short_life","short_life","arrow_hit","explosion"})
        return .8,function()
            assert(close(e.components.health.currenthealth,975) and Executor.stats()==0,"NW_END_PAYLOAD: untouched collision carrier expiry")
        end
    end
    for _,event in ipairs({"hit","timer"}) do
        stages[#stages+1]=function()
            local e=target(2,0)
            cast({"arrow_"..event,"explosion"})
            return 1.4,function()
                assert(close(e.components.health.currenthealth,953) and Executor.stats()==0,"NW_END_PAYLOAD: contact must emit exactly once "..event)
            end
        end
    end
    stages[#stages+1]=function()
        local e=target(2,0)
        local end_target=target(9.8,0)
        cast({"pierce_all","short_life","short_life","arrow_hit","explosion"})
        return .8,function()
            assert(close(e.components.health.currenthealth,953) and close(end_target.components.health.currenthealth,1000) and Executor.stats()==0,"NW_END_PAYLOAD: no expiry replay after piercing hit")
            print("NW_END_PAYLOAD_PASS: hit / timer expiry fallback, contact deduplication, piercing history")
        end
    end
    stages[#stages+1]=function()
        local e=target(13.5,1.5)
        cast({"short_life","arrow_timer","explosion"})
        return 1,function()
            assert(close(e.components.health.currenthealth,975) and Executor.stats()==0,"NW_END_PAYLOAD: already fired timer must not replay at expiry")
        end
    end
    for _,id in ipairs({"edge_chum","edge_shieldofterror"}) do
        stages[#stages+1]=function()
            local e=target(0,0)
            cast({"imprint_hit","short_life","short_life","short_life","short_life","short_life","short_life",id,"explosion"})
            return .6,function()
                assert(close(e.components.health.currenthealth,975) and Executor.stats()==0,"NW_END_PAYLOAD: special termination "..id)
            end
        end
    end
    stages[#stages+1]=function()
        local inside,outside=target(14,0),target(15.5,0)
        cast({"giant_shot","giant_shot","explosion"})
        assert(close(inside.components.health.currenthealth,975) and close(outside.components.health.currenthealth,1000),"NW_GIANT_ALL: 5x instant blast boundary")
        return .4,function() end
    end
    stages[#stages+1]=function()
        local inside,outside=target(7,2.7),target(7,3.3)
        cast({"giant_shot","giant_shot","thrust"})
        return .6,function()
            assert(close(inside.components.health.currenthealth,972.8) and close(outside.components.health.currenthealth,1000),"NW_GIANT_ALL: 5x melee width and reach")
        end
    end
    stages[#stages+1]=function()
        local inside,outside=target(8,0),target(9.5,0)
        cast({"giant_shot","giant_shot","sleep_crystal"})
        local crystal=owner._nw_crystals[#owner._nw_crystals]
        assert(close(crystal.Transform:GetScale(),5) and crystal._nw_stored.p.radius==9,"NW_GIANT_ALL: crystal size")
        local record=crystal:GetSaveRecord();crystal:Remove();crystal=SpawnSaveRecord(record);crystal._nw_owner=owner
        assert(close(crystal.Transform:GetScale(),5) and crystal._nw_stored.p.radius==9,"NW_GIANT_ALL: no double scale after save")
        crystal._nw_break()
        assert(close(inside.components.health.currenthealth,978) and close(outside.components.health.currenthealth,1000),"NW_GIANT_ALL: saved field blast")
        return .4,function() end
    end
    for _,key in ipairs({"yellowstaff","opalstaff"}) do
        stages[#stages+1]=function()
            cast({"giant_shot","giant_shot","edge_"..key})
            local star
            for _,e in ipairs(TheSim:FindEntities(x,0,z,.2,{"staffstar"})) do if e.prefab=="nw_edge_"..key then star=e end end
            assert(star and close(star.Transform:GetScale(),5) and star._nw_giant_star==5,"NW_GIANT_ALL: native star scale")
            owner.Physics:Teleport(x+15,0,z)
            local temperature=owner.components.temperature
            local before=temperature.current
            temperature:SetTemperature(key=="yellowstaff" and 0 or temperature.overheattemp)
            local delta=require("nw/giant_stars").heat(temperature)
            assert(key=="yellowstaff" and delta>80 or key=="opalstaff" and delta< -100,"NW_GIANT_ALL: thermal radius beyond native 10")
            assert(star:HasTag("HASHEATER") and star:HasTag("sanityaura"),"NW_GIANT_ALL: preserve native heat interactions")
            assert(star.components.sanityaura:GetAura(owner)>0,"NW_GIANT_ALL: extended sanity aura")
            owner.Physics:Teleport(x+25,0,z)
            assert(require("nw/giant_stars").aura(owner.components.sanity)>0,"NW_GIANT_ALL: aura beyond native search")
            owner.Physics:Teleport(x+15,0,z)
            temperature:OnUpdate(.1,false)
            local record=star:GetSaveRecord();star:Remove();star=SpawnSaveRecord(record)
            assert(star._nw_giant_star==5 and close(star.Transform:GetScale(),5),"NW_GIANT_ALL: saved native effects")
            return .4,function()
                assert(star.Light:GetRadius()>=55 and star.Light:GetRadius()<=60,"NW_GIANT_ALL: pulsing light radius")
                star:Remove();assert(not TheWorld._nw_giant_stars,"NW_GIANT_ALL: registry cleanup")
                temperature:SetTemperature(before);owner.Physics:Teleport(x,0,z)
                print("NW_GIANT_STAR_PASS: "..key.." scaled light / thermal / sanity / save")
            end
        end
    end
    for _,key in ipairs({"yellowstaff","opalstaff"}) do
        stages[#stages+1]=function()
            local id="edge_"..key
            local definition=require("nw/definitions").spells[id]
            local plan=cast({id})
            assert(plan.cooldown==definition.cooldown,"NW_STARS: cast cooldown")
            local star
            for _,e in ipairs(TheSim:FindEntities(x,0,z,.2,{"staffstar"})) do if e.prefab=="nw_"..id then star=e end end
            assert(star and not star._nw_motion and Executor.stats()==0,"NW_STARS: stationary placement / ledger")
            local ref=SpawnPrefab(definition.native_field);ref.Transform:SetPosition(x-20,0,z)
            assert(star.components.heater.heat==ref.components.heater.heat and star.components.sanityaura.aura==ref.components.sanityaura.aura
                and (star.components.cooker~=nil)==(ref.components.cooker~=nil),"NW_STARS: native environmental effects")
            assert(close(star.components.timer:GetTimeLeft("extinguish"),ref.components.timer:GetTimeLeft("extinguish")),"NW_STARS: native lifetime")
            ref:Remove();star:Remove()
            cast({"speed_up",id})
            for _,e in ipairs(TheSim:FindEntities(x,0,z,.2,{"staffstar"})) do if e.prefab=="nw_"..id then star=e end end
            assert(star and star._nw_motion,"NW_STARS: driven star")
            owner:DoTaskInTime(.5,function()
                assert(star:GetDistanceSqToPoint(x,0,z)>.5,"NW_STARS: native physics movement")
                local remaining=star.components.timer:GetTimeLeft("extinguish")
                local record=star:GetSaveRecord();star:Remove();star=SpawnSaveRecord(record)
                assert(star._nw_star.p.speed==2 and close(star.components.timer:GetTimeLeft("extinguish"),remaining),"NW_STARS: saved motion and remaining life")
                star._nw_owner=owner
                star.components.timer:StopTimer("extinguish");star.components.timer:StartTimer("extinguish",.2)
            end)
            return 2,function()
                assert(not star:IsValid(),"NW_STARS: native timed extinction")
                print("NW_STAR_PASS: "..key.." native effects / motion / saved timer / expiry")
            end
        end
    end
    stages[#stages+1]=function()
        local e=target(4,.72)
        cast({"arrow"})
        owner:DoTaskInTime(1.4,function()
            assert(close(e.components.health.currenthealth,1000),"NW_GIANT: baseline must miss")
            cast({"giant_shot","arrow"})
        end)
        return 2.8,function() assert(close(e.components.health.currenthealth,978),"NW_GIANT: expanded collision") end
    end
    stages[#stages+1]=function()
        local e=target(3,4)
        local tornado=SpawnPrefab("tornado");tornado.Transform:SetPosition(x+3,0,z)
        tornado:StopBrain("nw_giant_test");tornado._nw_giant=2.5
        tornado.WINDSTAFF_CASTER=owner;tornado.WINDSTAFF_CASTER_ISPLAYER=true
        tornado.sg:GoToState("idle")
        assert(e.components.health.currenthealth<1000,"NW_GIANT: native tornado annulus")
        tornado:Remove()
        return .1,function() end
    end
    stages[#stages+1]=function()
        local e=target(3,4)
        local p=cast({"giant_shot","edge_trident"}).blocks[1].projectiles[1]
        -- Exercise the same finish path without waiting for the full outgoing flight.
        require("nw/engraved_impact").finish({p=p,owner=owner},x+3,z)
        assert(close(e.components.health.currenthealth,915),"NW_GIANT: trident radius / damage")
        return 1.8,function() end
    end
    local function last_shot(key)
        local items=TheWorld._nw_projectiles.items
        for i=#items,1,-1 do
            local e=items[i]
            if e:IsValid() and e._shot.owner==owner and e._shot.p.engraving==key then return e end
        end
        error("NW_ENGRAVING: missing shot "..key)
    end
    stages[#stages+1]=function()
        local pond=SpawnPrefab("pond")
        local px=x+3
        pond.Transform:SetPosition(px,0,z);targets[#targets+1]=pond
        local stock=pond.components.fishable.fishleft
        local caught
        local function collect(_,data) caught=data.fish end
        owner:ListenForEvent("fishingcollect",collect)
        cast({"edge_fishingrod"})
        return .8,function()
            assert(pond.components.fishable.fishleft==stock-1,"NW_ENGRAVING: pond settlement")
            assert(caught and caught:IsValid(),"NW_ENGRAVING: no pond fish")
            local fx,_,fz=caught.Transform:GetWorldPosition()
            local radius=pond:GetPhysicsRadius()+caught:GetPhysicsRadius(.1)+.15
            assert(math.abs(fx-(px-radius))<.1 and math.abs(fz-z)<.1,"NW_ENGRAVING: fish did not land on near bank")
            owner:RemoveEventCallback("fishingcollect",collect);caught:Remove()
        end
    end
    stages[#stages+1]=function()
        local dummy=target(4,0)
        cast({"edge_voidcloth_boomerang"})
        local bolt=last_shot("voidcloth_boomerang")._shot.native
        owner:DoTaskInTime(.1,function()
            assert(bolt:IsValid() and bolt.Physics:GetMotorVel()>0,"NW_ENGRAVING: native outgoing motor")
            assert(bolt.scale>=.4 and bolt.scale<=1,"NW_ENGRAVING: oversized boomerang")
        end)
        return 1.6,function()
            assert(dummy.components.health.currenthealth<990,"NW_ENGRAVING: growing native boomerang hp "..dummy.components.health.currenthealth)
        end
    end
    stages[#stages+1]=function()
        local dummy=target(3,0)
        cast({"edge_dumbbell_bluegem"})
        cast({"edge_farm_hoe"})
        local bouncing_hoe=last_shot("farm_hoe")
        owner:DoTaskInTime(.9,function()
            assert(bouncing_hoe:IsValid(),"NW_HOE: non-farm landing must allow another hop")
        end)
        cast({"edge_minifan"})
        cast({"edge_shieldofterror"})
        return 4.8,function()
            assert(dummy.components.health.currenthealth<995,"NW_ENGRAVING: airborne hit")
            assert(owner._nw_shields and owner._nw_shields[1]._shot.armor==50,"NW_ENGRAVING: orbit shield")
            local combat=dummy.components.combat
            combat.temppos=owner:GetPosition();combat.temprange=3
            assert(close(owner.components.inventory:ApplyDamage(65,dummy),15) and not owner._nw_shields,"NW_ENGRAVING: before-armour shield accounting")
            combat.temppos=nil;combat.temprange=nil
            print("NW_ENGRAVING_PASS: pond settlement, native boomerang, ballistic landing and shield")
        end
    end
    stages[#stages+1]=function()
        local dummy=target(3,0)
        cast({"edge_chum"},nil,{x=x+8,z=z})
        local e=last_shot("chum")
        local landed
        e:ListenForEvent("onremove",function() landed={e.Transform:GetWorldPosition()} end)
        owner:DoTaskInTime(.2,function()
            assert(e:IsValid() and select(2,e.Transform:GetWorldPosition())>.05,"NW_CHUM: no airborne arc")
        end)
        return 1.3,function()
            assert(landed and math.abs(landed[1]-(x+8))<1 and math.abs(landed[3]-z)<.1,"NW_CHUM: missed aimed landing")
            assert(dummy.components.health.currenthealth==1000,"NW_CHUM: airborne contact damage")
        end
    end
    stages[#stages+1]=function()
        local plants={}
        for _,v in ipairs({{2,.6},{4,-.6},{6,0}}) do
            local grass=SpawnPrefab("grass");grass.Transform:SetPosition(x+v[1],0,z+v[2])
            grass.components.pickable:Regen();plants[#plants+1]=grass;targets[#targets+1]=grass
        end
        cast({"edge_voidcloth_scythe"})
        return 1.8,function()
            for _,e in ipairs(plants) do assert(not e.components.pickable:CanBePicked(),"NW_SCYTHE: missed a plant in sweep") end
        end
    end
    stages[#stages+1]=function()
        local map=TheWorld.Map
        local cx=map:GetTileCenterPoint(x+8,0,z)
        local tx,tz=map:GetTileCoordsAtPoint(cx,0,z)
        local old=map:GetTile(tx,tz)
        map:SetTile(tx,tz,WORLD_TILES.FARMING_SOIL)
        cast({"edge_farm_hoe"},nil,{x=cx,z=z})
        local hoe=last_shot("farm_hoe")
        return 1.5,function()
            local soil=TheSim:FindEntities(cx,0,z,1.2,{"soil"})
            map:SetTile(tx,tz,old)
            assert(not hoe:IsValid() and #soil==1,"NW_HOE: first successful landing must till and finish")
            for _,e in ipairs(soil) do e:Remove() end
            print("NW_ENGRAVING_RETEST_PASS: bank-side fish, native motor/scale, aimed chum, continuous harvest and aimed tilling")
        end
    end
    stages[#stages+1]=function()
        local a,b=target(4,0),target(6,1)
        cast({"edge_staff_lunarplant"})
        return 2.2,function()
            assert(a.components.health.currenthealth<1000 and b.components.health.currenthealth<1000,"NW_ENGRAVING: native brightshade rebound")
        end
    end
    stages[#stages+1]=function()
        local a=target(3,0)
        cast({"edge_trident"})
        return .65,function()
            assert(a.components.health.currenthealth<1000,"NW_ENGRAVING: land waterspout")
        end
    end
    stages[#stages+1]=function()
        local a=target(5,0)
        cast({"edge_icestaff"})
        return .5,function()
            assert(a.components.freezable.coldness>0 or a.components.freezable:IsFrozen(),"NW_ENGRAVING: native ice impact")
        end
    end
    stages[#stages+1]=function()
        local px=x+6
        cast({"edge_staff_tornado"},false,Vector3(px,0,z))
        local shot=TheWorld._nw_projectiles.items[#TheWorld._nw_projectiles.items]
        local tornado=shot._shot.native
        targets[#targets+1]=tornado
        return 1,function()
            local center=tornado.components.knownlocations:GetLocation("target")
            assert(not shot:IsValid() and center and math.abs(center.x-px)<.05 and math.abs(center.z-z)<.05,"NW_ENGRAVING: tornado handoff")
        end
    end
    stages[#stages+1]=function()
        local shock=SpawnPrefab("nw_ground_shock_fx")
        shock.Transform:SetPosition(x,0,z)
        local weapon=SpawnPrefab("nw_edge_hammer_fx")
        assert(weapon.AnimState:IsCurrentAnimation("atk"))
        weapon:Remove()
        local stab=SpawnPrefab("nw_thrust_fx")
        assert(stab.AnimState:IsCurrentAnimation("spearjab"))
        stab:Remove()
        cast({"bog_whip"})
        local arm=TheSim:FindEntities(x,0,z,1,{"FX"})
        local emerged=false
        for _,e in ipairs(arm) do
            if e.prefab=="nw_bog_whip" then emerged=e.AnimState:IsCurrentAnimation("atk_pre") end
        end
        assert(emerged,"NW_VISUAL: native tentacle emerge")
        return 2.2,function()
            assert(not shock:IsValid(),"NW_VISUAL: ground shock did not finish")
        end
    end
    stages[#stages+1]=function()
        local ally,enemy=target(2,0),target(4,0)
        ally:AddComponent("follower");ally.components.follower:SetLeader(owner)
        ally.components.health:SetPercent(.5);enemy.components.health:SetPercent(.5)
        cast({"heal_bolt"})
        return .6,function()
            assert(close(ally.components.health.currenthealth,500) and close(enemy.components.health.currenthealth,508),"NW_HEAL_BOLT: ordinary shot")
        end
    end
    stages[#stages+1]=function()
        local ally=target(3,0)
        ally:AddComponent("follower");ally.components.follower:SetLeader(owner)
        ally.components.health:SetPercent(.5)
        cast({"target_friendly","homing","heal_bolt"})
        return .6,function()
            assert(close(ally.components.health.currenthealth,508),"NW_HEAL_BOLT: selected follower")
            print("NW_HEAL_BOLT_PASS: enemy by default, explicit follower healing")
        end
    end
    stages[#stages+1]=function()
        cast({"sleep_crystal"})
        local near=owner._nw_crystals[1]
        cast({"sleep_crystal"})
        local far=owner._nw_crystals[2]
        near.Physics:Teleport(x+2,0,z);far.Physics:Teleport(x+9,0,z)
        cast({"detonate"},false,Vector3(x+9,0,z))
        assert(near:IsValid() and not far:IsValid(),"NW_REVIEW: detonator ignored aim")
        near._nw_break()
        return .4,function() end
    end
    stages[#stages+1]=function()
        local wall=SpawnPrefab("wall_stone")
        wall.Transform:SetPosition(x+2,0,z);targets[#targets+1]=wall
        local before=wall.components.health.currenthealth
        cast({"target_building","arrow"})
        return 1.4,function()
            assert(wall:IsValid() and wall.components.health.currenthealth<before,"NW_REVIEW: wall ignored directed damage")
        end
    end
    stages[#stages+1]=function()
        local tree=SpawnPrefab("evergreen_normal")
        tree.entity:SetCanSleep(false)
        tree.Transform:SetPosition(x+4.5,0,z+.15);targets[#targets+1]=tree
        local lit=false
        tree:ListenForEvent("onignite",function() lit=true end)
        cast({"target_nature","homing","fire"})
        return 1,function() assert(lit,"NW_REVIEW: homing fire missed tree") end
    end
    stages[#stages+1]=function()
        local effects=require("nw/spell_effects")
        local wet=owner.components.moisture
        wet:SetPercent(.5)
        local before=wet:GetMoisture()
        effects.direct(owner,owner,{damage=10,flags={targets={self=true}},burn_damage=4,burn_ticks=3},1,0)
        assert(close(wet:GetMoisture(),before-2) and not owner._nw_burn and not owner.components.burnable:IsBurning(),
            "NW_REVIEW: wet fire ignited or wrong evaporation")
        wet:SetPercent(0)
        local e=target(3,0)
        local cold=0
        local ice=e.components.freezable
        local add=ice.AddColdness
        ice.AddColdness=function(comp,n,...) cold=cold+n;return add(comp,n,...) end
        cast({"chill_touch","repeat_3","arrow"})
        return 1.5,function()
            assert(close(cold,.6),"NW_REVIEW: lost repeated frost enchantment")
            print("NW_REVIEW_PASS: structure damage, homing nature ignition, moisture evaporation and repeated chill")
        end
    end
    stages[#stages+1]=function()
        local limits=require("nw/spell_limits")
        local oldcast,oldplants=limits.cast,limits.sentries
        limits.cast,limits.sentries=0,0
        local plan=cast({"repeat_3","repeat_3","scatter"},true)
        assert(plan.projectile_count==27 and Executor.stats()==27,"NW_LIMIT: 27 attack entities")
        for i=1,3 do cast({"spore_sentry"}) end
        local plants=owner._nw_sentries
        assert(#plants==3 and plants[1]:IsValid(),"NW_LIMIT: default sentries capped")
        while #plants>0 do plants[1]:Remove() end
        limits.sentries=2
        for i=1,2 do cast({"spore_sentry"}) end
        local first=plants[1]
        cast({"spore_sentry"})
        assert(#plants==2 and not first:IsValid(),"NW_LIMIT: configured sentry cap ignored")
        while #plants>0 do plants[1]:Remove() end
        limits.cast,limits.sentries=oldcast,oldplants
        return 2,function() print("NW_LIMIT_PASS: 27 real projectiles, unlimited and capped sentries") end
    end
    stages[#stages+1]=function()
        local fields=require("nw/expanded_fields")
        local configured=fields.crystal_limit
        for _,cap in ipairs({0,30}) do
            fields.crystal_limit=cap
            for i=1,30 do cast({i%2==0 and "sleep_crystal" or "crystal_mine"}) end
            local list=owner._nw_crystals
            assert(#list==30,"NW_CRYSTAL: fewer than 30 live crystals")
            local first,second=list[1],list[2]
            cast({"sleep_crystal"})
            assert(#list==(cap==0 and 31 or 30) and first:IsValid()==(cap==0) and second:IsValid())
            cast({"detonate"})
            assert(#list==0,"NW_CRYSTAL: partial cleanup")
        end
        fields.crystal_limit=configured
        cast({"spore_sentry"})
        local plant=owner._nw_sentries[1]
        local hound=SpawnPrefab("hound")
        hound.Physics:Teleport(x+.5,0,z)
        assert(hound.components.combat:CanTarget(plant) and plant.components.health.maxhealth==60)
        hound.components.combat:SetTarget(plant)
        hound.components.combat:DoAttack(plant)
        assert(plant.components.health.currenthealth<60,"NW_SENTRY: native hound attack missed")
        plant.components.health:Kill()
        assert(not plant:IsValid() and #owner._nw_sentries==0)
        hound:Remove()
        return .35,function() print("NW_CRYSTAL_SENTRY_PASS: 30/31 crystals + detonation; hound hit + death cleanup") end
    end
    stages[#stages+1]=function()
        local distant=target(4,0)
        cast({"speed_up","delay_seal","explosion"})
        return 1.1,function()
            assert(close(distant.components.health.currenthealth,975),"NW_FIELD: payload used original position")
        end
    end
    stages[#stages+1]=function()
        cast({"homing","sleep_crystal"})
        local crystal=owner._nw_crystals[1]
        owner:DoTaskInTime(.3,function()
            assert(crystal:GetDistanceSqToPoint(x,0,z)<.04,"NW_FIELD: homing moved without target")
            target(2,3)
        end)
        return 1.55,function()
            local ex,_,ez=crystal.Transform:GetWorldPosition()
            assert(ez>z+1.5 and ex>x+.6,"NW_FIELD: no curved pursuit")
            local e=targets[1]
            crystal._nw_break()
            assert(close(e.components.health.currenthealth,978),"NW_FIELD: blast hp="..e.components.health.currenthealth.." distance="..math.sqrt(e:GetDistanceSqToPoint(ex,0,ez)))
            print("NW_FIELD_PASS: moving payload, dormant homing, curved pursuit and blast at live position")
        end
    end
    stages[#stages+1]=function()
        local trees={}
        for j,dist in ipairs({.55,-.65,2.55}) do
            local tree=SpawnPrefab("evergreen_normal")
            tree.Transform:SetPosition(x+dist,0,z)
            tree.components.workable:SetWorkLeft(8)
            trees[j]=tree;targets[#targets+1]=tree
        end
        for _=1,4 do cast({"whirl"}) end
        return .8,function()
            for j,e in ipairs(trees) do assert(e.components.workable:GetWorkLeft()==(j<3 and 5 or 8),"NW_WORK: 0.75 AoE") end
        end
    end
    stages[#stages+1]=function()
        local grass=SpawnPrefab("grass");grass.Transform:SetPosition(x+.6,0,z)
        targets[#targets+1]=grass
        cast({"target_nature","edge_voidcloth_scythe"})

        return 1.8,function()
            assert(not grass.components.pickable:CanBePicked(),"NW_WORK: directional scythe harvest")
            print("NW_WORK_PASS: range, 75% work, directional harvesting")
        end
    end
    stages[#stages+1]=function()
        local friend=SpawnPrefab("wilson")
        friend.Transform:SetPosition(x+2,0,z);targets[#targets+1]=friend
        local hp=friend.components.health.currenthealth
        local mine=owner.components.health.currenthealth
        cast({"target_players_other","arrow"})
        cast({"target_self","reverse_path","arrow"})
        owner:DoTaskInTime(.2,function()
            assert(close(owner.components.health.currenthealth,mine),"NW_SCOPE: immediate self hit")
        end)
        return 1.5,function()
            assert(close(owner.components.health.currenthealth,mine-22),"NW_SCOPE: self")
            assert(close(friend.components.health.currenthealth,hp-22),"NW_SCOPE: explicit player target")
            print("NW_SCOPE_PASS: self and other-player damage; PvP",TheNet:GetPVPEnabled())
        end
    end
    local wave={}
    local function arsenal_wave(ids)
        stages[#stages+1]=function()
            target(1,0)
            for _,id in ipairs(ids) do cast({id}) end
            return .85,function() end
        end
    end
    for _,c in ipairs(require("nw/arsenal").cards) do
        if c.kind=="melee" and not require("nw/engraved_spells").retired[c.id] or require("nw/arsenal").notes[c.id] then
            wave[#wave+1]=c.id
            if #wave==8 then arsenal_wave(wave);wave={} end
        end
    end
    if #wave>0 then arsenal_wave(wave) end
    stages[#stages+1]=function()
        local attacker=target(3,0)
        local hits=0
        owner:ListenForEvent("attacked",function(_,data) if data.attacker==attacker then hits=hits+1 end end)
        cast({"guard_ring"})
        local dart=SpawnPrefab("blowdart_walrus")
        dart.Transform:SetPosition(x+1.7,0,z)
        dart.components.projectile:Throw(attacker,owner)
        return 2.3,function()
            assert(not dart:IsValid() and hits==0,string.format("NW_GUARD: dart valid=%s, hits=%d",tostring(dart:IsValid()),hits))
        end
    end
    stages[#stages+1]=function()
        local sample=require("nw/spellkit").rollwand(4,1062,owner)
        -- Frozen v2 save fixture: new generator versions must not reroll old stats.
        local legacy=sample.components.nw_wand.data
        legacy.generator_version=2;legacy.generation_budget=64;legacy.budget_remaining=0
        legacy.always_cast=nil
        legacy.stats={capacity=10,draw_count=6,mana_max=50,mana_regen=80,cast_delay=1.6,recharge=.6,
            spread=0,shuffle=false,sanity_conversion=20}
        legacy.cards={}
        for i=1,10 do legacy.cards[i]=require("nw/wand_factory").card("spark","legacy-test") end
        legacy.runtime=require("nw/compiler").initial(legacy.cards,legacy.stats,1062)
        legacy.config_revision=legacy.config_revision+1
        sample.components.nw_wand:Sync()
        local record=sample:GetSaveRecord()
        sample:Remove()
        local restored=SpawnSaveRecord(record)
        local cmp=restored.components.nw_wand
        local s=cmp.data.stats
        assert(cmp.data.generator_version==2 and cmp.data.generation_budget==64 and s.capacity==10
            and s.draw_count==6 and s.mana_max==50 and s.mana_regen==80
            and s.cast_delay==1.6 and s.recharge==.6,"NW_ROLL: saved stats or seed mismatch")
        owner.components.inventory:Equip(restored)
        local ready,_,plan=cmp:CanCast(owner)
        assert(ready and plan.projectile_count==6 and cmp:Cast(owner,Vector3(x+8,0,z),plan))
        assert(Executor.stats()==6 and restored._nw_mana:value()==20 and restored._nw_maxmana:value()==50
            and require("nw/hover_data").decode(restored._nw_stats:value()).draw_count==6,"NW_ROLL: launch or replication failed")
        return 1.8,function()
            assert(restored._nw_mana:value()==50 and restored._nw_cancast:value(),"NW_ROLL: recharge failed")
            restored:Remove()
            owner.components.inventory:Equip(wand)
            print("NW_ROLL_PASS: saved v2 wand, six real shots, faster-than-cap regen, short recharge")
        end
    end
    for _,id in ipairs({"fire","frost"}) do
        local element=id
        stages[#stages+1]=function()
            local e=target(4,1.4)
            local d=wand.components.nw_wand.data
            for i=1,d.stats.capacity do d.cards[i]=false end
            d.cards[1]=require("nw/wand_factory").card(element,"debug")
            d.stats.spread=0;d.config_revision=d.config_revision+1
            d.runtime=Compiler.initial(d.cards,d.stats,10)
            wand.components.nw_wand:Sync()
            local act=BufferedAction(owner,e,ACTIONS.NW_CAST,wand,Vector3(x+4,0,z-2))
            local native=require("nw/cast_action")
            native.prepare(act)
            assert(native.perform(act),"NW_LAB: selected entity cast")
            return .55,function()
                assert(e.components.health.currenthealth<=991,"NW_LAB: body click missed "..element)
            end
        end
    end
    stages[#stages+1]=function()
        local behind,beside=target(5,0),target(2,.95)
        local wall=SpawnPrefab("wall_stone")
        wall.Transform:SetPosition(x+3,0,z);targets[#targets+1]=wall
        local hp=wall.components.health.currenthealth
        cast({"arrow_hit","whirl"})
        cast({"phase_wall","bounce","arrow"})
        return 1,function()
            assert(wall.components.health.currenthealth==hp and close(behind.components.health.currenthealth,978)
                and close(beside.components.health.currenthealth,978.24),"NW_LAB: phase precedence / wall payload / wall HP")
        end
    end
    stages[#stages+1]=function()
        local perf=require("nw/perf")
        perf.begin()
        for i=1,4 do cast({"recharge_down","repeat_3","sine","homing","arrow_timer","whirl"}) end
        return 1.5,function()
            local s=perf.finish()
            print("NW_PERF_CURVE_TIMER_MELEE:",s.steps,"flight steps",s.queries,"sweep queries",s.effect_queries,"homing/melee queries",s.melee,"melee payloads")
            assert(Executor.stats()==0 and s.melee==12 and s.queries<s.steps and s.effect_queries>0 and s.effect_queries<s.steps/2,
                "NW_LAB: mixed cast query sharing or reservation cleanup")
        end
    end
    stages[#stages+1]=function()
        local a,b=target(6,0),target(6.8,.25)
        local plan=cast({"repeat_2","arrow_hit","slash"})
        assert(plan.projectile_count==4 and plan.mana_spent==66)
        return 1,function()
            assert(close(a.components.health.currenthealth,847.2) and close(b.components.health.currenthealth,891.2),
                "NW_LAB: both copied carriers must release their own melee payload")
        end
    end
    stages[#stages+1]=function()
        local a,b,c=target(6,0),target(6.8,.25),target(0,1.6)
        cast({"arrow_hit","slash"})
        return 1,function()
            assert(close(a.components.health.currenthealth,923.6) and close(b.components.health.currenthealth,945.6)
                and c.components.health.currenthealth==1000,"NW_LAB: remote slash origin/area")
        end
    end
    stages[#stages+1]=function()
        local a=target(12.5,.9)
        cast({"imprint_timer","arrow","whirl"})
        -- The 1.2s carrier can expire on the next physics tick after the scheduler fires.
        return 1.2+2*FRAMES,function() assert(close(a.components.health.currenthealth,978.24),"NW_LAB: timer whirl") end
    end
    stages[#stages+1]=function()
        local line={}
        for i=1,4 do line[i]=target(2*i,0) end
        cast({"pierce","arrow"});cast({"pierce_all","arrow"})
        return 1.5,function()
            for i,e in ipairs(line) do assert(close(e.components.health.currenthealth,i==4 and 978 or 956),"NW_LAB: pierce "..i) end
        end
    end
    stages[#stages+1]=function()
        local row={target(2,0),target(5,0),target(8,0)}
        cast({"pierce","arrow_hit","double","explosion","whirl"})
        return 1.5,function()
            -- The blast from the next hit is within 3 of the previous target.
            for i,e in ipairs(row) do
                local hp=1000-22-25-21.76-(i<3 and 25 or 0)
                assert(close(e.components.health.currenthealth,hp),"NW_LAB: per-contact blast or payload "..i)
            end
        end
    end
    stages[#stages+1]=function()
        local a,b,c,d,e=target(2,0),target(7.9,0),target(12,0),target(12,2),target(12,3)
        cast({"chain"})
        return .65,function()
            compare_electric_hops(a,b,c,d)
            assert(e.components.health.currenthealth==1000,"NW_LAB: fifth arc target was attacked")
        end
    end
    stages[#stages+1]=function()
        local a=target(12.5,1.5)
        cast({"arrow_timer","chain"})
        return 1.4,function()
            compare_electric_hops(a)
        end
    end
    stages[#stages+1]=function()
        local b,c=target(2,0),target(7,0)
        b:AddTag("moistureimmunity");c:AddTag("wet")
        owner.components.health:SetPercent(.5)
        local before=owner.components.health.currenthealth
        cast({"leech","chain"})
        return .65,function()
            -- Compare with the game's own electric weapon under identical conditions.
            local losses=compare_electric_hops(b,c)
            assert(losses[2]/10>losses[1]/15,"NW_LAB: wet arc")
            assert(close(owner.components.health.currenthealth-before,(losses[1]+losses[2])*.05),"NW_LAB: actual loss leech")
            print("NW_NATIVE_ELECTRIC",losses[1],losses[2])
        end
    end
    stages[#stages+1]=function()
        local b,c=target(2,0),target(7,0)
        b.entity:AddDynamicShadow();b:AddComponent("inventory")
        local umbrella,hat=SpawnPrefab("umbrella"),SpawnPrefab("strawhat")
        targets[#targets+1]=umbrella;targets[#targets+1]=hat
        b.components.inventory:Equip(umbrella);b.components.inventory:Equip(hat)
        assert(b.components.inventory:IsWaterproof() and not b.components.inventory:IsInsulated(),"NW_LAB: waterproof gear")
        c.entity:AddDynamicShadow();c:AddComponent("inventory")
        local eyebrella=SpawnPrefab("eyebrellahat");targets[#targets+1]=eyebrella
        c.components.inventory:Equip(eyebrella)
        assert(c.components.inventory:IsWaterproof() and c.components.inventory:IsInsulated(),"NW_LAB: insulated gear")
        b:AddTag("wet");c:AddTag("wet")
        local attacked=0
        b:ListenForEvent("attacked",function() attacked=attacked+1 end)
        cast({"chain"})
        return .65,function()
            assert(attacked==1,"NW_LAB: waterproof arc")
            local losses=compare_electric_hops(b,c)
            print("NW_ELECTRIC_GEAR_PARITY",losses[1],losses[2])
        end
    end
    stages[#stages+1]=function()
        local a=target(2,0)
        local goat=SpawnPrefab("lightninggoat");targets[#targets+1]=goat
        goat.Transform:SetPosition(x+7,0,z);goat.entity:SetCanSleep(false);goat:StopBrain("nw_test")
        assert(not goat:HasTag("charged"))
        cast({"arrow_hit","chain"})
        return .65,function()
            assert(a.components.health.currenthealth<978 and goat:HasTag("charged"),"NW_LAB: native goat charge")
        end
    end
    stages[#stages+1]=function()
        local a=target(3,0)
        a:RemoveComponent("burnable") -- isolate our exact six ticks from native environmental fire
        cast({"double","fire","fire"})
        return 3.6,function() assert(close(a.components.health.currenthealth,960.4),"NW_LAB: independent fire stacks") end
    end
    stages[#stages+1]=function()
        local a=target(3,0)
        a.components.freezable:SetResistance(1)
        cast({"triple","frost","frost","frost"})
        return .5,function() assert(a.components.freezable:IsFrozen(),"NW_LAB: native freezing") end
    end
    stages[#stages+1]=function()
        local a=target(3,0);a:AddComponent("follower");a.components.follower:SetLeader(owner)
        a.components.health:SetPercent(.5)
        cast({"heal_ally","spark"})
        return .5,function() assert(close(a.components.health.currenthealth,508),"NW_LAB: friendly healing") end
    end
    stages[#stages+1]=function()
        cast({"orbit","light","pierce_all","spark"})
        cast({"homing","sine","spiral","arrow_timer","thrust"})
        return 4.6,function()
            assert(Executor.stats()==0,"NW_LAB: curved/timed cleanup")
            assert(owner._nw_lights and owner._nw_lights[1]:IsValid(),"NW_LAB: residual light")
        end
    end
    stages[#stages+1]=function()
        local a,b=target(3,0),target(3,2.6)
        cast({"arrow_hit","explosion"})
        return .5,function()
            assert(close(a.components.health.currenthealth,953) and close(b.components.health.currenthealth,975),"NW_LAB: blast")
        end
    end
    stages[#stages+1]=function()
        local inside,outside=target(3-0.02,0),target(0,3+0.02)
        cast({"explosion"})
        return .4,function()
            assert(close(inside.components.health.currenthealth,975) and close(outside.components.health.currenthealth,1000),
                "NW_LAB: blast boundary 2.98 / 3.02")
        end
    end
    stages[#stages+1]=function()
        local a=target(-2,0)
        local wall=SpawnPrefab("wall_stone")
        wall.Transform:SetPosition(x+3,0,z);targets[#targets+1]=wall
        cast({"bounce","arrow"})
        return 1.5,function()
            assert(close(a.components.health.currenthealth,978),"NW_LAB: reflected shot")
        end
    end
    stages[#stages+1]=function()
        local a=target(4,0)
        cast({"fire"})
        return .6,function()
            assert(a.components.burnable:IsBurning() and a._nw_burn,"NW_LAB: native fire")
            a.components.burnable:Extinguish()
            assert(not a._nw_burn,"NW_LAB: extinguish cancels delayed fire")
        end
    end
    stages[#stages+1]=function()
        local e=target(3,0)
        cast({"scatter_hit","whirl"})
        return 1,function()
            assert(close(e.components.health.currenthealth,1000-27-3*21.76),"NW_LAB: payload per pellet")
        end
    end
    for _,case in ipairs({{{"orbit","spark"},1},{{"orbit","pierce","spark"},3}}) do
        local cards,hits=case[1],case[2]
        stages[#stages+1]=function()
            local e=target(0,2)
            cast(cards)
            return 4.2,function()
                assert(close(e.components.health.currenthealth,1000-18*hits),"NW_LAB: orbit penetration count "..hits)
            end
        end
    end
    stages[#stages+1]=function()
        local e=target(4,0)
        local burnable=e.components.burnable
        local extinguish,elapsed_ms=burnable.Extinguish,nil
        burnable.Extinguish=function(component,...)
            local start=GetTimeReal()
            local result=extinguish(component,...)
            elapsed_ms=GetTimeReal()-start
            return result
        end
        cast({"triple","fire","fire","fire"})
        local ended=0
        e:ListenForEvent("onextinguish",function() ended=ended+1 end)
        return 7,function()
            assert(ended==1 and elapsed_ms and not e._nw_burn and not e.components.burnable:IsBurning()
                and #e.components.burnable.fxchildren==0,"NW_LAB: natural fire cleanup")
            print("NW_NATURAL_EXTINGUISH_MS",elapsed_ms)
        end
    end
    stages[#stages+1]=function()
        local spider=SpawnPrefab("spider")
        spider.Transform:SetPosition(x+4,0,z)
        spider.entity:SetCanSleep(false);spider:StopBrain("nw_test")
        targets[#targets+1]=spider
        cast({"knockback","arrow"})
        return .7,function()
            local tx,_,tz=spider.Transform:GetWorldPosition()
            print("NW_LAB_KNOCK",tx-x-4,tz-z,spider.components.health.currenthealth,spider.sg.currentstate.name)
            assert(tx>x+4.4 and tx<x+5.5 and math.abs(tz-z)<.35,"NW_LAB: directed knockback")
        end
    end
    stages[#stages+1]=function()
        local e=target(2.5,0)
        local hits={}
        e:ListenForEvent("attacked",function(_,data)
            if data.attacker==owner then hits[#hits+1]=data.damageresolved end
        end)
        cast({"spore_sentry"})
        return 3.5,function()
            assert(#hits==3 and close(hits[1],6) and close(hits[2],6) and close(hits[3],6),
                "NW_GARDEN: expected three six-damage thorns from caster")
        end
    end
    stages[#stages+1]=function()
        local e=target(8,0)
        cast({"arrow_hit","spore_sentry"})
        return 4,function()
            assert(close(e.components.health.currenthealth,960),"NW_GARDEN: remote sentry at impact, hp="..e.components.health.currenthealth)
        end
    end
    stages[#stages+1]=function()
        local ally=target(1,0)
        ally:AddComponent("follower");ally.components.follower:SetLeader(owner)
        ally.components.health:SetPercent(.5)
        local healed,hits=0,0
        ally:ListenForEvent("healthdelta",function(_,evt)
            if evt.cause=="nw_vital_ring" then healed=healed+evt.amount;hits=hits+1 end
        end)
        owner.components.sanity:DoDelta(-20)
        local san=owner.components.sanity.current
        cast({"chord_d"});cast({"chord_d"})
        assert(close(owner.components.sanity.current-san,1),"NW_GARDEN: repeated note")
        cast({"vital_ring"});cast({"vital_ring"})
        return 3.4,function()
            assert(close(healed,12) and hits==6,"NW_GARDEN: two overlapping rings, healed="..healed.." hits="..hits)
            print("NW_GARDEN_PASS: sentry, remote payload, overlapping rings and D note")
        end
    end
    -- Fire each expansion card through the actual compiler, executor and prefab.
    -- Separate fields with incompatible target side effects into different rounds.
    local batch={}
    local function expansion_round(ids)
        stages[#stages+1]=function()
            target(2.8,0);target(4,0)
            for _,id in ipairs(ids) do
                local d=require("nw/definitions").spells[id]
                if id=="land_hook" then owner.Transform:SetPosition(x,0,z) end
                cast(d.kind=="modifier" and {id,"double","arrow","arrow"} or
                    (d.kind=="multicast" or d.event) and {id,"spark","arrow"} or {id})
            end
            return 8.5,function()
                while #(owner._nw_crystals or {})>0 do owner._nw_crystals[1]:Remove() end
                for _,e in ipairs(TheSim:FindEntities(x,0,z,12,{"nw_breakable"})) do
                    if e.prefab=="nw_payload_egg" and e._nw_owner==owner then e:Remove() end
                end
                owner.Physics:Teleport(x,0,z)
            end
        end
    end
    for _,card in ipairs(require("nw/expansion")) do
        batch[#batch+1]=card.id
        if #batch==9 then expansion_round(batch);batch={} end
    end
    if #batch>0 then expansion_round(batch) end
    stages[#stages+1]=function()
        local e=target(2.5,0)
        cast({"delay_seal","flint_lance"})
        return 1.9,function()
            assert(close(e.components.health.currenthealth,980),"NW_EXPANSION: delayed payload hp="..e.components.health.currenthealth)
        end
    end
    stages[#stages+1]=function()
        local e=target(1,0)
        cast({"sleep_crystal"})
        cast({"detonate"})
        cast({"note_a"})
        owner:DoTaskInTime(.35,function() cast({"note_c"}) end)
        return 1,function()
            assert(close(e.components.health.currenthealth,970),"NW_EXPANSION: crystal + A/C echo")
            print("NW_EXPANSION_PASS: 47 expansion cards, delayed payload, owner detonation and note echo")
        end
    end
    stages[#stages+1]=function()
        local e=target(2,0)
        cast({"payload_egg","arrow"})
        local egg=TheSim:FindEntities(x,0,z,.5,{"nw_breakable"})[1]
        assert(egg and egg.prefab=="nw_payload_egg")
        local outsider=SpawnPrefab("wilson")
        outsider.Physics:Teleport(x+.4,0,z)
        outsider.components.combat:DoAttack(egg)
        assert(not egg:IsValid(),"NW_EXPANSION: native foreign attack failed to open egg")
        return 2,function()
            assert(close(e.components.health.currenthealth,978),"NW_EXPANSION: egg payload")
            outsider:Remove()
        end
    end
    stages[#stages+1]=function()
        local e=target(2,0)
        cast({"rain_cloud"})
        owner:DoTaskInTime(.5,function()
            assert(e:GetWetMultiplier()>0,"NW_EXPANSION: cloud failed to wet")
            cast({"wet_weak","arrow"})
        end)
        return 3.3,function()
            assert(close(e.components.health.currenthealth,972.5),"NW_EXPANSION: wet damage")
        end
    end
    local i=0
    local function advance()
        for _,e in ipairs(targets) do if e:IsValid() then e:Remove() end end
        targets={};i=i+1
        if not stages[i] then
            wand:Remove();owner:Remove()
            print("NW_SPELL_LAB_PASS: remote area + timed area + pierce + chain/leech + six burn ticks + freeze + healing + curve cleanup")
            finish_persistent(done);return
        end
        local delay,check=stages[i]()
        TheWorld:DoTaskInTime(delay,function()
            check()
            assert(Executor.stats()==0,"NW_LAB: budget stage "..i)
            advance()
        end)
    end
    advance()
end
return M
