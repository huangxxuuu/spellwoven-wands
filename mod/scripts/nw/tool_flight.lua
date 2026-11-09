-- Client-only native tool artwork and a distance-sampled orange orb trail.
local M={}
local Budget=require("nw/trail_budget")
local BANK="nw_tool_flight"
local FRAME=1/30
local TAU=2*math.pi
local DIRECTIONS=128
local supported={fishingrod=true,oceanfishingrod=true,trident=true,farm_hoe=true,yoth_lance=true,orange_bolt=true}
local animation_period={orange_bolt=.2,oceanfishingrod=8/30}
local SHOT_PARTS,MAX_BIRTHS=128,32

local function visible(inst)
    while inst do
        if not inst:IsValid() or not inst.entity:IsVisible() then return false end
        inst=inst.entity:GetParent()
    end
    return true
end

function M.resolve(id) return id=="orangestaff" and "orange_bolt" or id end
function M.supports(id) return supported[M.resolve(id)]==true end
function M.trail_timing(scale) return math.min(.85,.34*math.sqrt(math.max(1,scale))) end
function M.trail_spacing(scale) return .14*math.max(1,scale) end
function M.project(dx,dy,dz,heading,pitch)
    local c,s=math.cos(heading),math.sin(heading)
    return math.atan2((dx*c+dz*s)*math.sin(pitch)-dy*math.cos(pitch),dz*c-dx*s)
end
function M.direction_bin(angle) return math.floor(angle/TAU*DIRECTIONS+.5)%DIRECTIONS end

local function direction(dx,dy,dz)
    local camera=TheCamera
    return M.direction_bin(M.project(dx,dy,dz,(camera and camera.heading or 0)*DEGREES,
                                    (camera and camera.pitch or 35)*DEGREES))
end
local function position(inst)
    local x,y,z=inst.Transform:GetWorldPosition()
    return x,y+inst._height:value(),z
end
local function head(s,now)
    local dir=direction(s.dx,s.dy,s.dz)
    if dir~=s.direction then
        s.direction=dir
        s.visual.AnimState:PlayAnimation(s.id.."_dir_"..dir,true)
        local period=animation_period[s.id]
        if period then s.visual.AnimState:SetTime(math.max(0,(now-s.started+s.phase)%period)) end
    end
end
local function release(part)
    if part.fx:IsValid() then part.fx:Remove() end
    part.owner.parts[part.slot]=nil
    part.pool.count=part.pool.count-1
end
local function discard(pool,s,index)
    local part=s.parts[index]
    if part then Budget.remove(part) end
end
local function face_tail(part,now)
    local dir=direction(part.dx,part.dy,part.dz)
    if dir~=part.direction then
        part.direction=dir
        part.fx.AnimState:PlayAnimation("orange_bolt_tail_dir_"..dir,false)
        part.fx.AnimState:SetTime(math.max(0,now-part.born)*.2/part.life)
        part.fx.AnimState:SetDeltaTimeMultiplier(.2/part.life)
    end
end
local function emit(pool,s,x,y,z,dx,dy,dz,born,now)
    if not Budget.can_emit(s.inst) then return end
    local index=s.next
    local part=s.parts[index]
    if not part then
        local fx=CreateEntity()
        fx.entity:AddTransform();fx.entity:AddAnimState();fx.entity:SetCanSleep(false)
        fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
        fx.AnimState:SetBank(BANK);fx.AnimState:SetBuild(BANK)
        fx.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
        fx.AnimState:SetLightOverride(1)
        part={fx=fx};s.parts[index]=part;pool.count=pool.count+1
    end
    s.next=index%SHOT_PARTS+1
    part.fx.Transform:SetPosition(x,y,z)
    part.fx.Transform:SetScale(s.scale,s.scale,s.scale)
    part.dx,part.dy,part.dz=dx,dy,dz
    part.born,part.life,part.direction=born,M.trail_timing(s.scale),nil
    part.owner,part.slot,part.pool=s,index,pool
    Budget.track(part,born,release)
    face_tail(part,now)
end
local function trail(pool,s,x,y,z,dx,dy,dz,distance,now)
    local offset=.28*s.scale/distance
    local ax,ay,az=x-dx*offset,y-dy*offset,z-dz*offset
    local spacing=M.trail_spacing(s.scale)
    local path=s.path
    if not path then
        path={x=s.x-dx*offset,y=s.y-dy*offset,z=s.z-dz*offset,time=s.time,carry=spacing}
        s.path=path
    end
    local vx,vy,vz=ax-path.x,ay-path.y,az-path.z
    local length=math.sqrt(vx*vx+vy*vy+vz*vz)
    if length>.000001 then
        local count=math.floor((path.carry+length+.000001)/spacing)
        if count>MAX_BIRTHS then
            emit(pool,s,ax,ay,az,dx,dy,dz,now,now);path.carry=0
        else
            local travelled=spacing-path.carry
            while travelled<=length+.000001 do
                local t=math.max(0,math.min(1,travelled/length))
                emit(pool,s,path.x+vx*t,path.y+vy*t,path.z+vz*t,vx,vy,vz,
                     path.time+(now-path.time)*t,now)
                travelled=travelled+spacing
            end
            path.carry=path.carry+length-count*spacing
        end
    end
    path.x,path.y,path.z,path.time=ax,ay,az,now
