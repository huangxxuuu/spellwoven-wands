local function fn()
    local inst=Prefabs.gunpowder.fn()
    inst:AddTag("NOCLICK")
    inst:RemoveTag("molebait")
    if not TheWorld.ismastersim then return inst end
    inst.components.inventoryitem.canbepickedup=false
    inst.components.burnable:SetOnExtinguishFn(function(self)
        self.SoundEmitter:KillSound("hiss")
        self:Remove()
    end)
    function inst:Launch(owner,p,x,z,dx,dz,cleanup)
        self.Transform:SetPosition(x,0,z)
        self._nw_owner=owner
        self.components.explosive:SetAttacker(owner)
        self:ListenForEvent("onremove",cleanup)
        if require("nw/ground_fields").sink(self) then return end
        require("nw/field_motion").start(self,owner,p,dx,dz)
        if self:IsValid() then self.components.burnable:Ignite(true,owner) end
    end
    return inst
end
return Prefab("nw_gunpowder",fn,nil,{"gunpowder"})
