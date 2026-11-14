local M={}
function M.start(x,z)
    local found
    for offset=30,70 do
        if TheWorld.Map:IsPassableAtPoint(x+offset,0,z) and TheWorld.Map:IsPassableAtPoint(x+offset+3,0,z)
            and #TheSim:FindEntities(x+offset+1.5,0,z,4,nil,{"INLIMBO","FX"},{"_combat","wall","structure"})==0 then
            x=x+offset;found=true;break
        end
    end
    assert(found,"NW_PERSIST: no fixture ground")
    local Executor=require("nw/executor")
    local Compiler=require("nw/compiler")
    local owner=SpawnPrefab("wilson")
    local userid="NW_PERSIST_TEST_"..owner.GUID
    owner.userid=userid;owner.Transform:SetPosition(x,0,z)
    owner.components.combat.CanTarget=function() return false end
    local function cast(ids)
        local w=require("nw/generator").starter()
        w.stats.spread=0;w.stats.mana_max=600;w.cards={}
        for i,id in ipairs(ids) do w.cards[i]={spell_id=id,card_uid="saved:"..i} end
        w.runtime=Compiler.initial(w.cards,w.stats,19)
        assert(Executor.execute(assert(Compiler.compile(w)),owner,x,z,1,0,1.4))
    end
    cast({"crystal_mine"});cast({"sleep_crystal"});cast({"payload_egg","damage_up","arrow"})
    local placements={}
    for _,e in ipairs(TheSim:FindEntities(x,0,z,1)) do
        if e._nw_stored and e._nw_owner==owner then placements[#placements+1]=e end
    end
    assert(#placements==3,"NW_PERSIST: fixtures")
    owner:Remove()
    local start=GetTime()
    return function(done)
        TheWorld:DoTaskInTime(math.max(.1,121-(GetTime()-start)),function()
            local restored={}
            for _,e in ipairs(placements) do
                assert(e:IsValid() and e.persists,"NW_PERSIST: timeout/offline removed placement")
                local record=e:GetSaveRecord()
                assert(record.data.placement and record.data.placement.userid==userid)
                e:Remove()
                restored[#restored+1]=assert(SpawnSaveRecord(record))
            end
            owner=SpawnPrefab("wilson");owner.userid=userid
            owner.Transform:SetPosition(x,0,z)
            TheWorld:DoTaskInTime(.1,function()
            local egg
            for _,e in ipairs(restored) do
                assert(e._nw_owner==owner,"NW_PERSIST: reconnect owner")
                if e.prefab=="nw_payload_egg" then egg=e else e:Remove() end
            end
            local target=SpawnPrefab("nw_target_dummy");target.Transform:SetPosition(x+2,0,z)
            local can_target=owner.components.combat.CanTarget
            owner.components.combat.CanTarget=function(combat,e) return e==target and can_target(combat,e) end
            assert(egg and egg._nw_stored.payload.blocks[1].projectiles[1].damage==32)
            local outsider=SpawnPrefab("wilson");outsider.Transform:SetPosition(x+.4,0,z)
            outsider.components.combat.CanTarget=function(_,e) return e==target or e==egg end
            outsider.components.combat:DoAttack(egg)
            assert(not egg:IsValid(),"NW_PERSIST: outsider cannot open restored egg")
            local attributed=false
            for _,e in ipairs(TheWorld._nw_projectiles.items) do
                if e:IsValid() and e._shot.owner==outsider then attributed=true end
            end
            assert(attributed,"NW_PERSIST: payload did not belong to outsider")
            TheWorld:DoTaskInTime(1.5,function()
                assert(math.abs(target.components.health.currenthealth-968)<.03,"NW_PERSIST: restored payload hp="..target.components.health.currenthealth)
                assert(Executor.stats()==0,"NW_PERSIST: reservation leak")
                target:Remove();owner:Remove();outsider:Remove()
                print("NW_PERSISTENT_FIELDS_PASS: 121s + offline retention, native save/restore, reconnect ownership and modified payload")
                done()
            end)
            end)
        end)
    end
end
return M
