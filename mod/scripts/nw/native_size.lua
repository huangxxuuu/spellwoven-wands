local C=require("nw/constants/native_effects")
local M={}
function M.filtered(fn,scale,radius,x,z,accept,...)
    if scale>=1 and not accept then return fn(...) end
    local env=getfenv(fn)
    local sim=env.TheSim
    local proxy=setmetatable({FindEntities=function(_,px,py,pz,r,...)
        local area=r==radius and math.abs(px-x)<C.area_epsilon and math.abs(pz-z)<C.area_epsilon
        if area and scale<1 then r=r*scale end
        local found=sim:FindEntities(px,py,pz,r,...)
        if not area or not accept then return found end
        local selected={}
        for _,e in ipairs(found) do if accept(e) then selected[#selected+1]=e end end
        return selected
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
function M.call(fn,scale,radius,x,z,...)
    return M.filtered(fn,scale,radius,x,z,nil,...)
end
function M.trident(inst,owner,position,scale,p)
    local x,y,z=position:Get()
    for _,e in ipairs(TheSim:FindEntities(x,y,z,TUNING.TRIDENT.SPELL.RADIUS*scale,nil,{"INLIMBO","outofreach","DECOR"})) do
        if e:IsOnOcean(false) and require("nw/native_targeting").accepts(owner,e,p) then inst:DoWaterExplosionEffect(e,owner,position) end
    end
    local angle=GetRandomWithVariance(C.trident.start_angle,C.trident.angle_variance)
    local radius=TUNING.TRIDENT.SPELL.RADIUS*C.trident.radius_factor*scale
    for _=1,C.trident.spouts do
        angle=angle+C.trident.angle_step
        local dx,dz=radius*math.cos(angle*DEGREES),-radius*math.sin(angle*DEGREES)
        local ox,oz=x+dx,z+dz
        if TheWorld.Map:IsOceanTileAtPoint(ox,y,oz) and not TheWorld.Map:IsVisualGroundAtPoint(ox,y,oz) then
            local boat=TheWorld.Map:GetPlatformAtPoint(ox,oz)
            if boat and require("nw/native_targeting").accepts(owner,boat,p) then
                local bx,_,bz=boat.Transform:GetWorldPosition()
                local lx,lz=ox,oz
                if bx~=ox or bz~=oz then
                    local nx,nz=VecUtil_Normalize(bx-ox,bz-oz)
                    lx,lz=ox+C.trident.leak_offset*scale*nx,oz+C.trident.leak_offset*scale*nz
                end
                boat:PushEvent("spawnnewboatleak",{pt=Vector3(lx,y,lz),leak_size="med_leak",playsoundfx=true})
                if boat.components.boatphysics then boat.components.boatphysics:ApplyForce(dx,dz,C.trident.boat_force) end
            elseif not boat then
                local fx=SpawnPrefab("crab_king_waterspout")
                fx.Transform:SetPosition(ox,y,oz)
                require("nw/projectile_size").visual(fx,scale)
            end
        end
    end
    local ox,oy,oz=owner.Transform:GetWorldPosition()
    for _,e in ipairs(TheSim:FindEntities(ox,oy,oz,TUNING.TRIDENT_FARM_PLANT_INTERACT_RANGE*scale,{"tendable_farmplant"})) do
        if e.components.farmplanttendable and require("nw/native_targeting").accepts(owner,e,p) then e.components.farmplanttendable:TendTo(owner) end
    end
    inst.components.finiteuses:Use(TUNING.TRIDENT.USES/TUNING.TRIDENT.SPELL.USE_COUNT)
end
return M