end
local function update(pool,s,now)
    local inst=s.inst
    local alive=inst and inst:IsValid() and s.visual:IsValid()
    if alive then
        local x,y,z=position(inst)
        local scale=math.max(1,inst._size:value())
        if scale~=s.scale then s.scale=scale;s.path=nil end
        local dx,dy,dz=x-s.x,y-s.y,z-s.z
        local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
        local dt=now-s.time
        local continuous=dt>0 and dt<=.25 and distance>.0001
            and distance<=math.max(60,s.speed or 0)*dt*2+.1
        if continuous then
            s.dx,s.dy,s.dz=dx,dy,dz
            s.speed=distance/dt
            if s.id=="orange_bolt" then
                if visible(s.visual) and visible(inst) then trail(pool,s,x,y,z,dx,dy,dz,distance,now)
                else s.path=nil end
            end
        else
            s.path=nil
            if distance>1 then
                local angle=-inst.Transform:GetRotation()*DEGREES
                s.dx,s.dy,s.dz=math.cos(angle),0,math.sin(angle)
            end
            s.speed=0
        end
        head(s,now)
        s.x,s.y,s.z,s.time=x,y,z,now
    end
    local remaining=false
    for index,part in pairs(s.parts) do
        if now-part.born>=part.life-.00001 or not part.fx:IsValid() then discard(pool,s,index)
        else face_tail(part,now);remaining=true end
    end
    return alive or remaining
end
local function stop_pool(pool)
    if pool.closed then return end
    pool.closed=true
    pool.task:Cancel()
    pool.world:RemoveEventCallback("onremove",pool.onremove)
    if pool.world._nw_tool_flights==pool then pool.world._nw_tool_flights=nil end
end
local function tick(world)
    local pool=world._nw_tool_flights
    if not pool then return end
    local now=GetTime()
    for index=#pool.shots,1,-1 do
        if not update(pool,pool.shots[index],now) then
            pool.shots[index]=pool.shots[#pool.shots];pool.shots[#pool.shots]=nil
        end
    end
    if #pool.shots==0 then stop_pool(pool) end
end
function M.detach(inst,immediate)
    local s=inst._nw_tool_flight
    if not s then return end
    inst:RemoveEventCallback("onremove",s.onremove)
    inst._nw_tool_flight=nil;s.inst=nil
    if immediate or next(s.parts)==nil then
        for index in pairs(s.parts) do discard(s.pool,s,index) end
        local pool=s.pool
        for index=#pool.shots,1,-1 do
            if pool.shots[index]==s then
                pool.shots[index]=pool.shots[#pool.shots];pool.shots[#pool.shots]=nil;break
            end
        end
        if #pool.shots==0 then stop_pool(pool) end
    end
end
function M.attach(inst,id)
    id=M.resolve(id)
    if not supported[id] or not inst._visual or TheNet:IsDedicated() then return end
    if inst._nw_tool_flight then
        if inst._nw_tool_flight.id==id then return end
        M.detach(inst,true)
    end
    local visual=inst._visual
    visual.AnimState:SetBank(BANK);visual.AnimState:SetBuild(BANK)
    visual.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
    local world=TheWorld
    local pool=world._nw_tool_flights
    if not pool then
        pool={shots={},count=0,world=world};world._nw_tool_flights=pool
        pool.task=world:DoPeriodicTask(FRAME,tick)
        pool.onremove=function()
            for index=#pool.shots,1,-1 do
                local shot=pool.shots[index]
                if shot.inst then M.detach(shot.inst,true)
                else for slot in pairs(shot.parts) do discard(pool,shot,slot) end end
            end
            pool.shots={};stop_pool(pool)
        end
        world:ListenForEvent("onremove",pool.onremove)
    end
    local x,y,z=position(inst)
    local angle=-inst.Transform:GetRotation()*DEGREES
    local now=GetTime()
    local s={inst=inst,visual=visual,id=id,pool=pool,x=x,y=y,z=z,dx=math.cos(angle),dy=0,dz=math.sin(angle),
             time=now,started=now,phase=((inst.GUID or 0)%6)*FRAME,scale=math.max(1,inst._size:value()),
             parts={},next=1}
    s.onremove=function() M.detach(inst) end
    inst:ListenForEvent("onremove",s.onremove)
    inst._nw_tool_flight=s;pool.shots[#pool.shots+1]=s
    head(s,now)
end
return M
