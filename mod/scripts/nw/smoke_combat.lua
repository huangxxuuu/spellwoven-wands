local M={}
function M.run(done)
    local wand=SpawnPrefab("nw_wand")
    wand.components.nw_wand:InitializePrototype()
    local caster=SpawnPrefab("nw_target_dummy")
    caster:AddComponent("inventory")
    caster.components.inventory:GiveItem(wand)
    caster.components.inventory:Equip(wand)
    local x,z=0,0
    for _,e in pairs(Ents) do
        if e:HasTag("multiplayer_portal") then x,_,z=e.Transform:GetWorldPosition();break end
    end
    local found=false
    for offset=0,100 do
        if TheWorld.Map:IsPassableAtPoint(x+offset,0,z) and TheWorld.Map:IsPassableAtPoint(x+offset+4,0,z)
            and #TheSim:FindEntities(x+offset+2,0,z,7,{"_combat"},{"INLIMBO"})==0 then
            x=x+offset;found=true;break
        end
    end
    assert(found,"NW_COMBAT: no test ground")
    caster.Transform:SetPosition(x,0,z)
    local target=SpawnPrefab("nw_target_dummy")
    target.Transform:SetPosition(x+4,0,z)
    local point=Vector3(x+4,0,z)
    local cmp=wand.components.nw_wand
    cmp.data.runtime.mana=0;cmp.last_time=GetTime()
    local dry,reason=cmp:CanCast(caster)
    assert(not dry and reason=="NO_MANA","NW_MANA: readiness accepted dry cast")
    dry,reason=cmp:Cast(caster,point)
    assert(not dry and reason=="NO_MANA" and cmp.data.runtime.remaining_cast==0
        and #cmp.data.runtime.deck==1 and #cmp.data.runtime.discard==0,"NW_MANA: dry cast advanced runtime")
    cmp.data.runtime.mana=120
    local ready,_,prepared=cmp:CanCast(caster)
    assert(ready and prepared and prepared.mana_spent==5,"NW_MANA: recovered readiness")
    local success,err=cmp:Cast(caster,point,prepared)
    assert(success,err)
    print("NW_MANA_PASS: dry cast blocked without spend/draw/cooldown; affordable prepared cast launches")
    assert(wand.components.nw_wand.data.runtime.mana==115,"NW_COMBAT: mana spend")
    local shot
    for _,e in pairs(Ents) do
        if e.prefab=="nw_projectile" and e._shot and e._shot.owner==caster then shot=e;break end
    end
    assert(shot,"NW_COMBAT: missing spawned projectile")
    local height=shot._height:value()
    assert(height>1 and math.abs(height-shot._shot.height)<.001,"NW_COMBAT: visual muzzle height at launch")
    local launchx,_,launchz=shot.Transform:GetWorldPosition()
    TheWorld:DoTaskInTime(2*FRAMES,function()
        if shot:IsValid() then
            local px,py,pz=shot.Transform:GetWorldPosition()
            assert((px-launchx)^2+(pz-launchz)^2>.01,"NW_PHYSICS: projectile did not move")
            assert(math.abs(py)<.001 and math.abs(shot._height:value()-height)<.001,"NW_PHYSICS: ground plane/visual height changed")
        end
    end)
    TheWorld:DoTaskInTime(FRAMES,function()
        if shot:IsValid() then
            local _,movingheight=shot.Transform:GetWorldPosition()
            assert(math.abs(movingheight)<.001 and math.abs(shot._height:value()-height)<.001,"NW_COMBAT: visual muzzle height changed")
        end
    end)
    local second,reason=wand.components.nw_wand:Cast(caster,point)
    assert(not second and reason=="COOLDOWN","NW_COMBAT: cooldown bypass")
    TheWorld:DoTaskInTime(1.2,function()
        assert(target.components.health.currenthealth==982,"NW_COMBAT: expected one 18 damage hit")
        assert(require("nw/executor").stats()==0,"NW_COMBAT: budget leak")
        local saved=wand.components.nw_wand:OnSave()
        local clone=SpawnPrefab("nw_wand")
        clone.components.nw_wand:OnLoad(saved)
        assert(clone.components.nw_wand.data.runtime.mana==saved.wand.runtime.mana,"NW_COMBAT: restore")
        clone:Remove()
        wand.components.nw_wand:SetTestLoadout("double")
        assert(wand.components.nw_wand:Cast(caster,point))
        assert(wand.components.nw_wand.data.runtime.mana==105,"NW_COMBAT: double mana")
        TheWorld:DoTaskInTime(1.2,function()
            assert(target.components.health.currenthealth==942,"NW_COMBAT: double damage")
            assert(require("nw/executor").stats()==0,"NW_COMBAT: double budget leak")
            require("nw/smoke_editing").run(caster,wand)
            wand:Remove();caster:Remove();target:Remove()
            print("NW_COMBAT_PASS: single=18 double=40 mana=5/15 cooldown=blocked budget=0 restore=ok")
            done(x,z)
        end)
    end)
end
return M
