local C=require("nw/constants/visuals/field_member_visual")
local Stages=require("nw/field_stages")
local M={}
local TAU=2*math.pi
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
    for _,part in ipairs(s.members) do if part.fx:IsValid() then part.fx:Remove() end end
    s.inst:RemoveEventCallback("onremove",s.onremove)
    s.inst:RemoveEventCallback("nw_field_stagedirty",s.dirty)
    if s.inst._nw_field_members==s then s.inst._nw_field_members=nil end
    local pool=s.pool
    for i=#pool.fields,1,-1 do
        if pool.fields[i]==s then pool.fields[i]=pool.fields[#pool.fields];pool.fields[#pool.fields]=nil;break end
    end
    if #pool.fields==0 then
        if pool.controller:IsValid() then pool.controller:Remove() end
        pool.world:RemoveEventCallback("onremove",pool.onremove)
        if pool.world._nw_field_members==pool then pool.world._nw_field_members=nil end
    end
end
local function sprite(kind,index)
    local fx=CreateEntity()
    fx.entity:AddTransform();fx.entity:AddAnimState();fx.entity:SetCanSleep(false)
    fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
    fx.AnimState:SetBank(Stages.bank);fx.AnimState:SetBuild(Stages.bank)
    fx.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
    if kind=="mote" then fx.AnimState:SetLightOverride(1) end
    fx:Hide()
    return {fx=fx,kind=kind,index=index,visible=false}
end
local function layout(s,seed)
    local state=((seed+1)*69621)%2147483647
    local function random()
        state=(state*16807)%2147483647
        return (state-1)/2147483646
    end
    for i=1,8 do
        local part=s.members[i]
        part.angle=(i-1)*TAU/8;part.radius=1;part.artscale=1
    end
    local index=9
    for gap=0,7 do
        local count=gap%2==0 and 2 or 1
        for n=1,count do
            local part=s.members[index];index=index+1
            local fraction=count==1 and C.single_gap_base+C.single_gap_spread*random() or C.double_gap_base+(n-1)*C.double_gap_step+C.double_gap_spread*random()
            part.angle=(gap+fraction)*TAU/8
            part.radius=C.vital_radius_base+C.vital_radius_spread*random()
            part.artscale=C.vital_scale_base+C.vital_scale_spread*random()
        end
    end
    for i=21,26 do
        local part=s.members[i]
        local angle,radius=random()*TAU,math.sqrt(random())*C.mote_radius
        part.center_x,part.center_z=math.cos(angle)*radius,math.sin(angle)*radius
        part.phase=random()*TAU;part.drift=C.drift_base+C.drift_spread*random()
        part.omega=(C.orbit_base+C.orbit_spread*random())*(random()<.5 and -1 or 1)
        part.height=C.height_base+C.height_spread*random();part.bob=C.bob_base+C.bob_spread*random();part.bobrate=C.bob_rate_base+C.bob_rate_spread*random()
        part.artscale=C.mote_scale_base+C.mote_scale_spread*random()
    end
    s.seed=seed
end
local function refresh(s,now)
    local inst=s.inst
    local seq=inst._nw_stage_seq:value()
    if seq==0 or seq==s.seq then return end
    local first=s.seq==nil
    s.seq=seq;s.changed=now
    s.started=s.started or now-inst._nw_stage_age:value()
    s.phase=inst._nw_stage_phase:value()
    s.size=math.max(.01,inst._nw_stage_size:value())
    s.radius=math.max(0,inst._nw_stage_radius:value())
    s.count=inst._nw_stage_count:value()
    if s.id=="vital_ring" then
        local seed=inst._nw_stage_seed:value()
        if s.seed~=seed then layout(s,seed) end
    end
    for _,part in ipairs(s.members) do
        if part.kind=="guard" and part.index>s.count and not part.ending then
            if first then part.fx:Remove() else part.ending=now;part.animation=nil end
        end
    end
end
local function animate(s,part,now)
    if not part.fx:IsValid() then return end
    local elapsed=now-s.changed
    local ending=part.ending or s.phase==Stages.phase.finish and s.changed
    if ending and now-ending>=Stages.end_time then part.fx:Remove();return end
    local phase=ending and "end" or s.phase==Stages.phase.spawn and elapsed<Stages.spawn_time and "spawn"
        or s.phase==Stages.phase.pulse and elapsed<Stages.pulse_time and "pulse" or "idle"
    local clip=part.kind=="mote" and (phase=="pulse" and "vital_mote_pulse" or "vital_mote_idle")
        or part.kind.."_member_"..phase
    local phase_seq=ending or s.seq
    if clip~=part.animation or part.phase_seq~=phase_seq then
        part.animation=clip;part.phase_seq=phase_seq
        part.fx.AnimState:PlayAnimation(clip,phase=="idle" or part.kind=="mote" and phase~="pulse")
        if phase=="idle" then part.fx.AnimState:SetTime((now-s.started+part.index*C.idle_phase_step)%C.idle_period) end
    end
    if part.kind=="mote" then
        local fade=ending and math.max(0,1-(now-ending)/Stages.end_time)
            or phase=="spawn" and math.min(1,elapsed/Stages.spawn_time) or 1
        local pulse=phase=="pulse" and C.pulse_alpha+C.pulse_alpha*math.sin(math.pi*elapsed/Stages.pulse_time) or 0
        part.fx.AnimState:SetMultColour(1,1,1,fade*math.min(1,C.mote_alpha+C.alpha_bob*math.sin((now-s.started)*part.bobrate+part.phase)+pulse))
    end
end
local function update(s,now)
    refresh(s,now)
    if not s.seq then return end
    local x,y,z=s.inst.Transform:GetWorldPosition()
    local age=now-s.started
    local shown=visible(s.inst)
    for _,part in ipairs(s.members) do
        animate(s,part,now)
        if part.fx:IsValid() then
            local ox,oz,height
            if part.kind=="guard" then
                local angle=age*C.guard_orbit_speed+(part.index-1)*math.pi
                ox,oz=math.cos(angle)*s.radius,math.sin(angle)*s.radius
                height=C.guard_height+C.guard_bob*math.sin(age*C.guard_bob_rate+part.index)
            elseif part.kind=="vital" then
                ox,oz=math.cos(part.angle)*s.radius*part.radius,math.sin(part.angle)*s.radius*part.radius
                height=0
            else
                local angle=part.phase+age*part.omega
                ox=s.radius*(part.center_x+part.drift*math.cos(angle))
                oz=s.radius*(part.center_z+part.drift*C.drift_depth*math.sin(angle*C.drift_frequency+part.phase*C.drift_phase))
                height=(part.height+part.bob*math.sin(age*part.bobrate+part.phase))*math.sqrt(s.size)
                local elapsed=now-s.changed
                if s.phase==Stages.phase.pulse and elapsed<Stages.pulse_time then
                    height=height+C.pulse_height*math.sin(math.pi*elapsed/Stages.pulse_time)
                end
            end
            part.x,part.y,part.z=x+ox,y+height,z+oz
            part.fx.Transform:SetPosition(part.x,part.y,part.z)
            local scale=s.size*(part.kind=="guard" and C.guard_scale or part.artscale)
            if scale~=part.scale then part.scale=scale;part.fx.Transform:SetScale(scale,scale,scale) end
            if shown~=part.visible then
                part.visible=shown
                if shown then part.fx:Show() else part.fx:Hide() end
            end
        end
    end
end
local function tick(pool,dt)
    if pool.world._nw_field_members~=pool then return end
    pool.clock=pool.clock+dt*TheSim:GetTimeScale()
    local now=pool.clock
    for i=#pool.fields,1,-1 do
        local s=pool.fields[i]
        if s.inst:IsValid() then update(s,now) else remove(s) end
    end
end
function M.detach(inst) if inst._nw_field_members then remove(inst._nw_field_members) end end
function M.attach(inst,id)
    if not Stages.members(id) or TheNet:IsDedicated() then return end
    if inst._nw_field_members then return inst._nw_field_members end
    local pool=TheWorld._nw_field_members
    if not pool then
        pool={world=TheWorld,fields={},clock=GetTime()}
        TheWorld._nw_field_members=pool
        local controller=CreateEntity()
        controller.entity:AddTransform();controller.entity:SetCanSleep(false)
        controller:AddTag("FX");controller:AddTag("NOCLICK");controller.persists=false
        controller:AddComponent("updatelooper")
        pool.controller=controller
        pool.wallfn=function(_,dt) tick(pool,dt) end
        controller.components.updatelooper:AddOnWallUpdateFn(pool.wallfn)
        pool.onremove=function() for i=#pool.fields,1,-1 do remove(pool.fields[i]) end end
        TheWorld:ListenForEvent("onremove",pool.onremove)
    end
    local s={inst=inst,id=id,pool=pool,members={}}
    if id=="guard_ring" then
        for i=1,2 do s.members[#s.members+1]=sprite("guard",i) end
    else
        for i=1,20 do s.members[#s.members+1]=sprite("vital",i) end
        for i=21,26 do s.members[#s.members+1]=sprite("mote",i) end
    end
    s.onremove=function() remove(s) end
    s.dirty=function() end
    inst._nw_field_members=s;pool.fields[#pool.fields+1]=s
    inst:ListenForEvent("onremove",s.onremove)
    inst:ListenForEvent("nw_field_stagedirty",s.dirty)
    return s
end
return M
