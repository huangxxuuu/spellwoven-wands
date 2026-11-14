local C=require("nw/constants/visuals/muzzle")
local U=require("nw/util")
local Visual=require("nw/visual")
local M={default_height=C.default_height}
function M.offset(capacity)
    local tip=capacity<=C.short_capacity and C.short_tip*Visual.scale.short or capacity<=C.medium_capacity and C.medium_tip*Visual.scale.medium or C.long_tip*Visual.scale.long
    return tip*Visual.held_multiplier
end
function M.origin(owner,capacity,dx,dz,aim_distance)
    local x,y,z=owner.Transform:GetWorldPosition()
    local forward=capacity<=C.short_capacity and C.short_forward or capacity<=C.medium_capacity and C.medium_forward or C.long_forward
    local height=M.default_height
    local source="fallback"
    if owner.components and owner.components.rider and owner.components.rider:IsRiding() then height=height+C.riding_height end
    if owner.AnimState and owner.AnimState.GetSymbolPosition then
        local hx,hy,hz,hand_found=owner.AnimState:GetSymbolPosition("swap_object",0,0,0)
        if hand_found and U.finite(hx) and U.finite(hy) and U.finite(hz)
            and hy-y>C.min_height and hy-y<C.max_height and (hx-x)^2+(hz-z)^2<C.max_hand_distance_squared then
            height=hy-y
            source="hand"
        end
        local sx,sy,sz,found=owner.AnimState:GetSymbolPosition("swap_object",0,M.offset(capacity),0)
        if found and U.finite(sx) and U.finite(sy) and U.finite(sz)
            and sy-y>C.min_height and sy-y<C.max_height and (sx-x)^2+(sz-z)^2<C.max_hand_distance_squared then
            forward=math.max(forward,math.min(C.max_forward,(sx-x)*dx+(sz-z)*dz))
        end
    end
    if aim_distance then forward=math.min(forward,aim_distance*C.aim_fraction) end
    if aim_distance and TheWorld.Map then
        local ex,ez=x+dx*forward,z+dz*forward
        local hit=require("nw/geometry").hit
        local t=1
        for _,e in ipairs(require("nw/spell_effects").near(x,z,forward+C.query_padding)) do
            if e~=owner and e:IsValid() and e.components.health and not e.components.health:IsDead() then
                local tx,_,tz=e.Transform:GetWorldPosition()
                t=math.min(t,hit(x,z,ex,ez,tx,tz,math.min(C.max_radius,e:GetPhysicsRadius(C.default_radius))+C.hit_padding) or 1)
            end
        end
        for i=1,C.ground_steps do
            if not TheWorld.Map:IsPassableAtPoint(x+dx*forward*i/C.ground_steps,0,z+dz*forward*i/C.ground_steps,true) then
                t=math.min(t,(i-1)/C.ground_steps);break
            end
        end
        forward=forward*t
    end
    return x+dx*forward,y+height,z+dz*forward,source
end
return M
