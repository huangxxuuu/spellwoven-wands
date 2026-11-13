-- Server-owned, short-lived creature-control regions. No player/light hooks.
local M={radius=2,min_duration=3,max_duration=5,interval=.1,overlap=.3,
    per_owner=128,world_limit=384,fade_duration=.4}
-- World startup only. Fog is transient and is never restored from a save.
function M.install(env)
    M.effects_disabled=env.GetModConfigData("disable_dark_fog")==true
    if not M.effects_disabled then
        require("nw/dark_fog_boss").install(env.AddComponentPostInit,env.AddStategraphPostInit,env.AddPrefabPostInit)
    end
end
local CELL=4
local Size=require("nw/projectile_size")
local EXCLUDE={"INLIMBO","FX","DECOR","player","playerghost"}
local INCLUDE={"_combat","locomotor","smallcreature","largecreature","shadowcreature"}
local function now() return GetTime() end
local function valid(e) return e and e:IsValid() end
local function key(x,z) return math.floor(x/CELL)..":"..math.floor(z/CELL) end
local function radius(p) return M.radius*Size.factor(p) end
local function mergekey(owner,x,z,r)
    -- Small clouds must not disappear into the old one-unit merge buckets.
    local width=math.min(1,r/2)
    return owner..":"..tostring(r)..":"..math.floor(x/width+.5)..":"..math.floor(z/width+.5)
end
local function control() return require("nw/dark_fog_control") end
local function unregister(world,source)
    local pool=world and world._nw_dark_fog
    local rec=pool and pool.sources[source]
    if not rec then return end
    pool.sources[source]=nil;pool.count=pool.count-1
    pool.large[source]=nil
    pool.owners[rec.owner]=(pool.owners[rec.owner] or 1)-1
    local cell=pool.cells[rec.cell]
    if cell then
        cell.sources[source]=nil
        if next(cell.sources)==nil then pool.cells[rec.cell]=nil
        elseif rec.radius==cell.radius then
            cell.radius=0
            for other in pairs(cell.sources) do cell.radius=math.max(cell.radius,pool.sources[other].radius) end
        end
    end
    if pool.merge[rec.merge]==source then pool.merge[rec.merge]=nil end
    if source._nw_dark_expiry then source._nw_dark_expiry:Cancel();source._nw_dark_expiry=nil end
    if source._nw_dark_release then source._nw_dark_release();source._nw_dark_release=nil end
    pool.dirty=true
end
function M.contains(world,inst)
    if M.effects_disabled then return false end
    local pool=world and world._nw_dark_fog
    if not pool or not valid(inst) or inst:HasTag("player") or inst:HasTag("playerghost") then return false end
    local x,_,z=inst.Transform:GetWorldPosition()
    local cx,cz=math.floor(x/CELL),math.floor(z/CELL)
    for ix=cx-1,cx+1 do for iz=cz-1,cz+1 do
        local cell=pool.cells[ix..":"..iz]
        for source in pairs(cell and cell.sources or {}) do
            local rec=pool.sources[source]
            if rec and rec.radius<=CELL and valid(source) and not source._nw_dark_inactive
                and (rec.x-x)^2+(rec.z-z)^2<=rec.radius^2 then return true end
        end
    end end
    -- Giant multipliers are unbounded; do not expand their area into grid cells.
    -- This fallback is bounded by the existing world entity cap instead.
    for source in pairs(pool.large) do
        local rec=pool.sources[source]
        if rec and valid(source) and not source._nw_dark_inactive
            and (rec.x-x)^2+(rec.z-z)^2<=rec.radius^2 then return true end
    end
    return false
