local C=require("nw/constants/native").elemental
local Glow=require("nw/projectile_glow")
local M={}
local Budget=require("nw/trail_budget")
local Limits=require("nw/spell_limits")
local FRAME=1/C.frame_rate
local CLIP_TIME=C.clip_frames*FRAME
local BASE_TRAIL_LIFE=C.trail_life
local MAX_SAMPLE_DT=C.max_sample_dt
local ARROW_SLOTS=C.arrow_slots
local MAX_PATH_BIRTHS=C.max_path_births
local BANK="nw_elemental_flight"
local profiles=C.profiles

function M.resolve(id)
    if profiles[id] then return id end
    local note=id and require("nw/arsenal").notes[id]
    if type(note)=="table" and note.instrument=="ocarina" then return "soundwave" end
end

function M.supports(id) return M.resolve(id)~=nil end

function M.trail_motion(id)
    local profile=profiles[M.resolve(id)]
    if profile then return profile.drift,profile.offset end
end

function M.head_period(id)
    local profile=profiles[M.resolve(id)]
    return (profile and profile.head_frames or C.clip_frames)*FRAME/(profile and profile.head_playback or 1)
end

function M.trail_spacing(scale,id)
    scale=math.max(1,scale)
    local profile=profiles[M.resolve(id)]
    return (profile and profile.spacing or C.spacing)*scale,(profile and profile.coverage or C.coverage)*scale
end

function M.trail_timing(scale,id)
    local profile=profiles[M.resolve(id)]
    local rate=profile and profile.rate or C.rate
    local base=profile and profile.life or BASE_TRAIL_LIFE
    local maximum=profile and profile.maxlife or C.max_trail_life
    local lifetime=math.min(maximum,base*math.sqrt(math.max(1,scale)))
    if profile and profile.spatial then return lifetime,M.trail_spacing(scale,id)/C.spatial_reference_speed end
    return lifetime,lifetime/(base*rate)
end

function M.direction_count(id)
    local profile=profiles[M.resolve(id)]
    return profile and profile.directions or C.directions
end

function M.direction(heading,id)
    local count=M.direction_count(id)
    if not TheCamera then return math.floor(heading/(2*math.pi)*count+.5)%count end
    local radians=math.pi/180
    local rel=heading-TheCamera.heading*radians
    local pitch=math.sin(TheCamera.pitch*radians)
    local angle=math.atan2(math.cos(rel)*pitch,math.sin(rel))
    return math.floor(angle/(2*math.pi)*count+.5)%count
end

local function face_head(s,now,heading)
    heading=heading or s.launch_heading or -s.inst.Transform:GetRotation()*math.pi/180
    local direction=M.direction(heading,s.id)
    if direction~=s.direction then
        s.direction=direction
        s.visual.AnimState:PlayAnimation(s.id.."_dir_"..direction,true)
        s.visual.AnimState:SetDeltaTimeMultiplier(s.head_playback)
        s.visual.AnimState:SetTime(((now-s.started)*s.head_playback+s.phase)%s.head_time)
    end
end

local function new_segment()
    local fx=CreateEntity()
    fx.entity:AddTransform()
    fx.entity:AddAnimState()
    fx.entity:SetCanSleep(false)
    fx:AddTag("FX")
    fx:AddTag("NOCLICK")
    fx.persists=false
    fx.AnimState:SetBank(BANK)
    fx.AnimState:SetBuild(BANK)
    fx.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
    return {fx=fx}
end

local function face_segment(s,part,age,force)
    local direction=M.direction(part.heading,s.id)
    if force or direction~=part.direction then
        part.direction=direction
        part.fx.AnimState:PlayAnimation(s.id.."_tail_dir_"..direction)
        part.fx.AnimState:SetDeltaTimeMultiplier(part.playback)
        part.fx.AnimState:SetTime(age*part.playback)
    end
end

