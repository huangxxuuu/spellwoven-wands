local Stages=require("nw/field_stages")
local assets={Asset("ANIM","anim/nw_field_stages.zip")}
local function make(name,id)
    return Prefab(name,function()
        local inst=CreateEntity()
        inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddNetwork()
        inst.entity:SetCanSleep(false)
        inst:AddTag("FX");inst:AddTag("NOCLICK")
        if id then Stages.setup(inst,id)
        else
            inst.AnimState:SetBank(Stages.bank);inst.AnimState:SetBuild(Stages.bank)
            inst.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
        end
        inst.entity:SetPristine()
        if id then Stages.attach(inst,id) end
        if not TheWorld.ismastersim then return inst end
        inst.persists=false
        function inst:SetStage(field,phase,size,radius,count,age,seed)
            Stages.effect_state(self,field,phase,size,radius,count,age,seed)
            self:DoTaskInTime(Stages.duration(field,phase),self.Remove)
        end
        return inst
    end,assets)
end
return make("nw_field_stage_fx"),make("nw_guard_stage_fx","guard_ring"),make("nw_vital_stage_fx","vital_ring")