end
function M.refresh(world)
    local pool=world and world._nw_dark_fog
    if not pool then return end
    if pool.refreshing then pool.dirty=true;return end
    pool.refreshing=true;pool.dirty=false
    local members={}
    if not M.effects_disabled then
    for _,cell in pairs(pool.cells) do
        for _,inst in ipairs(TheSim:FindEntities(cell.x,0,cell.z,cell.radius+CELL/math.sqrt(2),nil,EXCLUDE,INCLUDE)) do
            if not members[inst] and valid(inst) and not inst:IsInLimbo()
                and not inst:IsAsleep() and control().classify(inst) then
                local x,_,z=inst.Transform:GetWorldPosition()
                for source in pairs(cell.sources) do
                    local rec=pool.sources[source]
                    if rec and (rec.x-x)^2+(rec.z-z)^2<=rec.radius^2 then members[inst]=true;break end
                end
            end
        end
    end
    end
    local time=now()
    for inst in pairs(members) do control().update(inst,time,true) end
    for inst in pairs(pool.members) do if not members[inst] then control().leave(inst) end end
    pool.members=members;pool.refreshing=false
    if pool.count==0 then
        for inst in pairs(members) do control().leave(inst) end
        pool.members={}
        if pool.task then pool.task:Cancel() end
        world:RemoveEventCallback("onremove",pool.onremove)
        world._nw_dark_fog=nil
    elseif pool.dirty then M.refresh(world) end
end
function M.dissipate(source)
    if not valid(source) or source._nw_dark_inactive then return false end
    source._nw_dark_inactive=true
    local world=source._nw_dark_world
    unregister(world,source)
    if source._nw_dark_dissipating then source._nw_dark_dissipating:set(true) end
    if source._nw_dark_visuals then require("nw/dark_fog_visual").dissipate(source) end
    source:DoTaskInTime(M.fade_duration+.2,source.Remove)
    M.refresh(world)
    return true
end
-- Only approved boss attack adapters call this; clouds never become targets.
local function retire(world,pool,hits)
    -- Batch removal so overlapping sources do not briefly release/reapply AI.
    local was_refreshing=pool.refreshing;pool.refreshing=true
    for _,source in ipairs(hits) do M.dissipate(source) end
    pool.refreshing=was_refreshing
    M.refresh(world)
    return #hits
end
local function segment_distance_sq(px,pz,ax,az,bx,bz)
    local dx,dz=bx-ax,bz-az
    local length=dx*dx+dz*dz
    local t=length>0 and math.max(0,math.min(1,((px-ax)*dx+(pz-az)*dz)/length)) or 0
    return (px-ax-dx*t)^2+(pz-az-dz*t)^2
