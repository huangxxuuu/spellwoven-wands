-- Native dumbbell landing animation only; no item, damage or secondary effects.
local out={}
for _,bank in ipairs({"dumbbell","dumbbell_golden","dumbbell_marble","dumbbell_gem",
    "dumbbell_heat","dumbbell_redgem","dumbbell_bluegem"}) do
    local function fn()
        local inst=CreateEntity()
        inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddNetwork()
        inst.AnimState:SetBank(bank);inst.AnimState:SetBuild(bank)
        inst.AnimState:PlayAnimation("land",false)
        inst:AddTag("FX");inst:AddTag("NOCLICK")
        inst.entity:SetPristine();inst.persists=false
        if not TheWorld.ismastersim then return inst end
        inst:ListenForEvent("animover",inst.Remove)
        inst:DoTaskInTime(1,inst.Remove)
        return inst
    end
    out[#out+1]=Prefab("nw_tool_land_"..bank,fn,{Asset("ANIM","anim/"..bank..".zip")})
end
return unpack(out)
