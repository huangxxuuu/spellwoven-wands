-- Local animated spell bodies and detached trails. Gameplay stays on nw_projectile.
local M={}
local FRAME=1/30
local CLIP_TIME=6*FRAME
local BASE_TRAIL_LIFE=.2
local MAX_SAMPLE_DT=.2
local CLIENT_LIMIT=128
local ARROW_LIMIT=256
local ARROW_SLOTS=128
local MAX_PATH_BIRTHS=64
local BANK="nw_elemental_flight"
local profiles={
    fire={drift=.12,offset=.24,rate=24},
    frost={drift=0,offset=.20,rate=24},
    arrow={drift=0,offset=.45,rate=30,life=.35,maxlife=.9,directions=128,motion_heading=true,spatial=true},
    heavy={drift=.06,offset=.65,rate=12,head_playback=.5},
    scatter={drift=.04,offset=.22,rate=20,life=.3,maxlife=.75,stagger=true},
    -- Registered head/tail alpha bounds determine the new rear offsets. Keep
    -- a visible overlap at the attachment; the hook attaches behind its rope.
    gust={drift=.08,offset=.60,rate=24,life=.24,motion_heading=true},
    spore_ball={drift=.03,offset=.50,rate=16,life=.32,maxlife=.8,motion_heading=true},
    flint_lance={drift=0,offset=.50,rate=30,life=.35,maxlife=.9,directions=128,motion_heading=true,
        spatial=true,spacing=.13,coverage=.28},
    slime={drift=.08,offset=.60,rate=20,life=.3,maxlife=.75,motion_heading=true},
    grow_orb={drift=.02,offset=.60,rate=24,life=.3,maxlife=.75,motion_heading=true},
    heal_bolt={drift=.04,offset=.60,rate=24,life=.3,maxlife=.75,motion_heading=true},
    star_vortex={drift=0,offset=.38,rate=24,life=.24,motion_heading=true,stagger=true},
    glass_disc={drift=0,offset=.48,rate=24,life=.24,motion_heading=true},
    land_hook={drift=.02,offset=3.50,rate=24,life=.24,motion_heading=true},
    tri_electric={drift=0,offset=.36,rate=30,life=.24,head_frames=12,motion_heading=true,stagger=true},
    end_beam={drift=0,offset=.72,rate=60,life=.24,directions=128,motion_heading=true},
    soundwave={drift=0,offset=.45,rate=24,life=.3,maxlife=.75,motion_heading=true},
    bee_swarm={drift=.04,offset=.28,rate=20,life=.24,motion_heading=true,stagger=true},
    fireflies={drift=.02,offset=.44,rate=24,life=.3,maxlife=.75,motion_heading=true,stagger=true},
}

-- Keep card identity on the wire and in gameplay. Only ocarina projectiles
-- share the soundwave artwork; kantele notes are stationary fields.
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
    return (profile and profile.head_frames or 6)*FRAME/(profile and profile.head_playback or 1)
end

-- The painted strip retains this conservative axial coverage at every age.
-- Less than half-length spacing also covers the unsampled gap at the body.
-- Omitted id preserves the accepted arrow spacing; the lance uses shorter art.
function M.trail_spacing(scale,id)
    scale=math.max(1,scale)
    local profile=profiles[M.resolve(id)]
    return (profile and profile.spacing or .19)*scale,(profile and profile.coverage or .4)*scale
end

function M.trail_timing(scale,id)
    local profile=profiles[M.resolve(id)]
    local rate=profile and profile.rate or 24
    local base=profile and profile.life or BASE_TRAIL_LIFE
    local maximum=profile and profile.maxlife or .6
    local lifetime=math.min(maximum,base*math.sqrt(math.max(1,scale)))
    -- Spatial trails have no timer. This is a reference interval at speed 25;
    -- runtime births are driven entirely by the sampled anchor's path length.
    if profile and profile.spatial then return lifetime,M.trail_spacing(scale,id)/25 end
    return lifetime,lifetime/(base*rate)
end

function M.direction_count(id)
    local profile=profiles[M.resolve(id)]
    return profile and profile.directions or 32
end

-- World heading in radians, projected into the camera-facing sprite plane.
-- Impact visuals use the same mapping, including when the camera rotates.
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
    heading=heading or -s.inst.Transform:GetRotation()*math.pi/180
    local direction=M.direction(heading,s.id)
    if direction~=s.direction then
        s.direction=direction
        s.visual.AnimState:PlayAnimation(s.id.."_dir_"..direction,true)
        s.visual.AnimState:SetDeltaTimeMultiplier(s.head_playback)
        -- Direction clips share the same timeline. Never restart a flame or
        -- crystal shimmer when homing, bouncing, or rotating the camera.
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
    fx.AnimState:SetLightOverride(1)
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

local function oldest_arrow(pool)
    local oldest
    for _,shot in ipairs(pool.shots) do
        if profiles[shot.id].spatial then
            for _,part in pairs(shot.parts) do
                if not oldest or part.born<oldest.born then oldest=part end
            end
        end
    end
    return oldest
end