end
function M.disperse_circle(world,x,z,outer,inner)
    local pool=world and world._nw_dark_fog
    if not pool then return 0 end
    inner=math.max(0,inner or 0);outer=math.max(0,outer or 0)
    local hits={}
    for source,rec in pairs(pool.sources) do
        local d=math.sqrt((rec.x-x)^2+(rec.z-z)^2)
        if d<=outer+rec.radius and d+rec.radius>=inner then hits[#hits+1]=source end
    end
    return retire(world,pool,hits)
end
-- rotation/arc use DST degrees; +rotation turns toward -Z. The origin has
-- already been offset by the native attack, not by the fog radius.
function M.disperse_sector(world,x,z,radius,rotation,arc)
    local pool=world and world._nw_dark_fog
    if not pool then return 0 end
    radius=math.max(0,radius)
    local half=math.max(0,math.min(180,arc/2))*math.pi/180
    local angle=-rotation*math.pi/180
    local fx,fz=math.cos(angle),math.sin(angle)
    local ax,az=radius*math.cos(angle-half),radius*math.sin(angle-half)
    local bx,bz=radius*math.cos(angle+half),radius*math.sin(angle+half)
    local hits={}
    for source,rec in pairs(pool.sources) do
        local dx,dz=rec.x-x,rec.z-z
        local d=math.sqrt(dx*dx+dz*dz)
        if d<=radius+rec.radius then
            local inside=math.abs(math.atan2(fx*dz-fz*dx,fx*dx+fz*dz))<=half
            local distance=inside and math.max(0,d-radius)^2 or math.min(
                segment_distance_sq(dx,dz,0,0,ax,az),segment_distance_sq(dx,dz,0,0,bx,bz))
            if distance<=rec.radius^2 then hits[#hits+1]=source end
        end
    end
    return retire(world,pool,hits)
end
-- Native DoArcAttack clips a disk by a forward-plane threshold rather than
-- testing an angle. At 180 degrees this matches a sector; at 240 it does not.
function M.disperse_arc(world,x,z,radius,rotation,arc)
    local pool=world and world._nw_dark_fog
    if not pool then return 0 end
    radius=math.max(0,radius or 0)
    local heading=(rotation or 0)*math.pi/180
    local fx,fz=math.cos(heading),-math.sin(heading)
    local cutoff=radius*math.cos(math.max(0,math.min(360,arc or 360))*math.pi/360)
    local halfchord=math.sqrt(math.max(0,radius*radius-cutoff*cutoff))
    local hits={}
    for source,rec in pairs(pool.sources) do
        local dx,dz=rec.x-x,rec.z-z
        local u,v=dx*fx+dz*fz,-dx*fz+dz*fx
        local distance=math.sqrt(u*u+v*v)
        local dsq
        if u>=cutoff and distance<=radius then
            dsq=0
        elseif distance>0 and u*radius/distance>=cutoff then
            dsq=math.max(0,distance-radius)^2
        else
            local nearest=math.max(-halfchord,math.min(halfchord,v))
            dsq=(u-cutoff)^2+(v-nearest)^2
        end
        if dsq<=rec.radius^2 then hits[#hits+1]=source end
    end
    return retire(world,pool,hits)
end
-- Native lunar fissures use a world-axis rectangle, including its corners.
function M.disperse_box(world,x,z,halfwidth,halfheight)
    local pool=world and world._nw_dark_fog
    if not pool then return 0 end
    halfwidth,halfheight=math.max(0,halfwidth or 0),math.max(0,halfheight or 0)
    local hits={}
    for source,rec in pairs(pool.sources) do
        local dx=math.max(0,math.abs(rec.x-x)-halfwidth)
        local dz=math.max(0,math.abs(rec.z-z)-halfheight)
        if dx*dx+dz*dz<=rec.radius^2 then hits[#hits+1]=source end
    end
    return retire(world,pool,hits)
end
-- Sweep the boss's actual body disk over accepted movement. This does not
-- turn the body into an attack or alter any native collision/damage behavior.
function M.disperse_path(world,ax,az,bx,bz,body_radius)
    local pool=world and world._nw_dark_fog
    if not pool then return 0 end
    body_radius=math.max(0,body_radius or 0)
    local hits={}
    for source,rec in pairs(pool.sources) do
        if segment_distance_sq(rec.x,rec.z,ax,az,bx,bz)<=(body_radius+rec.radius)^2 then
            hits[#hits+1]=source
        end
    end
    return retire(world,pool,hits)
end
function M.register(source,owner,lifetime,p)
    local world=TheWorld
    if not valid(source) or not world or not world.ismastersim then return end
    local pool=world._nw_dark_fog
    if not pool then
        pool={sources={},members={},cells={},large={},owners={},merge={},count=0,serial=0}
        world._nw_dark_fog=pool
        if not M.effects_disabled then
            pool.task=world:DoPeriodicTask(M.interval,function() M.refresh(world) end)
        end
        pool.onremove=function()
            if world._nw_dark_fog==pool then
                for inst in pairs(pool.members) do control().leave(inst) end
                pool.members={}
                if pool.task then pool.task:Cancel() end
                world._nw_dark_fog=nil
            end
        end
        world:ListenForEvent("onremove",pool.onremove)
    end
    if pool.sources[source] then return source end
    local x,_,z=source.Transform:GetWorldPosition()
    local ownerkey=require("nw/entity_limits").key(owner)
    local r=radius(p)
    local cellkey=key(x,z)
    local merge=mergekey(ownerkey,x,z,r)
    lifetime=math.max(M.min_duration,math.min(M.max_duration,lifetime or M.min_duration+math.random()*(M.max_duration-M.min_duration)))
    pool.serial=pool.serial+1
    pool.sources[source]={owner=ownerkey,x=x,z=z,radius=r,cell=cellkey,merge=merge,order=pool.serial,expires=now()+lifetime}
    if r>CELL then pool.large[source]=true end
    pool.merge[merge]=source;pool.count=pool.count+1;pool.owners[ownerkey]=(pool.owners[ownerkey] or 0)+1
    local cell=pool.cells[cellkey]
    if not cell then cell={x=(math.floor(x/CELL)+.5)*CELL,z=(math.floor(z/CELL)+.5)*CELL,radius=0,sources={}};pool.cells[cellkey]=cell end
    cell.radius=math.max(cell.radius,r)
    cell.sources[source]=true;source._nw_dark_world=world
    if source._nw_dark_radius then source._nw_dark_radius:set(r) end
    source:ListenForEvent("onremove",function() unregister(world,source);M.refresh(world) end)
    source._nw_dark_expiry=source:DoTaskInTime(lifetime,function() M.dissipate(source) end)
    local oldest
    local own_over=pool.owners[ownerkey]>M.per_owner
    if own_over or pool.count>M.world_limit then
        for e,rec in pairs(pool.sources) do
            if e~=source and (not own_over or rec.owner==ownerkey)
                and (not oldest or rec.order<pool.sources[oldest].order) then oldest=e end
        end
        if oldest then
            -- Burst eviction must not rescan the world once per new cloud.
            local was_refreshing=pool.refreshing;pool.refreshing=true
            M.dissipate(oldest)
            pool.refreshing=was_refreshing
        end
    end
    -- Registration shares the world's next scan rather than scanning per puff.
    return source
end
function M.leave(owner,x,z,p)
    if not TheWorld or not TheWorld.ismastersim then return end
    local Budget=require("nw/entity_limits")
    local pool=TheWorld._nw_dark_fog
    local ownerkey=Budget.key(owner)
    local time=now()
    if pool then
        local old=pool.merge[mergekey(ownerkey,x,z,radius(p))]
        local rec=old and pool.sources[old]
        if rec and rec.expires>time+.5 then return old end
        -- Bound new network entities during unlimited multishot bursts.
        local window=math.floor(time/M.interval)
        if pool.spawn_window~=window then pool.spawn_window=window;pool.spawn_count=0;pool.spawn_owners={} end
        if pool.spawn_count>=32 or (pool.spawn_owners[ownerkey] or 0)>=16 then return end
    end
    local release=Budget.acquire(owner,"fields")
    if not release then return end
    local fog=SpawnPrefab("nw_dark_fog")
    if not fog then release();return end
    fog.Transform:SetPosition(x,0,z)
    fog._nw_dark_release=release;Budget.bind(fog,release)
    M.register(fog,owner,nil,p)
    pool=TheWorld._nw_dark_fog
    if pool then
        local window=math.floor(time/M.interval)
        if pool.spawn_window~=window then pool.spawn_window=window;pool.spawn_count=0;pool.spawn_owners={} end
        pool.spawn_count=pool.spawn_count+1;pool.spawn_owners[ownerkey]=(pool.spawn_owners[ownerkey] or 0)+1
    end
    return fog
end
function M.attach(inst,owner,p)
    if not (p and p.flags and p.flags.dark) or inst._nw_dark_trail then return end
    inst._nw_dark_trail={distance=0}
    local x,_,z=inst.Transform:GetWorldPosition()
    return M.leave(owner,x,z,p)
end
-- Feed only accepted collision segments, never the untrimmed physics endpoint.
function M.trail(inst,s,x,z,nx,nz,continuous)
    if not (s and s.p and s.p.flags and s.p.flags.dark) then return end
    local state=inst._nw_dark_trail
    if not state then state={distance=0};inst._nw_dark_trail=state;M.leave(s.owner,x,z,s.p) end
    -- Adjacent clouds overlap by 30% of their diameter at every spell size.
    local spacing=2*radius(s.p)*(1-M.overlap)
    if state.spacing and state.spacing~=spacing then state.distance=0 end
    state.spacing=spacing
    local dx,dz=nx-x,nz-z
    local length=math.sqrt(dx*dx+dz*dz)
    if length<=.00001 then return end
    -- Discontinuous teleports must not lay fog across the intervening world.
    if length>16 and not continuous then state.distance=0;M.leave(s.owner,nx,nz,s.p);return end
    local distance=spacing-state.distance
    while distance<=length+.000001 do
        local t=math.min(1,distance/length)
        local fog=M.leave(s.owner,x+dx*t,z+dz*t,s.p)
        -- Confirmed lightning segments may be arbitrarily long after scaling.
        -- Once creation is refused, later samples share the same exhausted
        -- budget/window; existing clouds need no refresh (merging never renews).
        if continuous and not fog then break end
        distance=distance+spacing
    end
    state.distance=(state.distance+length)%spacing
end
return M
