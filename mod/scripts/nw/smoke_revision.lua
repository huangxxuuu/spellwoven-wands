local M={}
function M.run()
    local Copy=require("nw/util").copy
    local C=require("nw/compiler")
    local E=require("nw/executor")
    local D=require("nw/definitions").spells
    local made={}
    local function spawn(id,x,z)
        local e=assert(SpawnPrefab(id),id);e.Transform:SetPosition(x,0,z);made[#made+1]=e;return e
    end
    local x,z=0,0
    for _,e in pairs(Ents) do if e:HasTag("multiplayer_portal") then x,_,z=e.Transform:GetWorldPosition();break end end
    local a,b=spawn("wilson",x,z),spawn("wilson",x+1,z)
    a.entity:SetCanSleep(false);b.entity:SetCanSleep(false)
    -- Exercise the native new-character callback, not just a mocked event.
    a.userid="NW_STARTER_REVISION_TEST"
    a:OnNewSpawn({})
    local starter=a.components.inventory:FindItem(function(item) return item.prefab=="nw_wand" end)
    assert(starter and starter.components.nw_wand.data.cards[1].spell_id=="spark","NW_REVISION: enabled starting wand missing")
    starter:Remove()
    local function plan(...)
        local w=require("nw/generator").starter();w.stats.mana_max=2000;w.stats.spread=0;w.cards={}
        for i,id in ipairs({...}) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
        w.runtime=C.initial(w.cards,w.stats,7)
        return assert(C.compile(w))
    end
    -- An unrelated character and native explosion can break dormant crystals.
    for _,event in ipairs({"weapon","explosion"}) do
        local crystal=spawn("nw_sleep_crystal",x+10,z+10)
        crystal:Launch(a,Copy(D.sleep_crystal),x+10,z+10,1,0,function() end,1.4)
        if event=="weapon" then crystal.components.combat:GetAttacked(b,1)
        else crystal:PushEvent("explosion",{explosive=b}) end
        assert(not crystal:IsValid(),"NW_REVISION: dormant crystal ignored "..event)
    end
    local function egg()
        local e=spawn("nw_payload_egg",x+4,z)
        local p=plan("payload_egg","spark").blocks[1].projectiles[1]
        e:Launch(a,p,x+4,z,1,0,function() end,1.4,nil,plan("spark"))
        return e
    end
    local function last_caster()
        local found
        for _,e in pairs(Ents) do if e._shot and e._shot.p.id=="spark" then found=e._shot.owner;e:Remove() end end
        return found
    end
    local e=egg();e.components.combat:GetAttacked(b,10)
    assert(not e:IsValid() and last_caster()==b,"NW_REVISION: direct player attack attribution")
    local hound=spawn("hound",x+15,z);hound:StopBrain("test")
    e=egg();e.components.combat:GetAttacked(hound,10)
    assert(not e:IsValid() and last_caster()==hound,"NW_REVISION: creature attack")
    e=egg();require("nw/spell_effects").blast(b,x+4,z,{damage=22,radius=1.8,flags={}})
    assert(not e:IsValid() and last_caster()==b,"NW_REVISION: crystal blast opens egg")
    e=egg()
    local powder=spawn("gunpowder",x+4,z);powder.components.explosive:SetAttacker(b)
    powder.components.explosive:OnBurnt()
    assert(not e:IsValid() and last_caster()==b,"NW_REVISION: native explosion resolves attacker")
    e=egg();e.components.combat:GetAttacked(nil,1)
    local neutral=last_caster()
    assert(not e:IsValid() and neutral and neutral._nw_neutral,"NW_REVISION: neutral fallback")
    -- Friendly fire is native gunpowder behaviour, regardless of targeting modifiers.
    a.components.health:SetCurrentHealth(100);b.components.health:SetCurrentHealth(100)
    local beforea,beforeb=a.components.health.currenthealth,b.components.health.currenthealth
    require("nw/explosions").hit(a,{flags={targets={hostile=true},explosive_hit=D.explosion}},x,z)
    assert(a.components.health.currenthealth==beforea-25 and b.components.health.currenthealth==beforeb-25,"NW_REVISION: native all-side explosion")
    a.components.health:SetInvincible(true);b.components.health:SetInvincible(true)
    require("nw/smoke_weapons").run(a,x,z)
    local p=plan("gunpowder").blocks[1].projectiles[1]
    powder=spawn("nw_gunpowder",x+8,z)
    powder:Launch(a,p,x+8,z,1,0,function() end)
    assert(powder.components.burnable:IsBurning() and not powder.components.inventoryitem.canbepickedup)
    powder.components.burnable:Extinguish();assert(not powder:IsValid(),"NW_REVISION: extinguished powder removed")
    local modified=plan("long_life","short_life","speed_up","homing","giant_shot","damage_up","gunpowder").blocks[1].projectiles[1]
    powder=spawn("nw_gunpowder",x+8,z)
    local base_fuse=powder.components.burnable.burntime
    powder:Launch(a,modified,x+8,z,1,0,function() end)
    assert(math.abs(powder.components.burnable.burntime-base_fuse*1.35*.5)<.001,"NW_REVISION: modified native fuse")
    assert(powder._nw_motion and powder._nw_motion.p.flags.homing and modified.speed==2,"NW_REVISION: shared powder motion")
    assert(powder.components.explosive.explosiverange==7.5 and powder.components.explosive.explosivedamage==TUNING.GUNPOWDER_DAMAGE+10,
        "NW_REVISION: powder size/damage modifiers")
    local saved=powder:GetSaveRecord()
    local left=saved.data.nw_powder.remaining
    powder:Remove()
    local restored=assert(SpawnSaveRecord(saved));made[#made+1]=restored
    TheWorld:DoTaskInTime(.1,function()
        assert(restored:IsValid() and restored.components.burnable:IsBurning(),"NW_REVISION: restore burning powder")
        assert(math.abs(restored.components.burnable.burntime-left)<.001,"NW_REVISION: saved fuse must not multiply twice")
        assert(restored.components.explosive.explosiverange==7.5,"NW_REVISION: saved giant must not multiply twice")
        restored.components.burnable:Extinguish()
        assert(not restored:IsValid(),"NW_REVISION: restored powder extinguish")
    end)
    -- Ocean placements must disappear without releasing their payload.
    local ox,oz
    for i=0,500,4 do if TheWorld.Map:IsOceanAtPoint(x+i,0,z) and not TheWorld.Map:GetPlatformAtPoint(x+i,z) then ox,oz=x+i,z;break end end
    assert(ox,"NW_REVISION: ocean fixture")
    for _,id in ipairs({"payload_egg","crystal_mine","sleep_crystal"}) do
        local field=spawn("nw_"..id,ox,oz)
        field:Launch(a,plan(id).blocks[1].projectiles[1],ox,oz,1,0,function() end,1.4,nil,plan("spark"))
        assert(not field:IsValid(),"NW_REVISION: ocean placement must sink")
    end
    assert(not last_caster(),"NW_REVISION: sinking must not release payload")
    local lo,hi=x,ox
    for _=1,18 do
        local mid=(lo+hi)/2
        if TheWorld.Map:IsOceanAtPoint(mid,0,z) then hi=mid else lo=mid end
    end
    local ground=require("nw/ground_fields")
    local function crossing(sx,sz,ex,ez,surface)
        local field=spawn("nw_payload_egg",sx,sz)
        local motion=plan("speed_up","payload_egg","spark").blocks[1].projectiles[1]
        field:Launch(a,motion,sx,sz,1,0,function() end,1.4,nil,plan("spark"))
        field.Physics:Teleport(ex,0,ez)
        require("nw/projectiles").step(field,GetTime()+.1,{})
        local fx,_,fz=field.Transform:GetWorldPosition()
        assert(field:IsValid() and field._nw_motion.stopped and ground.surface(fx,fz)==surface,"NW_REVISION: ground surface crossing")
        field:Remove()
    end
    crossing(lo-.5,z,hi+.5,z,"land")
    local boat=spawn("boat",ox+10,oz)
    crossing(ox+10,oz,ox+17,oz,boat)
    assert(AllRecipes.nw_inscribe_gunpowder,"NW_REVISION: workbench powder recipe")
    local positions={}
    for dx=-12,12,4 do for dz=8,24,4 do
        if TheWorld.Map:IsPassableAtPoint(x+dx,0,z+dz) then positions[#positions+1]={x+dx,z+dz} end
    end end
    local pt=assert(positions[1])
    -- Count actual native powder payloads from all three independent timers.
    assert(E.execute(plan("short_life","short_life","scatter_timer","gunpowder"),a,pt[1],pt[2],1,0,1.4))
    TheWorld:DoTaskInTime(.8,function()
        local count=0
        for _,v in pairs(Ents) do if v.prefab=="nw_gunpowder" then
            count=count+1;assert(v.components.burnable:IsBurning());v:Remove()
        end end
        assert(count==3,"NW_REVISION: scatter must release three independent native payloads")
        assert(E.stats()==0,"NW_REVISION: reservations leaked")
        local fuse=spawn("nw_gunpowder",pt[1],pt[2])
        fuse:Launch(a,p,pt[1],pt[2],1,0,function() end)
        local explosions=0
        TheWorld:ListenForEvent("explosion",function() explosions=explosions+1 end)
        local short=spawn("nw_gunpowder",pt[1],pt[2])
        local short_plan=plan("short_life","short_life","short_life","gunpowder").blocks[1].projectiles[1]
        short:Launch(a,short_plan,pt[1],pt[2],1,0,function() end)
        TheWorld:DoTaskInTime(1,function()
            assert(not short:IsValid() and fuse:IsValid(),"NW_REVISION: short fuse explodes before unmodified fuse")
        end)
        TheWorld:DoTaskInTime(7,function()
            assert(not fuse:IsValid() and explosions>0,"NW_REVISION: native fuse explosion")
            assert(not neutral:IsValid(),"NW_REVISION: neutral caster released")
            assert(require("nw/smoke_weapons").passed,"NW_REVISION: weapon regression suite")
            for _,v in ipairs(made) do if v:IsValid() then v:Remove() end end
            print("NW_REVISION_PASS: native attacks/area/explosive egg ownership, neutral cleanup, all-side blast, powder fuse/extinguish, ocean sink, land/boat boundaries, independent scatter payloads and budgets")
        end)
    end)
end
return M
