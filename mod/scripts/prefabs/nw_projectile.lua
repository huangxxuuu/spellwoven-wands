local Effects=require("nw/spell_effects")
local Projectiles=require("nw/projectiles")
local assets = { Asset("ANIM","anim/nw_spell_world.zip"), Asset("ANIM", "anim/nw_objects.zip"), Asset("ANIM", "anim/nw_spark_flight.zip"), Asset("ANIM", "anim/nw_elemental_flight.zip"), Asset("ANIM", "anim/wagdrone_laserwire_fx.zip") }
assets[#assets+1]=Asset("ANIM","anim/nw_tool_flight.zip")
-- These tools play native banks directly on a local visual; declare them even
-- when the corresponding inventory item has never appeared in this world.
for _,bank in ipairs({"chum_pouch","oceanfishing_hook","fan_wheel","dumbbell","dumbbell_golden",
    "dumbbell_marble","dumbbell_gem","dumbbell_heat","dumbbell_redgem","dumbbell_bluegem"}) do
    assets[#assets+1]=Asset("ANIM","anim/"..bank..".zip")
end
local Cards=require("nw/cards")
local Size=require("nw/projectile_size")
local AnimatedFlight=require("nw/elemental_flight")
local Muzzle=require("nw/muzzle")
local function refresh(inst)
    if inst._beam_path then
        if not TheNet:IsDedicated() then require("nw/beam_visual").attach(inst) end
        return
    end
    if not inst._visual then return end
    local id=Cards.bycode[inst._spell:value()]
    if not id then return end -- Wait for the replicated spell before choosing art.
    inst._visual.Transform:SetPosition(0,inst._height:value(),0)
    local function size() Size.visual(inst._visual,math.max(1,inst._size:value())) end
    if inst._visual_id==id then size();return end
    inst._visual_id=id
    local descriptor=require("nw/definitions").spells[id]
    if descriptor and descriptor.engraving then
        require("nw/engraved_flight").visual(inst,descriptor.engraving);size();return
    end
    if id=="spark" then
        local anim=inst._visual.AnimState
        anim:SetOrientation(ANIM_ORIENTATION.BillBoard)
        anim:SetBank("nw_spark_flight")
        anim:SetBuild("nw_spark_flight")
        anim:PlayAnimation("head",true)
        require("nw/spark_trail").attach(inst)
        size()
        return
    end
    if AnimatedFlight.supports(id) then
        AnimatedFlight.attach(inst,id)
        size()
        return
    end
    require("nw/flight_visual").attach(inst,id)
    local scale=1.6
    inst._visual.Transform:SetScale(scale,scale,scale)
    size()
end
local function fn(breakable,beam)
    local inst=CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddNetwork()
    -- Same physical movement path as native staff projectiles; hits remain
    -- server-side swept tests, so remove automatic physics collision response.
    MakeInventoryPhysics(inst)
    RemovePhysicsColliders(inst)
    -- An inventory item's restitution causes ground micro-bounces, followed
    -- by ground-height corrections. Flying spells must slide continuously.
    inst.Physics:SetFriction(0)
    inst.Physics:SetRestitution(0)
    inst._nw_ground_mask=true
    -- Short-lived physical shots must keep moving even without nearby players
    -- (dedicated server/offscreen). Lifetime and the projectile budget bound it.
    inst.entity:SetCanSleep(false)
    if breakable then inst:AddTag("nw_breakable") else inst:AddTag("FX");inst:AddTag("NOCLICK") end
    inst._spell=net_byte(inst.GUID,"nw_projectile.spell","nw_projectiledirty")
    inst._height=net_float(inst.GUID,"nw_projectile.height","nw_projectiledirty")
    inst._size=net_float(inst.GUID,"nw_projectile.size","nw_projectiledirty")
    if beam then
        inst._beam_path=net_string(inst.GUID,"nw_beam.path","nw_beamdirty")
        inst._beam_ended=net_bool(inst.GUID,"nw_beam.ended","nw_beamdirty")
    end
    inst.entity:SetPristine()
    inst.persists=false
    -- Physics stays on the ground plane, as in native staff projectiles.
    -- A local child renders at the actual wand-tip height without gravity,
    -- extra network entities or per-frame transform writes.
    if not beam and not TheNet:IsDedicated() then
        local visual=CreateEntity()
        visual.entity:AddTransform();visual.entity:AddAnimState()
        visual:AddTag("FX");visual:AddTag("NOCLICK");visual.persists=false
        visual.entity:SetParent(inst.entity)
        visual.AnimState:SetBank("nw_objects");visual.AnimState:SetBuild("nw_objects")
        -- The physics heading belongs to the ground plane; the painted body
        -- faces the camera, including engraving visuals that bypass flight_visual.
        visual.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
        visual.AnimState:SetLightOverride(1)
        inst._visual=visual
        inst:ListenForEvent("onremove",function() if visual:IsValid() then visual:Remove() end end)
    end
    if not TheWorld.ismastersim then
        inst:ListenForEvent("nw_projectiledirty",refresh);inst:DoTaskInTime(0,refresh)
        return inst
    end
    if breakable then require("nw/expanded_fields").attackable(inst) end
    if beam then
        inst._beam_head_fx={}
        function inst:StopBeamHead()
            for _,fx in ipairs(self._beam_head_fx) do if fx:IsValid() then fx:Remove() end end
            self._beam_head_fx={}
        end
        function inst:PublishBeam(segments,now,ended,force)
            local Path=require("nw/beam_path")
            if not force and now<(self._beam_next_publish or 0) then return end
            self._beam_next_publish=now+Path.snapshot_interval
            self._beam_path:set(Path.encode(segments,now))
            self._beam_ended:set(ended==true)
            if not TheNet:IsDedicated() then require("nw/beam_visual").refresh(self) end
        end
    end
    function inst:Launch(owner, descriptor, x,z, dx,dz, onremove,height)
        descriptor.flags=descriptor.flags or {}
        if require("nw/arsenal").notes[descriptor.id] then
            require("nw/expanded_fields").sound(owner,x,z,descriptor.id,descriptor.pitch)
        end
        if breakable then
            self._nw_owner=owner
            self._nw_break=function()
                if not self._shot then return end
                self._nw_break=nil
                local bx,_,bz=self.Transform:GetWorldPosition()
                Projectiles.contact_fx(self._shot,bx,bz)
                Effects.blast(owner,bx,bz,{damage=self._shot.damage,radius=Size.factor(self._shot.p),flags=self._shot.p.flags,quiet_burst=true,journal_id=self._shot.p.journal_id or self._shot.p.id})
                require("nw/projectile_triggers").finish(self._shot,bx,bz)
                self:Remove()
            end
        end
        self._spell:set(Cards.codes[descriptor.base or descriptor.id] or 1)
        height=height or Muzzle.default_height
        self._height:set(height)
        self._size:set(Size.factor(descriptor))
        self._shot={owner=owner,damage=descriptor.damage,speed=descriptor.speed,
            remaining=descriptor.lifetime,travelled=0,dx=dx,dz=dz,height=height,
            ignore_self=descriptor.flags.targets and descriptor.flags.targets.self,
            x=x,z=z,time=GetTime(),age=0,p=descriptor,hit={},
            bounces=descriptor.flags.bounce and descriptor.flags.bounce.bounces,
            hits_left=descriptor.flags.pierce_all and math.huge or descriptor.flags.pierce and descriptor.flags.pierce.hits}
        require("nw/flight").reset(self._shot,dx,dz)
        if descriptor.flags.halo then
            local ring=SpawnPrefab("nw_field_boundary")
            ring.entity:SetParent(self.entity)
            local scale=require("nw/fx_layout").blast_scale(.8*Size.factor(descriptor))
            ring.AnimState:SetScale(scale,scale)
            ring.AnimState:SetMultColour(1,.46,.13,.85)
            if beam then self._beam_head_fx[#self._beam_head_fx+1]=ring end
            self:ListenForEvent("onremove",function() if ring:IsValid() then ring:Remove() end end)
        end
        if descriptor.flags.light then
            local glow=SpawnPrefab("nw_flyinglight")
            glow.entity:SetParent(self.entity)
            if beam then self._beam_head_fx[#self._beam_head_fx+1]=glow end
            self:ListenForEvent("onremove",function() if glow:IsValid() then glow:Remove() end end)
        end
        self.Transform:SetPosition(x,0,z)
        self.Transform:SetRotation(-math.atan2(dz,dx)/DEGREES)
        refresh(self)
        self:ListenForEvent("onremove",onremove)
        local speed=math.sqrt(self._shot.vx^2+self._shot.vz^2)
        self.Physics:SetMotorVel(speed,0,0)
        if descriptor.engraving then require("nw/engraved_flight").launch(self,self._shot);refresh(self) end
        Projectiles.add(self)
    end
    return inst
end
return Prefab("nw_projectile",function() return fn(false) end,assets,{"lighterfire"}),
    Prefab("nw_spore_ball_flight",function() return fn(true) end,assets),
    Prefab("nw_end_beam",function() return fn(false,true) end,assets)
