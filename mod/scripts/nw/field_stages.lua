local C=require("nw/constants/visuals/field_stages")
local Size=require("nw/projectile_size")
local M={bank=C.bank,spawn_time=C.spawn_time,pulse_time=C.pulse_time,end_time=C.end_time,fall_time=C.fall_time}
M.storm_strike_pixels=C.storm_strike_pixels
function M.storm_lift(p) return M.storm_strike_pixels/C.pixels_per_unit*Size.factor(p) end
M.phase=C.phase
local profiles=C.profiles
local members=C.members
local footprint=C.footprint
function M.has(id) return profiles[id]==true end
function M.members(id) return members[id]==true end
function M.orientation(id)
    return (id=="vortex" or id=="shock_ring") and ANIM_ORIENTATION.OnGround or ANIM_ORIENTATION.BillBoard
end
function M.duration(id,phase)
    if id=="storm_cloud" then
        if phase=="spawn" then return C.storm_spawn_time end
        if phase=="warning" then return C.storm_warning_time end
        if phase=="end" then return C.storm_end_time end
    end
    if phase=="end" then return id=="deer_decoy" and C.decoy_end_time or M.end_time end
    return phase=="spawn" and M.spawn_time or M.pulse_time
end
function M.storm_time_scale(p)
    local lifetime=p and p.field_lifetime_mult or 1
    return lifetime>0 and math.min(1,lifetime) or 1
end
local function fit(inst,id,size,radius)
    local width=footprint[id]
    if id=="deer_decoy" then
        inst.AnimState:SetScale(C.decoy_scale,C.decoy_scale)
    elseif width then
        local scale=2*radius*C.pixels_per_unit/(width*size)*(id=="moon_fall" and C.moon_radius_scale or 1)
        inst.AnimState:SetScale(scale,scale)
    end
end

local function moon_shadow(inst)
    if TheNet:IsDedicated() then return end
    local shadow=CreateEntity()
    shadow.entity:AddTransform();shadow.entity:AddAnimState();shadow.entity:SetCanSleep(false)
    shadow:AddTag("FX");shadow:AddTag("NOCLICK");shadow.persists=false
    shadow.entity:SetParent(inst.entity)
    shadow.AnimState:SetBank("warning_shadow");shadow.AnimState:SetBuild("meteor_shadow")
    shadow.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    shadow.AnimState:SetFinalOffset(C.shadow_offset)
    shadow.AnimState:PlayAnimation("idle",true)
    shadow.AnimState:SetMultColour(1,1,1,C.shadow_alpha)
    shadow.AnimState:SetScale(1,C.shadow_width/C.shadow_height)
    local function refresh()
        local radius=inst._nw_moon_radius:value()
        if radius<=0 then shadow:Hide();return end
        local scale=radius*2*C.moon_radius_scale*C.pixels_per_unit/C.shadow_width
        shadow.Transform:SetScale(scale,scale,scale)
        shadow:Show()
    end
    inst._nw_moon_shadow=shadow
    inst._nw_refresh_moon_shadow=refresh
    inst:ListenForEvent("nw_moonshadowdirty",refresh)
    inst:ListenForEvent("onremove",function() if shadow:IsValid() then shadow:Remove() end end)
    refresh()
end

function M.netvars(inst)
    inst._nw_stage_phase=net_tinybyte(inst.GUID,"nw_field.phase","nw_field_stagedirty")
    inst._nw_stage_seq=net_ushortint(inst.GUID,"nw_field.seq","nw_field_stagedirty")
    inst._nw_stage_size=net_float(inst.GUID,"nw_field.size","nw_field_stagedirty")
    inst._nw_stage_radius=net_float(inst.GUID,"nw_field.radius","nw_field_stagedirty")
    inst._nw_stage_count=net_smallbyte(inst.GUID,"nw_field.count","nw_field_stagedirty")
    inst._nw_stage_age=net_float(inst.GUID,"nw_field.age","nw_field_stagedirty")
    inst._nw_stage_seed=net_ushortint(inst.GUID,"nw_field.seed","nw_field_stagedirty")
end

function M.setup(inst,id)
    if not profiles[id] then return end
    if members[id] then M.netvars(inst) end
    if id=="moon_fall" then
        inst._nw_moon_radius=net_float(inst.GUID,"nw_field.moonradius","nw_moonshadowdirty")
    end
    inst.AnimState:SetBank(M.bank);inst.AnimState:SetBuild(M.bank)
    inst.AnimState:SetOrientation(M.orientation(id))
    if id=="storm_cloud" then inst.AnimState:SetFinalOffset(C.storm_offset) end
    inst.AnimState:PlayAnimation(id.."_idle",true)
    if members[id] then inst.AnimState:SetMultColour(1,1,1,0) end
    if id=="deer_decoy" then inst.AnimState:SetLightOverride(C.decoy_light) end
