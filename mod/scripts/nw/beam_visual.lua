-- Local native laser spans. The server owns the path, hit width and expiry;
-- each confirmed span keeps its endpoints while only its cross-section fades.
local Path=require("nw/beam_path")
local M={}
local FRAME=1/30
local BANK="wagdrone_laserwire_fx"
local ANIMATION="beam_straight"
local NATIVE_LENGTH=2 -- Native laser-wire spacing, including its end overlap.
local NATIVE_WIDTH=44/150 -- Widest painted glow across all 14 native poses.
local NATIVE_PERIOD=14/30
local TIP_MAX_DISTANCE=4
local TIP_MAX_AGE=Path.snapshot_interval*2+FRAME

local function new_piece(phase)
    local fx=CreateEntity()
    fx.entity:AddTransform();fx.entity:AddAnimState()
    fx.entity:SetCanSleep(false)
    fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
    fx.AnimState:SetBank(BANK);fx.AnimState:SetBuild(BANK)
    fx.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    fx.AnimState:SetLightOverride(1);fx.AnimState:SetFinalOffset(3)
    fx.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
    -- Keep the original animated core/glow texture; colour is runtime tint.
    fx.AnimState:SetMultColour(.72,.36,1,1)
    fx.AnimState:PlayAnimation(ANIMATION,true)
    fx.AnimState:SetTime(phase%NATIVE_PERIOD)
    return fx
end

local function discard_piece(part)
    if part and part.fx:IsValid() then part.fx:Remove() end
end

local function draw(part,height,width)
    part.fx.Transform:SetPosition((part.x1+part.x2)*.5,height,(part.z1+part.z2)*.5)
    part.fx.Transform:SetRotation(-math.deg(math.atan2(part.z2-part.z1,part.x2-part.x1)))
    -- Along-path length is independent of age; only the native Y axis narrows.
    part.fx.AnimState:SetScale(part.length/NATIVE_LENGTH,2*part.radius*width/NATIVE_WIDTH)
    part.fx.AnimState:SetMultColour(.72,.36,1,width)
end

local function remove_part(s,id)
    local part=s.parts[id]
    if part then
        discard_piece(part)
        s.parts[id]=nil
        -- IDs increase with birth order. A scalar also rejects late snapshots
        -- after local expiry without accumulating an unbounded tombstone set.
        s.retired=math.max(s.retired,id)
    end
end

local function remove_tip(s)
    discard_piece(s.tip)
    s.tip=nil
end

