-- Narrow synchronous adapter for native callbacks with a hard-coded area.
-- Only this Lua function sees the proxy; never replace the world's TheSim or
-- mutate TUNING. Restore its environment even when a callback raises an error.
local M={}
function M.call(fn,scale,radius,x,z,...)
    if scale>=1 then return fn(...) end
    local env=getfenv(fn)
    local sim=env.TheSim
    local proxy=setmetatable({FindEntities=function(_,px,py,pz,r,...)
        if r==radius and math.abs(px-x)<.0001 and math.abs(pz-z)<.0001 then r=r*scale end
        return sim:FindEntities(px,py,pz,r,...)
    end},{__index=function(_,key)
        local value=sim[key]
        if type(value)=="function" then return function(_,...) return value(sim,...) end end
        return value
    end})
    setfenv(fn,setmetatable({TheSim=proxy},{__index=env,__newindex=env}))
    local result={pcall(fn,...)}
    setfenv(fn,env)
    if not result[1] then error(result[2],0) end
    return unpack(result,2)
end
-- Native trident's ocean splash also creates boat leaks at a fixed ring.
-- Filtering creature hits alone would leave those leaks outside a shrunk cast.
-- Keep native target handling and boat interactions, scaling their positions.
function M.trident(inst,owner,position,scale)
    local x,y,z=position:Get()
    for _,e in ipairs(TheSim:FindEntities(x,y,z,TUNING.TRIDENT.SPELL.RADIUS*scale,nil,{"INLIMBO","outofreach","DECOR"})) do
        if e:IsOnOcean(false) then inst:DoWaterExplosionEffect(e,owner,position) end
    end
    local angle=GetRandomWithVariance(-45,20)
    local radius=TUNING.TRIDENT.SPELL.RADIUS*.65*scale
    for _=1,4 do
        angle=angle+90
        local dx,dz=radius*math.cos(angle*DEGREES),-radius*math.sin(angle*DEGREES)
        local ox,oz=x+dx,z+dz
        if TheWorld.Map:IsOceanTileAtPoint(ox,y,oz) and not TheWorld.Map:IsVisualGroundAtPoint(ox,y,oz) then
            local boat=TheWorld.Map:GetPlatformAtPoint(ox,oz)
            if boat then
                local bx,_,bz=boat.Transform:GetWorldPosition()
                local lx,lz=ox,oz
                if bx~=ox or bz~=oz then
                    local nx,nz=VecUtil_Normalize(bx-ox,bz-oz)
                    lx,lz=ox+.5*scale*nx,oz+.5*scale*nz
                end
                boat:PushEvent("spawnnewboatleak",{pt=Vector3(lx,y,lz),leak_size="med_leak",playsoundfx=true})
                if boat.components.boatphysics then boat.components.boatphysics:ApplyForce(dx,dz,1) end
            else
                local fx=SpawnPrefab("crab_king_waterspout")
                fx.Transform:SetPosition(ox,y,oz)
                require("nw/projectile_size").visual(fx,scale)
            end
        end
    end
    local ox,oy,oz=owner.Transform:GetWorldPosition()
    for _,e in ipairs(TheSim:FindEntities(ox,oy,oz,TUNING.TRIDENT_FARM_PLANT_INTERACT_RANGE*scale,{"tendable_farmplant"})) do
        if e.components.farmplanttendable then e.components.farmplanttendable:TendTo(owner) end
    end
    inst.components.finiteuses:Use(TUNING.TRIDENT.USES/TUNING.TRIDENT.SPELL.USE_COUNT)
end
return M
