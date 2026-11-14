local C=require("nw/constants/visuals/dark_fog_visual")
local M={duration=C.duration}
local LIFETIME=C.lifetime
local COLOUR=C.colour
local SCALE=C.scale
local initialized=false
local scales={}
local function scale_envelope(scale)
    local key=string.format("%.6g",scale)
    local name=scales[key]
    if not name then
        name=SCALE.."_"..key
        EnvelopeManager:AddVector2Envelope(name,{{0,{C.initial_scale*scale,C.initial_scale*scale}},{1,{C.final_scale*scale,C.final_scale*scale}}})
        scales[key]=name
    end
    return name
end
local function envelopes()
    if initialized then return end
    EnvelopeManager:AddColourEnvelope(COLOUR,{
        unpack(C.colour_envelope),
    })
    initialized=true
end
local function clear(inst)
    for _,fx in ipairs(inst._nw_dark_children or {}) do
        if fx:IsValid() then fx.VFXEffect:ClearAllParticles(0) end
    end
end
function M.dissipate(inst)
    if not inst._nw_dark_visuals or inst._nw_dark_visual_fading then return end
    inst._nw_dark_visual_fading=true
    local started=GetTime()
    local previous=started
    local function update()
        local time=math.min(GetTime(),started+M.duration)
        local advance=math.max(0,time-previous)*(LIFETIME/M.duration-1)
        previous=time
        for _,fx in ipairs(inst._nw_dark_children) do
            if fx:IsValid() then fx.VFXEffect:FastForward(0,advance) end
        end
        if time>=started+M.duration then
            clear(inst)
            if inst._nw_dark_fade_task then inst._nw_dark_fade_task:Cancel();inst._nw_dark_fade_task=nil end
        end
    end
    inst._nw_dark_fade_task=inst:DoPeriodicTask(FRAMES,update)
end
function M.create_emitter()
    envelopes()
    local fx=CreateEntity()
    fx.entity:AddTransform()
    fx.entity:SetCanSleep(false)
    fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
    local effect=fx.entity:AddVFXEffect()
    effect:InitEmitters(1)
    effect:SetRenderResources(0,"fx/miasma.tex","shaders/vfx_particle.ksh")
    effect:SetMaxNumParticles(0,C.max_particles)
    effect:SetRotationStatus(0,true)
    effect:SetMaxLifetime(0,LIFETIME)
    effect:SetColourEnvelope(0,COLOUR)
    effect:SetScaleEnvelope(0,scale_envelope(1))
    effect:SetUVFrameSize(0,C.uv_width,1)
    effect:SetBlendMode(0,BLENDMODE.AlphaBlended)
    effect:SetSortOrder(0,0)
    effect:SetSortOffset(0,0)
    effect:SetRadius(0,require("nw/dark_fog").radius)
    effect:SetDragCoefficient(0,C.drag)
    return fx
end
local function particles(inst)
    local base=require("nw/dark_fog").radius
    local radius=inst._nw_dark_radius and inst._nw_dark_radius:value() or base
    if radius<=0 then radius=base end
    if inst._nw_dark_visual_radius==radius or inst._nw_dark_visual_fading then return end
    clear(inst)
    for _,old in ipairs(inst._nw_dark_children) do if old:IsValid() then old:Remove() end end
    inst._nw_dark_children={}
    inst._nw_dark_visual_radius=radius
    local scale=radius/base
    local fx=SpawnPrefab("nw_dark_fog_vfx")
    inst._nw_dark_children[1]=fx
    fx.entity:SetParent(inst.entity)
    fx.Transform:SetPosition(0,0,0)
    local effect=fx.VFXEffect
    effect:SetScaleEnvelope(0,scale_envelope(scale))
    effect:SetRadius(0,radius)
    local circle=CreateCircleEmitter(math.max(0,radius-C.initial_scale*scale*C.emitter_margin))
    local function emit()
        local x,z=circle()
        effect:AddRotatingParticleUV(0,LIFETIME,x,C.particle_height*scale*(1+math.random()),z,
            C.horizontal_speed*scale*UnitRand(),C.vertical_speed*scale*UnitRand(),C.horizontal_speed*scale*UnitRand(),
            math.random()*360,UnitRand()*C.rotation_speed,math.random(0,1)*C.uv_width,0)
    end
    for i=1,C.initial_particles do emit() end
    effect:FastForward(0,C.initial_advance)
    local pending=0
    EmitterManager:AddEmitter(fx,nil,function()
        if not inst:IsValid() or inst._nw_dark_visual_fading then return end
        pending=pending+C.emission_rate*TheSim:GetTickTime()
        while pending>=1 do emit();pending=pending-1 end
    end)
end
function M.attach(inst)
    if inst._nw_dark_visuals then return end
    inst._nw_dark_visuals=true
    inst._nw_dark_children={}
    inst:ListenForEvent("nw_dark_fog_dirty",function()
        if inst._nw_dark_dissipating:value() then M.dissipate(inst) end
    end)
    inst:ListenForEvent("onremove",function()
        if inst._nw_dark_fade_task then inst._nw_dark_fade_task:Cancel();inst._nw_dark_fade_task=nil end
        clear(inst)
        for _,fx in ipairs(inst._nw_dark_children) do if fx:IsValid() then fx:Remove() end end
    end)
    inst:ListenForEvent("nw_dark_fog_size_dirty",function() particles(inst) end)
    if inst._nw_dark_dissipating:value() then M.dissipate(inst);return end

    particles(inst)
end
return M
