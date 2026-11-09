-- One replicated burst anchor supplies the position/radius. The five detached
-- smoke animations are local, silent and free to finish after the anchor dies.
local M={}
function M.attach(inst)
    if TheNet:IsDedicated() then return end
    local started=false
    local function refresh()
        local radius=inst._radius:value()
        if started or radius<=0 then return end
        started=true
        local x,_,z=inst.Transform:GetWorldPosition()
        for i=0,4 do
            local fx=CreateEntity()
            fx.entity:AddTransform();fx.entity:AddAnimState();fx.entity:SetCanSleep(false)
            fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
            fx.Transform:SetFourFaced()
            local angle=i*2.399
            local r=i==0 and 0 or radius*.38
            fx.Transform:SetPosition(x+math.cos(angle)*r,.15,z+math.sin(angle)*r)
            local scale=math.max(.25,radius/3)*(i==0 and 1.1 or .65)
            fx.Transform:SetScale(scale,scale,scale)
            fx.AnimState:SetBank("explode");fx.AnimState:SetBuild("explode")
            fx.AnimState:PlayAnimation("small")
            fx.AnimState:SetLightOverride(1)
            fx:ListenForEvent("animover",fx.Remove)
        end
    end
    inst:ListenForEvent("nw_blastradiusdirty",refresh)
    inst:DoTaskInTime(0,refresh)
    return refresh
end
return M
