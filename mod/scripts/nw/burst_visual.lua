local C=require("nw/constants/visuals/burst_visual")
local M={}
function M.attach(inst)
    if TheNet:IsDedicated() then return end
    local started,queued=false,false
    local function refresh()
        queued=false
        local radius=inst._radius:value()
        if started or radius<=0 then return end
        started=true
        local x,_,z=inst.Transform:GetWorldPosition()
        for i=0,C.satellite_count do
            local fx=CreateEntity()
            fx.entity:AddTransform();fx.entity:AddAnimState();fx.entity:SetCanSleep(false)
            fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
            fx.Transform:SetFromProxy(inst.GUID)
            local angle=i*C.angular_step
            local r=i==0 and 0 or radius*C.ring_radius
            fx.Transform:SetPosition(x+math.cos(angle)*r,C.height,z+math.sin(angle)*r)
            local scale=math.max(C.minimum_scale,radius/C.radius_scale)*(i==0 and C.center_scale or C.satellite_scale)
            fx.Transform:SetScale(scale,scale,scale)
            fx.AnimState:SetBank("explode");fx.AnimState:SetBuild("explode")
            fx.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
            fx.AnimState:PlayAnimation("small")
            fx.AnimState:SetLightOverride(1)
            fx:ListenForEvent("animover",fx.Remove)
        end
    end
    local function schedule()
        if started or queued then return end
        queued=true
        inst:DoTaskInTime(0,refresh)
    end
    inst:ListenForEvent("nw_blastradiusdirty",schedule)
    schedule()
    return schedule
end
return M