end

function M.attach(inst,id)
    if members[id] then return require("nw/field_member_visual").attach(inst,id) end
    if id=="moon_fall" then moon_shadow(inst) end
end

local function publish(inst,phase)
    local s=inst._nw_field_stages
    if not s or not members[s.id] then return end
    inst._nw_stage_size:set(s.size)
    inst._nw_stage_radius:set(s.radius)
    inst._nw_stage_count:set(s.count)
    inst._nw_stage_age:set(math.max(0,GetTime()-s.started))
    inst._nw_stage_seed:set(s.seed)
    inst._nw_stage_phase:set(M.phase[phase])
    s.seq=(s.seq or 0)%65535+1
    inst._nw_stage_seq:set(s.seq)
end

local function effect(inst,phase)
    local s=inst._nw_field_stages
    local prefab=s.id=="guard_ring" and "nw_guard_stage_fx"
        or s.id=="vital_ring" and "nw_vital_stage_fx" or "nw_field_stage_fx"
    local fx=SpawnPrefab(prefab)
    if fx then
        local x,y,z=inst.Transform:GetWorldPosition()
        fx.Transform:SetPosition(x,y,z)
        fx:SetStage(s.id,phase,s.size,s.radius,s.count,math.max(0,GetTime()-s.started),s.seed)
    end
end

local play
play=function(inst,phase,loop)
    local s=inst._nw_field_stages
    if not s or s.finished then return end
    s.phase=phase
    if members[s.id] then
        publish(inst,phase)
        if not loop then
            local seq=s.seq
            inst:DoTaskInTime(phase=="spawn" and M.spawn_time or M.pulse_time,function()
                if inst._nw_field_stages==s and not s.finished and s.seq==seq then play(inst,"idle",true) end
            end)
        end
    else
        local suffix=""
        if s.id=="storm_cloud" then
            if phase=="warning" then s.storm_cycle=(s.storm_cycle or 0)%3+1 end
            if phase~="spawn" and (s.storm_cycle or 1)>1 then suffix="_"..s.storm_cycle end
        end
        inst.AnimState:PlayAnimation(s.id.."_"..phase..suffix,loop==true)
        if not loop then inst.AnimState:PushAnimation(s.id.."_idle"..suffix,true) end
    end
end

function M.start(inst,id,p,loading)
    if not profiles[id] then return end
    inst._nw_field_stages={id=id,size=Size.factor(p),radius=p.radius or 1,
        count=id=="guard_ring" and 2 or 20,started=GetTime(),seq=0,seed=(inst.GUID or 0)%65535+1}
    local s=inst._nw_field_stages
    if id=="storm_cloud" then
        inst.AnimState:SetDeltaTimeMultiplier(1/M.storm_time_scale(p))
    end
    fit(inst,id,s.size,s.radius)
    if inst._nw_moon_radius then
        inst._nw_moon_radius:set(s.radius/s.size)
        if inst._nw_refresh_moon_shadow then inst._nw_refresh_moon_shadow() end
    end
    play(inst,loading and "idle" or id=="moon_fall" and "warning" or "spawn",loading or id=="moon_fall")
end
function M.pulse(inst) play(inst,"pulse") end
function M.warning(inst)
    local s=inst._nw_field_stages
    play(inst,"warning",s and s.id=="moon_fall")
end
function M.fall(inst)
    local s=inst._nw_field_stages
    if not s or s.finished or s.fallen then return end
    s.fallen=true;s.phase="fall"
    inst.AnimState:PlayAnimation(s.id.."_fall",false)
end
function M.finish(inst)
    local s=inst._nw_field_stages
    if not s or s.finished then return end
    s.finished=true
    effect(inst,"end")
end
function M.guard(inst,left)
    local s=inst._nw_field_stages
    if not s or s.finished then return end
    if left<=0 then M.finish(inst)
    else s.count=left;M.pulse(inst) end
end

function M.effect_state(inst,id,phase,size,radius,count,age,seed)
    inst._nw_field_stages={id=id,size=size or 1,radius=radius or 1,count=count or 1,
        started=GetTime()-(age or 0),seq=0,seed=seed or 1}
    inst.AnimState:SetOrientation(M.orientation(id))
    if members[id] then publish(inst,phase=="end" and "finish" or phase)
    else
        inst.Transform:SetScale(size or 1,size or 1,size or 1)
        fit(inst,id,size or 1,radius or 1)
        if id=="storm_cloud" then
            inst.AnimState:SetDeltaTimeMultiplier(1)
            inst.AnimState:SetFinalOffset(C.storm_offset)
        end
        if id=="deer_decoy" then inst.AnimState:SetLightOverride(C.decoy_light) end
        inst.AnimState:PlayAnimation(id.."_"..phase,false)
    end
end
return M
