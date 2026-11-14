local C=require("nw/constants/visuals/spark_trail")
local Glow=require("nw/projectile_glow")
local M={}
local Budget=require("nw/trail_budget")
local Limits=require("nw/spell_limits")
local CLIP_TIME=6*FRAMES
local LIFETIME=9*FRAMES
local MAX_SAMPLE_DT=6*FRAMES
local SLOTS=C.slots
local INTERVAL=LIFETIME/SLOTS
local PLAYBACK=CLIP_TIME/LIFETIME
local TAIL_OFFSET=C.tail_offset

local function new_segment()
    local fx=CreateEntity()
    fx.entity:AddTransform()
    fx.entity:AddAnimState()
    fx.entity:SetCanSleep(false)
    fx:AddTag("FX")
    fx:AddTag("NOCLICK")
    fx.persists=false
    fx.AnimState:SetBank("nw_spark_flight")
    fx.AnimState:SetBuild("nw_spark_flight")
    fx.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    fx.AnimState:SetDeltaTimeMultiplier(PLAYBACK)
    return {fx=fx}
end

local function discard(part)
    part.fx:Remove()
    part.owner.parts[part.slot]=nil
    part.pool.count=part.pool.count-1
end

local function emit(pool,s,born,age,x,y,z,dx,dz,dt,distance)
    if not Budget.can_emit(s.inst) then return end
    local index=s.next
    local part=s.parts[index]
    if not part then
        part=new_segment()
        s.parts[index]=part
        pool.count=pool.count+1
    end
    s.next=index%SLOTS+1
    part.born=born
    part.owner,part.slot,part.pool=s,index,pool
    Budget.track(part,born,discard)
    local scale=s.inst._size and math.max(1,s.inst._size:value()) or 1
    part.x,part.y,part.z=x-TAIL_OFFSET*scale*dx/distance,y,z-TAIL_OFFSET*scale*dz/distance
    if scale~=1 then part.fx.Transform:SetScale(scale,scale,scale) end
    part.vx,part.vz=C.velocity_scale*dx/dt,C.velocity_scale*dz/dt
    part.fx.AnimState:PlayAnimation("tail")
    part.fx.AnimState:SetTime(age*PLAYBACK)
end

local function update(pool,s,now)
    local inst=s.inst
    local alive=inst:IsValid()
    local x,y,z
    if alive then
        x,y,z=inst.Transform:GetWorldPosition()
        y=inst._height:value()
        local dt=now-s.time
        local dx,dz=x-s.x,z-s.z
        local distance=math.sqrt(dx*dx+dz*dz)
        if dt>0 and dt<=MAX_SAMPLE_DT and distance>.001 and distance<=Limits.max_speed*dt+.1
            and inst._visual.entity:IsVisible() then
            s.next_emit=math.max(s.next_emit,now-3*INTERVAL+.00001)
            while s.next_emit<=now+.000001 do
                local age=math.max(0,now-s.next_emit)
                emit(pool,s,s.next_emit,age,x-dx*age/dt,y,z-dz*age/dt,dx,dz,dt,distance)
                s.next_emit=s.next_emit+INTERVAL
            end
        else
            s.next_emit=now+INTERVAL
        end
        s.x,s.z,s.time=x,z,now
    end
    local remaining=false
    for index,part in pairs(s.parts) do
        local age=now-part.born
        if age>=LIFETIME-.00001 then
            Budget.remove(part)
        else
            local tx,tz=part.x+age*part.vx,part.z+age*part.vz
            part.fx.Transform:SetPosition(tx,part.y,tz)
            Glow.update(part.fx)
            if alive then part.fx:ForceFacePoint(x,y,z) end
            remaining=true
        end
    end
    return alive or remaining
end

local function tick(world)
    local pool=world._nw_spark_trails
    local now=GetTime()
    for i=#pool.shots,1,-1 do
        if not update(pool,pool.shots[i],now) then
            pool.shots[i]=pool.shots[#pool.shots]
            pool.shots[#pool.shots]=nil
        end
    end
    if #pool.shots==0 then
        pool.task:Cancel()
        world._nw_spark_trails=nil
    end
end

function M.attach(inst)
    local pool=TheWorld._nw_spark_trails
    if not pool then
        pool={shots={},count=0}
        TheWorld._nw_spark_trails=pool
        pool.task=TheWorld:DoPeriodicTask(FRAMES,tick)
    end
    local x,_,z=inst.Transform:GetWorldPosition()
    local now=GetTime()
    pool.shots[#pool.shots+1]={inst=inst,x=x,z=z,time=now,next_emit=now+INTERVAL,next=1,parts={}}
end
return M