local function leave_pool(s)
    local pool=s.pool
    if not pool then return end
    s.pool=nil
    for index=#pool.shots,1,-1 do
        if pool.shots[index]==s then
            pool.shots[index]=pool.shots[#pool.shots]
            pool.shots[#pool.shots]=nil
            break
        end
    end
    if #pool.shots==0 then
        pool.task:Cancel()
        pool.world:RemoveEventCallback("onremove",pool.onremove)
        if pool.world._nw_beam_visuals==pool then pool.world._nw_beam_visuals=nil end
    end
end

local function refresh_tip(s,now,height)
    local anchor=s.anchor
    if s.ended or not anchor or now-s.received+anchor.age>TIP_MAX_AGE then remove_tip(s);return false end
    local x,_,z=s.inst.Transform:GetWorldPosition()
    local dx,dz=x-anchor.x,z-anchor.z
    local length=math.sqrt(dx*dx+dz*dz)
    if length<.001 or length>TIP_MAX_DISTANCE then remove_tip(s);return false end
    if not s.tip then s.tip={fx=new_piece((anchor.id%14)*FRAME)} end
    local tip=s.tip
    tip.x1,tip.z1,tip.x2,tip.z2=anchor.x,anchor.z,x,z
    tip.radius,tip.length=anchor.radius,length
    draw(tip,height,1)
    return true
end

local function update(s,now)
    if not s.inst:IsValid() then M.detach(s.inst);return false end
    local height=s.inst._height:value()
    local remaining=false
    for id,part in pairs(s.parts) do
        local age=math.max(0,now-part.born)
        local width=Path.width(age)
        if age>=Path.lifetime-.000001 or width<=0 then remove_part(s,id)
        else draw(part,height,width);remaining=true end
    end
    local tip=refresh_tip(s,now,height)
    -- A recent empty tip may grow on the next interpolated root position.
    return remaining or tip or not s.ended and s.anchor and now-s.received+s.anchor.age<=TIP_MAX_AGE
end

local function tick(world)
    local pool=world._nw_beam_visuals
    if not pool then return end
    local now=GetTime()
    for index=#pool.shots,1,-1 do
        local s=pool.shots[index]
        if not update(s,now) then leave_pool(s) end
    end
end

local function enter_pool(s)
    if s.pool then return end
    local pool=TheWorld._nw_beam_visuals
    if not pool then
        pool={world=TheWorld,shots={}}
        TheWorld._nw_beam_visuals=pool
        pool.task=TheWorld:DoPeriodicTask(FRAME,tick)
        pool.onremove=function()
            for index=#pool.shots,1,-1 do M.detach(pool.shots[index].inst) end
        end
        TheWorld:ListenForEvent("onremove",pool.onremove)
    end
    s.pool=pool
    pool.shots[#pool.shots+1]=s
end

function M.detach(inst)
    local s=inst._nw_beam_visual
    if not s then return end
    for id in pairs(s.parts) do remove_part(s,id) end
    remove_tip(s)
    leave_pool(s)
    inst:RemoveEventCallback("nw_beamdirty",s.onrefresh)
    inst:RemoveEventCallback("nw_projectiledirty",s.onrefresh)
    inst:RemoveEventCallback("onremove",s.onremove)
    s.world:RemoveEventCallback("onremove",s.onworldremove)
    inst._nw_beam_visual=nil
end

function M.refresh(inst)
    if TheNet:IsDedicated() or not inst._beam_path then return end
    local s=inst._nw_beam_visual
    if not s then return M.attach(inst) end
    s.ended=s.ended or inst._beam_ended:value()
    if s.ended then remove_tip(s) end
    local snapshot=Path.decode(inst._beam_path:value())
    local now=GetTime()
    if snapshot and (not s.stamp or snapshot.time>=s.stamp) then
        -- Re-delivered unchanged snapshots must not renew the tip's freshness.
        if not s.stamp or snapshot.time>s.stamp then s.received=now end
        s.stamp=snapshot.time
        local seen={}
        local newest
        for _,segment in ipairs(snapshot.segments) do
            local id=segment.id
            seen[id]=true
            if not newest or id>newest.id then newest=segment end
            local part=s.parts[id]
            if part or id>s.retired then
                local dx,dz=segment.x2-segment.x1,segment.z2-segment.z1
                local length=math.sqrt(dx*dx+dz*dz)
                if segment.age<Path.lifetime and segment.radius>0 and length>.001 then
                    local born=now-segment.age
                    if not part then
                        part={fx=new_piece(segment.age+(id%14)*FRAME),born=born}
                        s.parts[id]=part
                    elseif born<part.born then
                        part.born=born
                        part.fx.AnimState:SetTime((now-born+(id%14)*FRAME)%NATIVE_PERIOD)
                    end
                    part.x1,part.z1,part.x2,part.z2=segment.x1,segment.z1,segment.x2,segment.z2
                    part.radius,part.length=segment.radius,length
                else
                    remove_part(s,id)
                    s.retired=math.max(s.retired,id)
                end
            end
        end
        for id in pairs(s.parts) do if not seen[id] then remove_part(s,id) end end
        s.anchor=newest and {id=newest.id,x=newest.x2,z=newest.z2,radius=newest.radius,age=newest.age} or nil
    end
    if update(s,now) then enter_pool(s) else leave_pool(s) end
end

function M.attach(inst)
    if TheNet:IsDedicated() or not inst._beam_path or not inst:IsValid() then return end
    local previous=inst._nw_beam_visual
    if previous then return previous end
    local s={inst=inst,world=TheWorld,parts={},retired=0,received=-math.huge,ended=false}
    s.onrefresh=function() M.refresh(inst) end
    s.onremove=function() M.detach(inst) end
    s.onworldremove=s.onremove
    inst._nw_beam_visual=s
    inst:ListenForEvent("nw_beamdirty",s.onrefresh)
    inst:ListenForEvent("nw_projectiledirty",s.onrefresh)
    inst:ListenForEvent("onremove",s.onremove)
    s.world:ListenForEvent("onremove",s.onworldremove)
    M.refresh(inst)
    return s
end

return M
