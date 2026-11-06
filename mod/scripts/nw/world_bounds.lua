-- Only explicitly registered spell instances are cleaned up. Sleeping saved
-- placements are checked too; world objects and player structures are untouched.
local Limits=require("nw/spell_limits")
local M={}
local MARGIN=5
local wall_tiles
local function playable(map,x,z) return map:IsAboveGroundAtPoint(x,0,z,true) end

function M.outside(x,z)
    if not Limits.boundary_cleanup then return false end
    local map=TheWorld and TheWorld.Map
    if not map or not map.IsAboveGroundAtPoint then return false end
    if playable(map,x,z) then return false end
    if not wall_tiles then
        wall_tiles={}
        for name,id in pairs(GROUND or {}) do
            if name:sub(1,5)=="WALL_" then wall_tiles[id]=true end
        end
    end
    local tile=map:GetTileAtPoint(x,0,z)
    -- Same world rule as the native impassable terrain collision set.
    if wall_tiles[tile] or TheWorld.CanFlyingCrossBarriers and not TheWorld:CanFlyingCrossBarriers()
        and map:IsImpassableTileAtPoint(x,0,z) then return true end
    -- Shortest distance to land/ocean tile squares, not time or path length
    -- spent outside. Ordinary coastlines remain inside this valid union.
    local scale=TILE_SCALE or 4
    local tx,tz=map:GetTileCoordsAtPoint(x,0,z)
    local reach=math.ceil(MARGIN/scale)+1
    local w,h=map:GetSize()
    for ix=math.max(0,tx-reach),math.min(w-1,tx+reach) do
        for iz=math.max(0,tz-reach),math.min(h-1,tz+reach) do
            local cx,_,cz=map:GetTileCenterPoint(ix,iz)
            local dx,dz=math.max(0,math.abs(cx-x)-scale/2),math.max(0,math.abs(cz-z)-scale/2)
            if dx*dx+dz*dz<MARGIN*MARGIN and playable(map,cx,cz) then return false end
        end
    end
    return true
end

function M.clip(x,z,nx,nz)
    if not Limits.boundary_cleanup then return end
    if M.outside(x,z) then return 0 end
    local dx,dz=nx-x,nz-z
    local steps=math.max(1,math.ceil(math.sqrt(dx*dx+dz*dz)*2))
    for i=1,steps do
        local hi=i/steps
        if M.outside(x+dx*hi,z+dz*hi) then
            local lo=(i-1)/steps
            for _=1,10 do
                local mid=(lo+hi)/2
                if M.outside(x+dx*mid,z+dz*mid) then hi=mid else lo=mid end
            end
            return lo
        end
    end
end

local function tick(world)
    local pool=world._nw_boundary_entities
    for inst,previous in pairs(pool.items) do
        if inst:IsValid() then
            local x,_,z=inst.Transform:GetWorldPosition()
            if x~=previous.x or z~=previous.z then
                if M.clip(previous.x,previous.z,x,z) then inst:Remove()
                else previous.x,previous.z=x,z end
            end
        end
    end
end

function M.watch(inst)
    if not Limits.boundary_cleanup or inst._nw_boundary_watched
        or not TheWorld.Map or not TheWorld.Map.IsAboveGroundAtPoint then return true end
    local x,_,z=inst.Transform:GetWorldPosition()
    if M.outside(x,z) then inst:Remove();return false end
    inst._nw_boundary_watched=true
    local pool=TheWorld._nw_boundary_entities
    if not pool then pool={items={}};TheWorld._nw_boundary_entities=pool end
    pool.items[inst]={x=x,z=z}
    inst:ListenForEvent("onremove",function()
        pool.items[inst]=nil
        if not next(pool.items) and pool.task then pool.task:Cancel();pool.task=nil end
    end)
    if not pool.task then pool.task=TheWorld:DoPeriodicTask(FRAMES,tick) end
    return true
end
return M
