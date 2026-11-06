-- Called only by the opt-in isolated revision smoke world.
local M={}
function M.run(owner,x,z)
    local made={}
    local D=require("nw/definitions").spells
    local Copy=require("nw/util").copy
    local function spawn(id,dx,dz)
        local e=assert(SpawnPrefab(id),id);made[#made+1]=e
        e.Transform:SetPosition(x+(dx or 0),0,z+(dz or 0));return e
    end
    local function shot(id,dx,dz)
        local e=spawn("nw_projectile",dx,dz)
        local p=Copy(D[id]);p.id=id;p.flags={}
        e:Launch(owner,p,x+(dx or 0),z+(dz or 0),1,0,function() end,1.4)
        e._shot.group={healed={}}
        return e
    end
    local torch=spawn("nw_edge_torch_fx")
    assert(torch._nw_flame and torch._nw_flame:IsValid(),"NW_WEAPONS: lit torch follower")
    local flame=torch._nw_flame;torch:Remove()
    assert(not flame:IsValid(),"NW_WEAPONS: torch fire cleanup")
    local lighter=shot("edge_lighter",8,0)
    assert(lighter.components.complexprojectile and lighter._height:value()==0,"NW_WEAPONS: aimed airborne lighter body")
    assert(lighter._nw_flame and lighter._nw_flame:IsValid(),"NW_WEAPONS: lit lighter projectile")
    local food=spawn("carrot",8,0);food.components.stackable:SetStackSize(5)
    local fuel=spawn("log",8,1)
    fuel.components.burnable:Ignite()
    require("nw/engraved_fire").absorb(owner,x+6,z,x+10,z,3)
    assert(not fuel.components.burnable:IsBurning(),"NW_WEAPONS: swept fire absorption")
    require("nw/engraved_impact").finish(lighter._shot,x+8,z)
    assert(not food:IsValid() and fuel.components.burnable:IsBurning(),"NW_WEAPONS: lighter cooking and ignition")
    local cooked=0
    for _,e in ipairs(TheSim:FindEntities(x+8,0,z,3)) do
        if e.prefab=="carrot_cooked" then cooked=cooked+e.components.stackable:StackSize();e:Remove() end
    end
    assert(cooked==5,"NW_WEAPONS: preserve cooked stack")
    flame=lighter._nw_flame;lighter:Remove();fuel:Remove()
    assert(not flame:IsValid(),"NW_WEAPONS: lighter fire cleanup")
    for id,p in pairs(D) do if p.ballistic then
        local e=shot(id,12,0)
        for _,distance in ipairs({2,7,18,35}) do
            require("nw/engraved_flight").aim_ground(e,e._shot,distance)
            local c=e.components.complexprojectile
            local time=distance/c.velocity.x
            assert(math.abs(1.4+c.velocity.y*time+.5*c.gravity*time*time)<.00001,"NW_WEAPONS: aimed arc "..id)
            assert(math.abs(c.velocity.x-e._shot.vx)<.00001,"NW_WEAPONS: shared velocity "..id)
        end
        e:Remove()
    end end
    local boomerang=shot("edge_voidcloth_boomerang",10,0)
    local bolt=boomerang._shot.native
    local bx,by,bz=bolt.Transform:GetWorldPosition()
    require("nw/engraved_impact").finish(boomerang._shot,bx-1,bz)
    local ax,ay,az=bolt.Transform:GetWorldPosition()
    assert(ax==bx and ay==by and az==bz,"NW_WEAPONS: return handoff must preserve position")
    assert(DiffAngle(bolt.Transform:GetRotation(),bolt:GetAngleToPoint(owner:GetPosition()))<.01,"NW_WEAPONS: return faces owner immediately")
    boomerang:Remove();bolt:Remove()
    local lab=spawn("researchlab",-8,0)
    local wall=spawn("wall_wood",-8,1)
    local boat=spawn("boat",-8,-1)
    local labwork,wallhealth,boathealth=lab.components.workable.workleft,wall.components.health.currenthealth,boat.components.health.currenthealth
    local events,docks=0,0
    local function onexplode() events=events+1 end
    TheWorld:ListenForEvent("explosion",onexplode)
    local manager=TheWorld.components.dockmanager
    local original=manager and manager.DamageDockAtPoint
    if manager then manager.DamageDockAtPoint=function() docks=docks+1 end end
    require("nw/explosions").hit(owner,{flags={explosive_hit=D.explosion}},x-8,z)
    if manager then manager.DamageDockAtPoint=original end
    TheWorld:RemoveEventCallback("explosion",onexplode)
    assert(lab:IsValid() and lab.components.workable.workleft==labwork and lab.components.burnable:IsBurning(),"NW_WEAPONS: structure protected but ignited")
    assert(wall.components.health.currenthealth==wallhealth and boat.components.health.currenthealth==boathealth and events==0 and docks==0,"NW_WEAPONS: wall/boat/dock protection")
    lab:Remove();wall:Remove();boat:Remove()
    -- Straight lance motion must remain at its native motor speed, without
    -- repeated physical bounces or forced horizontal position writes.
    local lance=shot("edge_yoth_lance",0,12)
    local lx,_,lz=lance.Transform:GetWorldPosition()
    local corrections=0
    local flight=require("nw/flight")
    local ground=flight.ground
    flight.ground=function(inst,px,py,pz)
        if inst==lance and math.abs(py)>.0001 then corrections=corrections+1 end
        return ground(inst,px,py,pz)
    end
    local shield=shot("edge_shieldofterror")
    local sx,_,sz=shield.Transform:GetWorldPosition()
    -- Native physics object methods are not writable; movement is checked after
    -- several real server ticks, alongside unit coverage forbidding Teleport.
    TheWorld:DoTaskInTime(.4,function()
        flight.ground=ground
        assert(lance:IsValid(),"NW_WEAPONS: lance disappeared on empty ground")
        local ex,ey,ez=lance.Transform:GetWorldPosition()
        assert(ex-lx>5 and ex-lx<9 and math.abs(ez-lz)<.05 and math.abs(ey)<.001 and corrections==0,
            "NW_WEAPONS: lance straight flight needs no height corrections")
        assert(shield:IsValid(),"NW_WEAPONS: orbit shield lifetime")
        local ex,_,ez=shield.Transform:GetWorldPosition()
        local ox,_,oz=owner.Transform:GetWorldPosition()
        assert((ex-sx)^2+(ez-sz)^2>1 and math.abs(math.sqrt((ex-ox)^2+(ez-oz)^2)-2)<.4,"NW_WEAPONS: continuous native orbit")
        for _,e in ipairs(made) do if e:IsValid() then e:Remove() end end
        M.passed=true
        print("NW_WEAPONS_PASS: flame followers, cooking stacks/ignition/absorption, all aimed arcs, continuous return/orbit, structure/boat/dock protection")
    end)
end
return M
