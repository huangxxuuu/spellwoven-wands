local C=require("nw/constants/visuals/insect_swarm_visual")
local Flight=require("nw/elemental_flight")
local M={}
local FRAME=C.frame
local BANK=C.bank
local profiles=C.profiles

local function visible(inst)
    repeat
        if not inst.entity:IsVisible() then return false end
        inst=inst.entity:GetParent()
    until not inst
    return true
end

local function remove(s)
    if s.closed then return end
    s.closed=true
    for _,part in ipairs(s.members) do
        if part.fx:IsValid() then part.fx:Remove() end
    end
    s.inst:RemoveEventCallback("onremove",s.onremove)
    if s.inst._nw_insect_swarm==s then s.inst._nw_insect_swarm=nil end
    local pool=s.pool
    for index=#pool.fields,1,-1 do
        if pool.fields[index]==s then
            pool.fields[index]=pool.fields[#pool.fields]
            pool.fields[#pool.fields]=nil
            break
        end
    end
    if #pool.fields==0 then
        pool.task:Cancel()
        pool.world:RemoveEventCallback("onremove",pool.onremove)
        if pool.world._nw_insect_swarms==pool then pool.world._nw_insect_swarms=nil end
    end
end

local function update(s,now)
    local inst=s.inst
    local x,y,z=inst.Transform:GetWorldPosition()
    local value=inst._nw_insect_size:value()
    local scale=value>0 and value or 1
    local profile=profiles[s.id]
    local height=s.id=="fireflies" and math.max(profile.height,y+C.firefly_minimum_height) or y+profile.height
    local age=now-s.started
    local shown=visible(inst)
    for _,part in ipairs(s.members) do
        local angle=part.orbit_phase+age*part.omega
        local radius=part.radius*scale
        local px=x+math.cos(angle)*radius
        local pz=z+math.sin(angle)*radius*profile.depth
        local py=height+profile.bob*math.sqrt(scale)*math.sin(age*part.bob_rate+part.orbit_phase)
        local dx,dz=part.x and px-part.x or 0,part.z and pz-part.z or 0
        if dx*dx+dz*dz<.00000001 then
            dx,dz=-math.sin(angle)*part.omega,math.cos(angle)*part.omega*profile.depth
        end
        part.x,part.y,part.z=px,py,pz
        part.heading=math.atan2(dz,dx)
        part.fx.Transform:SetPosition(px,py,pz)
        if scale~=s.scale then part.fx.Transform:SetScale(scale,scale,scale) end
        if shown~=part.visible then
            part.visible=shown
            if shown then part.fx:Show() else part.fx:Hide() end
        end
        local direction=Flight.direction(part.heading,s.id)
        if direction~=part.direction then
            part.direction=direction
            part.fx.AnimState:PlayAnimation(s.id.."_dir_"..direction,true)
            part.fx.AnimState:SetDeltaTimeMultiplier(part.playback)
            part.fx.AnimState:SetTime((age*part.playback+part.phase)%s.period)
        end
    end
    s.scale=scale
end

local function tick(world)
    local pool=world._nw_insect_swarms
    if not pool then return end
    local now=GetTime()
    for index=#pool.fields,1,-1 do
        local s=pool.fields[index]
        if s.inst:IsValid() then update(s,now) else remove(s) end
    end
end

function M.detach(inst)
    if inst._nw_insect_swarm then remove(inst._nw_insect_swarm) end
end

function M.attach(inst,id)
    if not profiles[id] or TheNet:IsDedicated() then return end
    local previous=inst._nw_insect_swarm
    if previous and previous.id==id then return previous end
    if previous then remove(previous) end
    local pool=TheWorld._nw_insect_swarms
    if not pool then
        pool={world=TheWorld,fields={}}
        TheWorld._nw_insect_swarms=pool
        pool.task=TheWorld:DoPeriodicTask(FRAME,tick)
        pool.onremove=function()
            for index=#pool.fields,1,-1 do remove(pool.fields[index]) end
        end
        TheWorld:ListenForEvent("onremove",pool.onremove)
    end
    local profile=profiles[id]
    local s={inst=inst,id=id,pool=pool,started=GetTime(),period=Flight.head_period(id),members={}}
    local seed=(inst.GUID or 0)%C.seed_modulus*C.seed_step
    for index=1,profile.count do
        local fx=CreateEntity()
        fx.entity:AddTransform();fx.entity:AddAnimState();fx.entity:SetCanSleep(false)
        fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
        fx.AnimState:SetBank(BANK);fx.AnimState:SetBuild(BANK)
        fx.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
        fx:Hide()
        s.members[index]={fx=fx,visible=false,radius=profile.radius+(index-1)*C.radius_step,
            orbit_phase=seed+(index-1)*2*math.pi/profile.count,
            omega=(profile.speed+index*C.speed_step)*(index%2==0 and -1 or 1),bob_rate=C.bob_rate+index*C.bob_rate_step,
            phase=(((inst.GUID or 0)%6+(index-1)*2)%6)*FRAME,playback=C.playback+index*C.playback_step}
    end
    s.onremove=function() remove(s) end
    inst._nw_insect_swarm=s
    pool.fields[#pool.fields+1]=s
    inst:ListenForEvent("onremove",s.onremove)
    return s
end

return M
