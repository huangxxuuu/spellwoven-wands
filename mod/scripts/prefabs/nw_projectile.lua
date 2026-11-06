local Effects=require("nw/spell_effects")
local Projectiles=require("nw/projectiles")
local assets = { Asset("ANIM","anim/nw_spell_world.zip"), Asset("ANIM", "anim/nw_objects.zip"), Asset("ANIM", "anim/nw_spark_flight.zip") }
local Cards=require("nw/cards")
local Size=require("nw/projectile_size")
local scales={arrow=1.6,heavy=2,scatter=1.4}
local function refresh(inst)
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
    require("nw/flight_visual").attach(inst,id)
    local scale=scales[id] or 1.6
    inst._visual.Transform:SetScale(scale,scale,scale)
    size()
end
local function fn(breakable)
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
    inst.entity:SetPristine()
    inst.persists=false
    -- Physics stays on the ground plane, as in native staff projectiles.
    -- A local child renders at the actual wand-tip height without gravity,
    -- extra network entities or per-frame transform writes.
    if not TheNet:IsDedicated() then
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
                Effects.blast(owner,bx,bz,{damage=self._shot.damage,radius=Size.factor(self._shot.p),flags=self._shot.p.flags})
                require("nw/projectile_triggers").finish(self._shot,bx,bz)
                self:Remove()
            end
        end
        self._spell:set(Cards.codes[descriptor.base or descriptor.id] or 1)
        self._height:set(height or 1.4)
        self._size:set(Size.factor(descriptor))
        self._shot={owner=owner,damage=descriptor.damage,speed=descriptor.speed,
            remaining=descriptor.lifetime,travelled=0,dx=dx,dz=dz,height=height or 1.4,
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
            self:ListenForEvent("onremove",function() if ring:IsValid() then ring:Remove() end end)
        end
        if descriptor.flags.light then
            local glow=SpawnPrefab("nw_flyinglight")
            glow.entity:SetParent(self.entity)
            self:ListenForEvent("onremove",function() if glow:IsValid() then glow:Remove() end end)
        end
        self.Transform:SetPosition(x,0,z)
        refresh(self)
        self:ListenForEvent("onremove",onremove)
        self.Transform:SetRotation(-math.atan2(dz,dx)/DEGREES)
        local speed=math.sqrt(self._shot.vx^2+self._shot.vz^2)
        self.Physics:SetMotorVel(speed,0,0)
        if descriptor.engraving then require("nw/engraved_flight").launch(self,self._shot);refresh(self) end
        Projectiles.add(self)
    end
    return inst
end
return Prefab("nw_projectile",function() return fn(false) end,assets,{"lighterfire"}),Prefab("nw_spore_ball_flight",function() return fn(true) end,assets)