local function discard(part)
    part.fx:Remove()
    part.owner.parts[part.slot]=nil
    part.pool.count=part.pool.count-1
    if part.arrow then part.pool.arrow_count=part.pool.arrow_count-1 end
end

local function emit(pool,s,born,now,x,y,z,dx,dz,dt,distance,anchored)
    if not Budget.can_emit(s.inst) then return end
    local profile=profiles[s.id]
    local part=s.parts[s.next]
    if part and now-part.born<part.lifetime-C.expiry_epsilon and not profile.spatial then return end
    if not part then
        part=new_segment()
        pool.count=pool.count+1
        if profile.spatial then pool.arrow_count=pool.arrow_count+1 end
        s.parts[s.next]=part
    end
    part.owner,part.slot=s,s.next
    part.arrow=profile.spatial or false
    s.next=s.next%s.slots+1
    local scale=math.max(1,s.inst._size:value())
    part.born=born
    part.pool=pool
    Budget.track(part,born,discard)
    part.lifetime=s.lifetime
    part.playback=CLIP_TIME/part.lifetime
    local offset=anchored and 0 or profile.offset*scale
    part.x,part.y,part.z=x-offset*dx/distance,y,z-offset*dz/distance
    part.vx,part.vz=profile.drift*dx/dt,profile.drift*dz/dt
    part.heading=math.atan2(dz,dx)
    part.fx.Transform:SetScale(scale,scale,scale)
    face_segment(s,part,math.max(0,now-born),true)
end

local function path_emit(pool,s,now,x,y,z,dx,dz,dt,distance)
    local offset=profiles[s.id].offset*s.scale
    local ax,az=x-offset*dx/distance,z-offset*dz/distance
    local spacing=M.trail_spacing(s.scale,s.id)
    local path=s.path
    if not path then
        path={x=s.x-offset*dx/distance,y=y,z=s.z-offset*dz/distance,time=s.time,carry=spacing}
        s.path=path
    end
    local px,pz=ax-path.x,az-path.z
    local length=math.sqrt(px*px+pz*pz)
    if length>C.distance_epsilon then
        local births=math.floor((path.carry+length+C.distance_epsilon)/spacing)
        if births>MAX_PATH_BIRTHS then
            emit(pool,s,now,now,ax,y,az,dx,dz,dt,distance,true)
            path.carry=0
        else
            local travelled=spacing-path.carry
            while travelled<=length+C.distance_epsilon do
                local fraction=math.max(0,math.min(1,travelled/length))
                local born=path.time+(now-path.time)*fraction
                emit(pool,s,born,now,path.x+px*fraction,path.y+(y-path.y)*fraction,
                    path.z+pz*fraction,px,pz,dt,length,true)
                travelled=travelled+spacing
            end
            path.carry=path.carry+length-births*spacing
        end
    end
    path.x,path.y,path.z,path.time=ax,y,az,now
end

local function speed(inst)
    if not inst.Physics then return 0 end
    local vx,_,vz=inst.Physics:GetVelocity()
    return math.sqrt(vx*vx+vz*vz)
end

