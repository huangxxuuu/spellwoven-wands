local M={}
function M.run(owner,x,z)
    require("nw/smoke_card_identity").run(x+24,z+24)
    require("nw/smoke_edit_transfer").run(x+30,z+24)
    local C=require("nw/compiler")
    local function p(...)
        local w=require("nw/generator").starter();w.stats.mana_max=2000;w.cards={}
        for i,id in ipairs({...}) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
        w.runtime=C.initial(w.cards,w.stats,1)
        return assert(C.compile(w)).blocks[1].projectiles[1]
    end
    local made={}
    local function spawn(id)
        local e=assert(SpawnPrefab(id),id);e.Transform:SetPosition(x,0,z);made[#made+1]=e;return e
    end
    for _,orbit in ipairs({true,false}) do
        local testwand=spawn("nw_wand");local c=testwand.components.nw_wand
        c:InitializePrototype()
        local d=c.data
        d.stats.capacity=12;d.stats.mana_max=600;d.stats.mana_regen=80
        d.stats.draw_count=1;d.stats.shuffle=false;d.stats.spread=0
        d.stats.cast_delay=.45;d.stats.recharge=.5
        d.always_cast=nil;d.cards={}
        local ids={"giant_shot",false,"repeat_2","repeat_3","repeat_2","repeat_2",
            orbit and "orbit" or false,"trident_cast",false,"fire","frost","fire"}
        for i,id in ipairs(ids) do d.cards[i]=id and {card_uid="mana:"..i,spell_id=id} or false end
        d.runtime=C.initial(d.cards,d.stats,1);d.config_revision=d.config_revision+1;c:Sync()
        if orbit then
            local saved=testwand:GetSaveRecord()
            local bad=saved.data.nw_wand.wand
            bad.cards[7].card_uid=bad.cards[1].card_uid
            bad.runtime=C.initial(bad.cards,bad.stats,1)
            testwand:Remove();testwand=assert(SpawnSaveRecord(saved));made[#made+1]=testwand
            c=testwand.components.nw_wand;d=c.data
            assert(d.cards[7].spell_id=="orbit" and d.cards[1].card_uid~=d.cards[7].card_uid,
                "NW_MANA_SCREENSHOT: saved collision was not repaired")
        end
        owner.components.inventory:GiveItem(testwand);owner.components.inventory:Equip(testwand)
        local ok,why,plan=c:CanCast(owner)
        local cost=orbit and 223 or 213
        assert(ok and plan.mana_required==cost and plan.mana_spent==cost and plan.projectile_count==72,
            "NW_MANA_SCREENSHOT: readiness "..tostring(why))
        local previous={};for _,e in pairs(Ents) do previous[e]=true end
        local aim=owner:GetPosition()+Vector3(10,0,0)
        assert(c:Cast(owner,aim,plan),"NW_MANA_SCREENSHOT: native cast failed")
        assert(math.abs(d.runtime.mana-(600-cost))<.01,"NW_MANA_SCREENSHOT: actual mana mismatch")
        local count=0
        for _,e in pairs(Ents) do
            if not previous[e] and e._shot and e._shot.owner==owner then count=count+1;e:Remove() end
        end
        assert(count==72,"NW_MANA_SCREENSHOT: actual projectile count "..count)
        testwand:Remove()
        print("NW_MANA_SCREENSHOT_PASS:",orbit and "orbit" or "no orbit",cost,count)
    end
    local boxes,ids=require("nw/spellkit").dropkit(owner)
    local expected={}
    for _,id in ipairs(require("nw/card_rarity").pool) do expected[id]=true end
    for _,r in ipairs(require("nw/acquisition").recipes) do if r.card then expected[r.card]=nil end end
    local actual={}
    for _,box in ipairs(boxes) do
        for _,card in pairs(box.components.container.slots) do
            assert(card.card_uid,"NW_REVIEW36: card UID deferred until save")
            local id=card.spell_id
            assert(expected[id] and not actual[id],"NW_REVIEW36: incorrect dropkit content "..tostring(id))
            actual[id]=true
        end
        box.components.container:DestroyContents();box:Remove()
    end
    for id in pairs(expected) do assert(actual[id],"NW_REVIEW36: dropkit missing "..id) end
    assert(#ids>0,"NW_REVIEW36: empty dropkit")
    local wand=spawn("nw_wand");wand.components.nw_wand:InitializeNew(3,"debug",nil,713)
    owner.components.inventory:GiveItem(wand);owner.components.inventory:Equip(wand)
    local data=wand.components.nw_wand.data
    data.cards[1]=require("nw/wand_factory").card("spark","debug")
    local uid=data.cards[1].card_uid
    local Damage=require("nw/wand_damage")
    Damage.set(wand,true)
    assert(wand:HasTag("nw_broken") and not wand.components.nw_wand:CanCast(owner),"NW_REVIEW36: broken wand still usable")
    assert(wand._nw_broken:value() and wand._held_visual._broken:value(),"NW_REVIEW36: broken visual replication")
    local record=wand:GetSaveRecord();wand:Remove()
    wand=assert(SpawnSaveRecord(record));made[#made+1]=wand
    assert(wand.components.nw_wand.data.broken and wand.components.nw_wand.data.cards[1].card_uid==uid,"NW_REVIEW36: broken save lost cards")
    owner.components.inventory:GiveItem(wand)
    local dust=spawn("nw_dust");dust.components.stackable:SetStackSize(8);owner.components.inventory:GiveItem(dust)
    assert(Damage.repair({target=wand,invobject=dust,doer=owner}),"NW_REVIEW36: repair rejected")
    assert(dust.components.stackable:StackSize()==3 and not wand:HasTag("nw_broken"),"NW_REVIEW36: repair dust/state")
    assert(wand.components.nw_wand.data.cards[1].card_uid==uid,"NW_REVIEW36: repair changed cards")
    owner.components.inventory:Equip(wand)
    local bench=spawn("nw_workbench")
    local backpack=spawn("backpack");owner.components.inventory:Equip(backpack)
    local source=spawn("nw_spellcard");source:SetSpell("arrow");source.components.stackable:SetStackSize(2)
    backpack.components.container:GiveItem(source,1)
    assert(require("nw/editing").commit(owner,wand,2,source,wand.components.nw_wand.data.config_revision,false),"NW_REVIEW36: backpack insertion")
    assert(source.components.stackable:StackSize()==1 and wand.components.nw_wand.data.cards[2].spell_id=="arrow","NW_REVIEW36: backpack stack split")
    assert(require("nw/editing").commit(owner,wand,2,nil,wand.components.nw_wand.data.config_revision,false),"NW_REVIEW36: shift removal")
    assert(not wand.components.nw_wand.data.cards[2],"NW_REVIEW36: slot not cleared")
    wand:Remove();dust:Remove();bench:Remove();backpack:Remove()
    local foreign=spawn("wilson");foreign.entity:SetCanSleep(false);foreign.components.health:SetInvincible(true)
    assert(not TheNet:GetPVPEnabled(),"NW_REVIEW36: requires cooperative fixture")
    assert(require("nw/targeting").allowed(owner,foreign,{targets={players_other=true}}),"NW_REVIEW36: player selection gated by PvP")
    local guard=spawn("nw_guard_ring");guard:Launch(owner,p("guard_ring"),x,z,1,0,function() end)
    local dart=spawn("blowdart_pipe");dart.components.projectile:Throw(foreign,owner)
    dart.Physics:Teleport(owner.Transform:GetWorldPosition())
    dart.components.projectile:Hit(owner)
    assert(not dart:IsValid() and guard._nw_guard_left==1,"NW_REVIEW36: native dart not silently intercepted")
    local balloon=spawn("waterballoon");balloon.components.complexprojectile:Launch(owner:GetPosition(),foreign)
    balloon.Physics:Teleport(owner.Transform:GetWorldPosition())
    balloon.components.complexprojectile:Hit()
    assert(not balloon:IsValid() and not guard:IsValid(),"NW_REVIEW36: native lob not intercepted")
    local aura=spawn("nw_vital_ring")
    aura:Launch(owner,p("target_self","speed_up","homing","vital_ring"),x-2,z,1,0,function() end)
    aura._nw_motion.ignore_self=false
    aura.Physics:Teleport(x+.1,0,z)
    require("nw/projectiles").step(aura,GetTime()+.1,{})
    assert(aura:IsValid() and not aura._nw_motion.stopped,"NW_REVIEW36: self aura stopped on owner")
    aura:Remove()
    local glowing=spawn("nw_vital_ring")
    glowing:Launch(owner,p("light","searing_halo","vital_ring"),x,z,1,0,function() end)
    assert(glowing._nw_field_effects_attached and glowing._nw_effects and not glowing._nw_motion,"NW_REVIEW36: stationary field lost continuous modifiers")
    local star=spawn("nw_edge_yellowstaff")
    local duration=star.components.timer:GetTimeLeft("extinguish")
    star:Launch(owner,p("short_life","edge_yellowstaff"),x,z,1,0,function() end)
    assert(math.abs(star.components.timer:GetTimeLeft("extinguish")-duration*.5)<.1,"NW_REVIEW36: native star lifetime")
    star:Remove()
    local ox,oz
    for i=8,500,4 do
        if TheWorld.Map:IsOceanAtPoint(x+i,0,z) and not TheWorld.Map:GetPlatformAtPoint(x+i,z) then ox,oz=x+i,z;break end
    end
    assert(ox,"NW_REVIEW36: ocean fixture")
    TheWorld:DoTaskInTime(.05,function()
        foreign.components.health:SetInvincible(false)
        require("nw/engraved_impact").finish({owner=foreign,p={engraving="orangestaff"}},ox,oz)
    end)
    local storm=spawn("nw_projectile")
    storm:Launch(owner,p("giant_shot","edge_staff_tornado"),x+10,z+10,1,0,function() end,1.4)
    local native=storm._shot.native
    local sx,_,sz=storm.Transform:GetWorldPosition();local nx,_,nz=native.Transform:GetWorldPosition()
    TheWorld:DoTaskInTime(.25,function()
        assert(storm:IsValid() and native:IsValid(),"NW_REVIEW36: tornado fixture expired")
        local ex,_,ez=storm.Transform:GetWorldPosition();local fx,_,fz=native.Transform:GetWorldPosition()
        assert(math.abs((ex-sx)-(fx-nx))<.7 and math.abs((ez-sz)-(fz-nz))<.7,"NW_REVIEW36: giant native visual drifts ahead")
        assert(foreign.sg:HasStateTag("drowning"),"NW_REVIEW36: water teleport did not enter native drowning state")
        for _,e in ipairs(made) do if e:IsValid() then e:Remove() end end
        M.passed=true
        print("NW_REVIEW36_PASS: broken wand/save/repair, native dart/lob guard, cooperative targeting, self aura, star lifetime and giant tornado")
    end)
end
return M
