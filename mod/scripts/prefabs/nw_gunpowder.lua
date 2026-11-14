local C=require("nw/constants/native").physics
local Copy=require("nw/util").copy
local Motion=require("nw/field_motion")
local function owner(inst)
    local Stored=require("nw/persistent_fields")
    local e=Stored.caster(inst._nw_owner)
    if not e then
        for _,player in ipairs(AllPlayers) do
            if inst._nw_powder and inst._nw_powder.userid and player.userid==inst._nw_powder.userid then
                e=Stored.caster(player);break
            end
        end
    end
    inst._nw_owner=e
    inst.components.explosive:SetAttacker(e)
    if inst._nw_powder then require("nw/journal_damage").tag(inst,e,inst._nw_powder.p) end
    return e
end
local function start(inst,data,caster)
    inst._nw_powder=Copy(data)
    data=inst._nw_powder
    data.p._nw_root=require("nw/balance_damage").root(data.p._nw_root)
    require("nw/balance_damage").tag(inst,data.p)
    inst._nw_owner=caster
    if not caster and data.neutral then
        local x,_,z=inst.Transform:GetWorldPosition()
        inst._nw_owner=require("nw/payload_caster").neutral(x,z)
    end
    require("nw/payload_caster").retain(inst._nw_owner,inst)
    inst._nw_motion_owner=owner
    local p=data.p
    local explosive=inst.components.explosive
    explosive.explosivedamage=p.flags.harmless and 0 or math.max(0,
        (inst._nw_base_damage*(p.base_damage_multiplier or 1)+(p.native_damage_add or 0))*(p.native_damage_mult or 1)*(p.effect_scale or 1))
    explosive.explosiverange=inst._nw_base_radius*require("nw/projectile_size").factor(p)
    require("nw/projectile_size").field(inst,p)
    local burnable=inst.components.burnable
    local remaining=math.max(0,data.remaining)
    inst._nw_fuse_deadline=GetTime()+remaining
    burnable:SetBurnTime(remaining)
    inst.entity:SetCanSleep(false)
    if Motion.start(inst,owner(inst),p,data.dx,data.dz,data.age,data.motion)==false then return end
    if inst:IsValid() then
        if burnable:IsBurning() then burnable:ExtendBurning() else burnable:Ignite(true,owner(inst)) end
    end
end
local function fn()
    local inst=Prefabs.gunpowder.fn()
    inst:AddTag("NOCLICK")
    inst:RemoveTag("molebait")
    MakeProjectilePhysics(inst,C.mass,C.radius)
    inst._nw_ground_mask=true
    if not TheWorld.ismastersim then return inst end
    inst._nw_base_damage=inst.components.explosive.explosivedamage
    inst._nw_base_radius=inst.components.explosive.explosiverange
    inst.components.inventoryitem.canbepickedup=false
    inst.components.burnable:SetOnExtinguishFn(function(self)
        self.SoundEmitter:KillSound("hiss")
        self:Remove()
    end)
    local explode=inst.components.explosive.onexplodefn
    inst.components.explosive:SetOnExplodeFn(function(self)
        owner(self)
        if self._nw_powder and require("nw/projectile_size").factor(self._nw_powder.p)~=1 then
            self.SoundEmitter:KillSound("hiss")
            local fx=SpawnPrefab("explode_small")
            if fx then
                fx.Transform:SetPosition(self.Transform:GetWorldPosition())
                require("nw/projectile_size").visual(fx,require("nw/projectile_size").factor(self._nw_powder.p))
            end
        elseif explode then explode(self) end
    end)
    local save,load=inst.OnSave,inst.OnLoad
    inst.OnSave=function(self,data)
        local refs=save and save(self,data)
        if self._nw_powder then
            data.nw_powder=Copy(self._nw_powder)
            data.nw_powder.remaining=math.max(0,self._nw_fuse_deadline-GetTime())
            if self._nw_motion then
                local m=self._nw_motion
                data.nw_powder.dx,data.nw_powder.dz,data.nw_powder.age=m.dx,m.dz,m.age
                data.nw_powder.motion=Motion.save(self)
            end
        end
        return refs
    end
    inst.OnLoad=function(self,data,...)
        if load then load(self,data,...) end
        if data and data.nw_powder then
            self:DoTaskInTime(0,function() start(self,data.nw_powder) end)
        else
            self:DoTaskInTime(0,function() self:Remove() end)
        end
    end
    function inst:Launch(owner,p,x,z,dx,dz,cleanup)
        self.Transform:SetPosition(x,0,z)
        self._nw_owner=owner
        self.components.explosive:SetAttacker(owner)
        self:ListenForEvent("onremove",cleanup)
        if require("nw/ground_fields").sink(self) then return end
        start(self,{p=p,dx=dx,dz=dz,remaining=self.components.burnable.burntime*(p.fuse_mult or 1),
            userid=require("nw/persistent_fields").userid(owner),neutral=owner and owner._nw_neutral or nil},owner)
    end
    return inst
end
return Prefab("nw_gunpowder",fn,nil,{"gunpowder"})