local function emit(pool,s,born,now,x,y,z,dx,dz,dt,distance,anchored)
    local profile=profiles[s.id]
    local part=s.parts[s.next]
    -- A later size correction may increase the birth rate. Let older, larger
    -- particles finish their original lifetime instead of cutting them short.
    if part and now-part.born<part.lifetime-.00001 and not profile.spatial then return end
    if not part then
        if profile.spatial then
            if pool.arrow_count>=ARROW_LIMIT then
                -- Preserve arrow/lance front connections under load by recycling
                -- the oldest spatial tail. Timed particles keep their lifetime.
                part=oldest_arrow(pool)
                if not part then return end
                part.owner.parts[part.slot]=nil
            else
                part=new_segment()
                pool.arrow_count=pool.arrow_count+1
                pool.count=pool.count+1
            end
        else
            if pool.count-pool.arrow_count>=CLIENT_LIMIT then return end
            part=new_segment()
            pool.count=pool.count+1
        end
        s.parts[s.next]=part
    end
    part.owner,part.slot=s,s.next
    part.arrow=profile.spatial or false
    s.next=s.next%s.slots+1
    local scale=math.max(1,s.inst._size:value())
    part.born=born
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
        -- Start at the preceding rear anchor, never at an older visible
        -- sample from before a teleport, hidden interval or size correction.
        path={x=s.x-offset*dx/distance,y=y,z=s.z-offset*dz/distance,time=s.time,carry=spacing}
        s.path=path
    end
    local px,pz=ax-path.x,az-path.z
    local length=math.sqrt(px*px+pz*pz)
    if length>.000001 then
        local births=math.floor((path.carry+length+.000001)/spacing)
        if births>MAX_PATH_BIRTHS then
            -- Never join a huge correction with a long straight streak.
            -- One fresh segment marks the new front; the old trail fades out.
            emit(pool,s,now,now,ax,y,az,dx,dz,dt,distance,true)
            path.carry=0
        else
            local travelled=spacing-path.carry
            while travelled<=length+.000001 do
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
            -- Preserve the fraction left before the next birth on a dirty update.
            s.next_emit=now+math.max(0,s.next_emit-now)*s.interval/previous
            s.path=nil
        end
        local x,_,z=inst.Transform:GetWorldPosition()
        local dt=now-s.time
        local dx,dz=x-s.x,z-s.z
        local distance=math.sqrt(dx*dx+dz*dz)
        local velocity=speed(inst)
        -- Scale the discontinuity guard with physical/observed velocity so
        -- legitimate speed modifiers do not lose their trails above 60 units/s.
        local expected=math.max(velocity,s.speed)
        local continuous=dt>0 and dt<=MAX_SAMPLE_DT+.000001 and distance>.001
            and distance<=math.max(60,expected)*dt*2+.1
        -- Directional bodies face the segment actually travelled, just like
        -- their new trails. Motor rotation may already describe the next turn.
        face_head(s,now,profiles[s.id].motion_heading and continuous and math.atan2(dz,dx) or nil)
        if continuous and s.visual.entity:IsVisible() then
            if profiles[s.id].spatial then
                path_emit(pool,s,now,x,inst._height:value(),z,dx,dz,dt,distance)
            else
                -- Timed fragments keep their existing bounded birth schedule.
                s.next_emit=math.max(s.next_emit,now-2*s.interval+.00001)
                while s.next_emit<=now+.000001 do
                    local age=math.max(0,now-s.next_emit)
                    emit(pool,s,s.next_emit,now,x-dx*age/dt,inst._height:value(),z-dz*age/dt,dx,dz,dt,distance)
                    s.next_emit=s.next_emit+s.interval
                end
            end
        else
            s.next_emit=now+s.interval
            s.path=nil
        end
        -- A correction must not inflate the next frame's displacement budget.
        s.speed=continuous and distance/dt or velocity
        s.x,s.z,s.time=x,z,now
    end
    local remaining=false
    for index,part in pairs(s.parts) do
        local age=now-part.born
        if age>=part.lifetime-.00001 then
            part.fx:Remove()
            s.parts[index]=nil
            pool.count=pool.count-1
            if part.arrow then pool.arrow_count=pool.arrow_count-1 end
        else
            part.fx.Transform:SetPosition(part.x+age*part.vx,part.y,part.z+age*part.vz)
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
        phase=((inst.GUID or 0)%(profile.head_frames or 6))*FRAME,speed=speed(inst),scale=scale,lifetime=lifetime,interval=interval,
        head_playback=profile.head_playback or 1,head_time=(profile.head_frames or 6)*FRAME,
        -- Spatial tails share a separate pool; timed lifetimes and intervals
        -- grow together, preserving each kind's slot budget.
        slots=profile.spatial and ARROW_SLOTS or math.ceil((profile.life or BASE_TRAIL_LIFE)*profile.rate),
        next_emit=now+interval*(profile.stagger and ((inst.GUID or 0)%3+1)/3 or 1),next=1,parts={}}
    inst._nw_elemental_flight=s
    pool.shots[#pool.shots+1]=s
    face_head(s,now)
end
return M
