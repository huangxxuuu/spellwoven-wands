local M={}
function M.run(done,launchx,launchz,x)
    local Copy=require("nw/util").copy
    local Motion=require("nw/field_motion")
    local Stored=require("nw/persistent_fields")
    local all={}
    local function spawn(name) local e=SpawnPrefab(name);all[#all+1]=e;return e end
    local placer=spawn("wilson");placer.components.health:SetInvincible(true)
    local triggerer=spawn("wilson");triggerer.components.health:SetInvincible(true)
    local target=spawn("pigman");target:StopBrain();target.Physics:Stop()
    target.entity:SetCanSleep(false);target.components.health:SetInvincible(true)
    target.Physics:Teleport(x+6,0,300)
    local blast_target=spawn("nw_target_dummy")
    blast_target.entity:SetCanSleep(false);blast_target.Transform:SetPosition(x+2,0,453)
    placer.components.combat.CanTarget=function(_,e) return e==target or e==blast_target end
    triggerer.components.combat.CanTarget=function() return false end
    local function compile(ids)
        local w=require("nw/generator").starter();w.stats.mana_max=2000;w.cards={}
        for i,id in ipairs(ids) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
        w.runtime=require("nw/compiler").initial(w.cards,w.stats,3)
        return assert(require("nw/compiler").compile(w))
    end
    local function place(ids,z)
        local plan=compile(ids);local p=plan.blocks[1].projectiles[1]
        local e=spawn("nw_"..p.id)
        e:Launch(placer,p,launchx,launchz,1,0,function() end,1.4)
        e.Physics:Teleport(x,0,z)
        if e._nw_motion then e._nw_motion.x,e._nw_motion.z=x,z end
        return e
    end
    local homing=place({"homing","payload_egg"},300)
    local star=place({"speed_up","sine","edge_yellowstaff"},330)
    local inert=place({"speed_up","payload_egg"},360)
    local egg=place({"payload_egg"},390)
    local crystal=place({"sleep_crystal"},420)
    local guided_crystal=place({"homing","sleep_crystal"},450)
    -- Replace only this egg's stored payload with a real compiled arrow plan.
    egg._nw_stored.payload={blocks=compile({"arrow"}).blocks,projectile_count=1,next_state={rng_state=1},payload_root=true}
    local gust=spawn("nw_projectile")
    local p=compile({"gust"}).blocks[1].projectiles[1]
    gust:Launch(triggerer,p,x-3,390,1,0,function() end,1.4)
    TheWorld:DoTaskInTime(1.55,function()
        assert(homing:IsValid() and homing:GetPosition().x>x+.5,"NW_MOTION: native guidance must launch from rest")
        assert(star:IsValid() and math.abs(star:GetPosition().z-330)>.1,"NW_MOTION: native star must use sine path")
        assert(inert:IsValid() and inert._nw_motion.vx>0 and inert._nw_motion.vx<2,"NW_MOTION: native permanent drag")
        assert(egg:IsValid() and egg._nw_motion and egg._nw_motion.vx>0 and not egg._nw_spent,"NW_MOTION: gust pushed, not triggered")
        assert(not Motion.push_egg(crystal,triggerer,1,0,8) and not crystal._nw_motion,"NW_MOTION: crystals reject gust")
        local bx,_,bz=guided_crystal.Transform:GetWorldPosition()
        guided_crystal._nw_break()
        assert(math.abs(blast_target.components.health.currenthealth-978)<.03,
            "NW_MOTION: guided crystal blast hp="..blast_target.components.health.currenthealth.." distance="..math.sqrt(blast_target:GetDistanceSqToPoint(bx,0,bz)))
        local record=inert:GetSaveRecord();inert:Remove()
        local restored=SpawnSaveRecord(record);all[#all+1]=restored
        assert(restored and restored._nw_motion and restored._nw_motion.vx<2,"NW_MOTION: saved velocity")
        placer:Remove()
        assert(not Stored.owner(egg),"NW_MOTION: original placer gone")
        -- Exercise the real attacked/blocked listener, not a replacement callback.
        egg:PushEvent("attacked",{attacker=triggerer})
        assert(not egg:IsValid(),"NW_MOTION: other player can open egg after placer leaves")
        local found=false
        for _,e in ipairs(TheWorld._nw_projectiles.items) do
            if e:IsValid() and e._shot.p.id=="arrow" and e._shot.owner==triggerer then found=true;e:Remove() end
        end
        assert(found,"NW_MOTION: payload belongs to actual triggerer")
        for _,e in ipairs(all) do if e and e:IsValid() then e:Remove() end end
        print("NW_MOTION_RULES_PASS: real guidance, star sine, drag, gust, saved velocity and offline-placer payload attribution")
        done()
    end)
end
return M