local function update(pool,s,now)
    local inst=s.inst
    local alive=not s.retired and inst:IsValid()
    if alive then
        local scale=math.max(1,inst._size:value())
        if scale~=s.scale then
            local previous=s.interval
            s.scale=scale
            s.lifetime,s.interval=M.trail_timing(scale,s.id)
            s.next_emit=now+math.max(0,s.next_emit-now)*s.interval/previous
            s.path=nil
        end
        local x,_,z=inst.Transform:GetWorldPosition()
        local dt=now-s.time
        local dx,dz=x-s.x,z-s.z
        local distance=math.sqrt(dx*dx+dz*dz)
        local velocity=speed(inst)
        local expected=math.max(velocity,s.speed)
        local continuous=dt>0 and dt<=MAX_SAMPLE_DT+C.distance_epsilon and distance>C.min_distance
            and distance<=math.max(Limits.max_speed,expected)*dt*C.continuity_speed_mult+C.continuity_padding
        if continuous then s.launch_heading=nil end
        face_head(s,now,profiles[s.id].motion_heading and continuous and math.atan2(dz,dx) or nil)
        if profiles[s.id].trail~=false and continuous and s.visual.entity:IsVisible() then
            if profiles[s.id].spatial then
                path_emit(pool,s,now,x,inst._height:value(),z,dx,dz,dt,distance)
            else
                s.next_emit=math.max(s.next_emit,now-C.catchup_intervals*s.interval+C.expiry_epsilon)
                while s.next_emit<=now+C.distance_epsilon do
                    local age=math.max(0,now-s.next_emit)
                    emit(pool,s,s.next_emit,now,x-dx*age/dt,inst._height:value(),z-dz*age/dt,dx,dz,dt,distance)
                    s.next_emit=s.next_emit+s.interval
                end
            end
        else
            s.next_emit=now+s.interval
            s.path=nil
        end
        s.speed=continuous and distance/dt or velocity
        s.x,s.z,s.time=x,z,now
    end
    local remaining=false
    for index,part in pairs(s.parts) do
        local age=now-part.born
        if age>=part.lifetime-C.expiry_epsilon then
            Budget.remove(part)
        else
            part.fx.Transform:SetPosition(part.x+age*part.vx,part.y,part.z+age*part.vz)
            Glow.update(part.fx)
            face_segment(s,part,age,false)
            remaining=true
        end
    end
    return alive or remaining
end

local function tick(world)
    local pool=world._nw_elemental_flights
    local now=GetTime()
    for i=#pool.shots,1,-1 do
        if not update(pool,pool.shots[i],now) then
            pool.shots[i]=pool.shots[#pool.shots]
            pool.shots[#pool.shots]=nil
        end
    end
    if #pool.shots==0 then
        pool.task:Cancel()
        world._nw_elemental_flights=nil
    end
end

function M.attach(inst,id)
    id=M.resolve(id)
    if not profiles[id] or not inst._visual or TheNet:IsDedicated() then return end
    local previous=inst._nw_elemental_flight
    if previous and previous.id==id then return end
    if previous then previous.retired=true end
    local visual=inst._visual
    visual.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
    visual.AnimState:SetBank(BANK)
    visual.AnimState:SetBuild(BANK)
    local pool=TheWorld._nw_elemental_flights
    if not pool then
        pool={shots={},count=0,arrow_count=0}
        TheWorld._nw_elemental_flights=pool
        pool.task=TheWorld:DoPeriodicTask(FRAME,tick)
    end
    local x,_,z=inst.Transform:GetWorldPosition()
    local now=GetTime()
    local scale=math.max(1,inst._size:value())
    local lifetime,interval=M.trail_timing(scale,id)
    local profile=profiles[id]
    local s={inst=inst,visual=visual,id=id,x=x,z=z,time=now,started=now,
        phase=((inst.GUID or 0)%(profile.head_frames or C.clip_frames))*FRAME,speed=speed(inst),scale=scale,lifetime=lifetime,interval=interval,
        head_playback=profile.head_playback or 1,head_time=(profile.head_frames or C.clip_frames)*FRAME,
        slots=profile.spatial and ARROW_SLOTS or math.ceil((profile.life or BASE_TRAIL_LIFE)*profile.rate),
        next_emit=now+interval*(profile.stagger and ((inst.GUID or 0)%C.stagger_groups+1)/C.stagger_groups or 1),next=1,parts={}}
    inst._nw_elemental_flight=s
    if id=="land_hook" and inst._launch_heading and inst._launch_heading:value()~=0 then
        s.launch_heading=inst._launch_heading:value()-C.launch_heading_offset
    end
    pool.shots[#pool.shots+1]=s
    face_head(s,now)
end
return M
