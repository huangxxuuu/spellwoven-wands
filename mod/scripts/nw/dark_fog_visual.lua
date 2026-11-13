-- Vanilla miasma texture, UV frames, colour/scale envelopes and drift, fitted
-- to the spell's radius. This local emitter never enters miasma's fire path.
local M={duration=.4}
local LIFETIME=5
local COLOUR="nw_dark_miasma_colour"
local SCALE="nw_dark_miasma_scale"
local initialized=false
local scales={}
local function scale_envelope(scale)
    local key=string.format("%.6g",scale)
    local name=scales[key]
    if not name then
        name=SCALE.."_"..key
        EnvelopeManager:AddVector2Envelope(name,{{0,{.8*scale,.8*scale}},{1,{.64*scale,.64*scale}}})
        scales[key]=name
    end
    return name
end
local function envelopes()
    if initialized then return end
    EnvelopeManager:AddColourEnvelope(COLOUR,{
        {0,{1,1,1,0}},{.1,{1,1,1,1}},{.9,{1,1,1,1}},{1,{1,1,1,0}},
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
        -- Normal simulation already advances particle age once per frame.
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
-- VFX emitters need the native SpawnPrefab completion hook to create their
-- render nodes. A bare CreateEntity used after world startup skips that hook.
function M.create_emitter()
    envelopes()
    local fx=CreateEntity()
    fx.entity:AddTransform()
    fx.entity:SetCanSleep(false)
    fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
    local effect=fx.entity:AddVFXEffect()
    effect:InitEmitters(1)
    effect:SetRenderResources(0,"fx/miasma.tex","shaders/vfx_particle.ksh")
    effect:SetMaxNumParticles(0,50)
    effect:SetRotationStatus(0,true)
    effect:SetMaxLifetime(0,LIFETIME)
    effect:SetColourEnvelope(0,COLOUR)
    effect:SetScaleEnvelope(0,scale_envelope(1))
    effect:SetUVFrameSize(0,.5,1)
    effect:SetBlendMode(0,BLENDMODE.AlphaBlended)
    effect:SetSortOrder(0,0)
    effect:SetSortOffset(0,0)
    effect:SetRadius(0,require("nw/dark_fog").radius)
    effect:SetDragCoefficient(0,.1)
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
    local circle=CreateCircleEmitter(math.max(0,radius-.8*scale*1.3))
    local function emit()
        local x,z=circle()
        effect:AddRotatingParticleUV(0,LIFETIME,x,.5*scale*(1+math.random()),z,
            .01*scale*UnitRand(),.005*scale*UnitRand(),.01*scale*UnitRand(),
            math.random()*360,UnitRand()*.1,math.random(0,1)*.5,0)
    end
    -- Prewarm the short-lived spell cloud instead of waiting for a five-second
    -- native particle cycle; density is reduced to match its smaller footprint.
    for i=1,10 do emit() end
    effect:FastForward(0,.55)
    local pending=0
    EmitterManager:AddEmitter(fx,nil,function()
        if not inst:IsValid() or inst._nw_dark_visual_fading then return end
        pending=pending+2*TheSim:GetTickTime()
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
    -- Late replicas must not flash a fresh cloud after coverage has ended.
    if inst._nw_dark_dissipating:value() then M.dissipate(inst);return end

    particles(inst)
end
return M
