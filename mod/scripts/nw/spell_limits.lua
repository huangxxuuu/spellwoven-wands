local C=require("nw/constants/limits")
local M={max_speed=C.max_speed,range=0,depth=0,boundary_cleanup=false,permanent_motion_cleanup=false}
function M.limit_velocity(vx,vz)
    local speed=math.sqrt(vx*vx+vz*vz)
    if speed>M.max_speed then
        local scale=M.max_speed/speed
        return vx*scale,vz*scale
    end
    return vx,vz
end
function M.motor_scale(inst)
    if not inst.Transform.GetScale then return 1,1 end
    local x,_,z=inst.Transform:GetScale()
    return math.max(C.min_motor_scale,math.abs(x or 1)),math.max(C.min_motor_scale,math.abs(z or x or 1))
end
function M.set_motor_velocity(inst,vx,vy,vz)
    vx,vz=M.limit_velocity(vx,vz)
    local sx,sz=M.motor_scale(inst)
    inst.Physics:SetMotorVel(vx/sx,vy,vz/sz)
end
function M.track(inst,owner,key)
    local list=owner[key] or {}
    owner[key]=list
    list[#list+1]=inst
    inst:ListenForEvent("onremove",function()
        for i,v in ipairs(list) do
            if v==inst then table.remove(list,i);break end
        end
    end)
end
return M
