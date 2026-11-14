local M={}
function M.run()
    local previous=TheWorld._nw_boundary_entities
    if previous then
        local old={};for e in pairs(previous.items) do old[#old+1]=e end
        for _,e in ipairs(old) do if e:IsValid() then e:Remove() end end
    end
    local Bounds=require("nw/world_bounds")
    local Limits=require("nw/spell_limits")
    local Executor=require("nw/executor")
    local Copy=require("nw/util").copy
    local map=TheWorld.Map
    local w,h=map:GetSize()
    local edge,z
    for tx=w-1,0,-1 do
        for tz=1,h-2 do
            local x,_,pz=map:GetTileCenterPoint(tx,tz)
            if map:IsAboveGroundAtPoint(x,0,pz,true) then edge,z=x+TILE_SCALE/2,pz;break end
        end
        if edge then break end
    end
    assert(edge and Limits.boundary_cleanup and Limits.range==0 and Limits.depth==0,"NW_BOUNDS: defaults/fixture")
    assert(not Bounds.outside(edge+4.9,z) and Bounds.outside(edge+5,z),"NW_BOUNDS: actual map five-unit margin")
    assert(Bounds.outside(w*TILE_SCALE/2+100,z),"NW_BOUNDS: outside tile array")
    local saved_rule=TheWorld.CanFlyingCrossBarriers
    TheWorld.CanFlyingCrossBarriers=function() return false end
    assert(Bounds.outside(edge+.1,z),"NW_BOUNDS: natural barrier")
    TheWorld.CanFlyingCrossBarriers=saved_rule
    print("NW_BOUNDS_MAP_PASS:",edge,z,w,h)

    local owner=SpawnPrefab("wilson")
    owner.entity:SetCanSleep(false)
    owner.components.health:SetInvincible(true)
    owner.components.combat.CanTarget=function() return false end
    local function shot(id)
        local p=Copy(require("nw/definitions").spells[id])
        p.flags={targets={hostile=true}};p.spread=0
        return p
    end
    local moving={}
    for _,id in ipairs({"crystal_mine","sleep_crystal","payload_egg","edge_yellowstaff","edge_opalstaff"}) do
        local p=shot(id);p.speed=6;p.field_drive=true
        local e=SpawnPrefab("nw_"..id)
        e:Launch(owner,p,edge-1,z,1,0,function() end,1.4)
        assert(e:IsValid(),"NW_BOUNDS: field launch "..id)
        moving[#moving+1]=e
    end
    local record=moving[2]:GetSaveRecord()
    record.x=edge+8;record.z=z
    local restored=SpawnSaveRecord(record)
    assert(not restored or not restored:IsValid(),"NW_BOUNDS: stale saved placement")

    local p=shot("arrow_hit");p.speed=20;p.lifetime=5;p.payload=2
    local plan={projectile_count=2,next_state={rng_state=1},blocks={
        {projectiles={p}},{projectiles={shot("spark")}},
    }}
    assert(Executor.execute(plan,owner,edge-1,z,1,0,1.4))
    local far=SpawnPrefab("nw_projectile")
    local fp=shot("spark");fp.speed=30;fp.lifetime=5
    far:Launch(owner,fp,edge-70,z,1,0,function() end,1.4)
    local enabled=Limits.boundary_cleanup;Limits.boundary_cleanup=false
    far.Physics:Teleport(edge-35,0,z)
    require("nw/projectiles").step(far,GetTime()+1.2,{})
    Limits.boundary_cleanup=enabled
    assert(far:IsValid() and far._shot.travelled>=35,"NW_BOUNDS: implicit range cap")
    far:Remove()
    TheWorld:DoTaskInTime(1.5,function()
        for _,e in ipairs(moving) do
            if e:IsValid() then
                print("NW_BOUNDS_POSITION:",e.prefab,e.Transform:GetWorldPosition())
                print("NW_BOUNDS_MOTOR:",e.Physics:GetMotorVel())
            end
            assert(not e:IsValid(),"NW_BOUNDS: moving field survived "..e.prefab)
        end
        assert(Executor.stats()==0,"NW_BOUNDS: unreleased carrier/payload")
        for _,e in ipairs(TheSim:FindEntities(edge+5,0,z,20,{"FX"})) do
            assert(not (e.prefab=="nw_projectile" and e._shot and e._shot.owner==owner),"NW_BOUNDS: payload escaped cleanup")
        end
        owner:Remove()
        assert(not next(TheWorld._nw_boundary_entities.items),"NW_BOUNDS: stale watch entries")
        assert(not TheWorld._nw_boundary_entities.task,"NW_BOUNDS: idle task survived")
        print("NW_BOUNDS_PASS: real map margin, natural barrier rule, saved fields, native motion, range, silent payload cleanup and idle task")
    end)
end
return M
