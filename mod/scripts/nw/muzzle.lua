local C=require("nw/constants/visuals/muzzle")
local U=require("nw/util")
local Visual=require("nw/visual")
local M={default_height=C.default_height}
function M.offset(capacity)
    local tip=capacity<=C.short_capacity and C.short_tip*Visual.scale.short or capacity<=C.medium_capacity and C.medium_tip*Visual.scale.medium or C.long_tip*Visual.scale.long
    return tip*Visual.held_multiplier
end
function M.origin(owner,capacity,dx,dz,aim_distance,instant)
    local x,y,z=owner.Transform:GetWorldPosition()
    local forward=capacity<=C.short_capacity and C.short_forward or capacity<=C.medium_capacity and C.medium_forward or C.long_forward
    local height=M.default_height
    local source="fallback"
    local riding=owner.components and owner.components.rider and owner.components.rider:IsRiding()
    local pose=not riding and owner._nw_pose_hold and owner.sg and owner.sg.currentstate
        and owner.sg.currentstate.name=="nw_hold_pose"
    -- Instant casts can precede the pose RPC, or occur during pre/release.
    -- The held build's head is negative local Y in native idle as well.
    local actual_tip=not riding and (instant or pose)
    local tip_x,tip_z
    if riding then height=height+C.riding_height end
    if owner.AnimState and owner.AnimState.GetSymbolPosition then
        local hx,hy,hz,hand_found=owner.AnimState:GetSymbolPosition("swap_object",0,0,0)
        if hand_found and U.finite(hx) and U.finite(hy) and U.finite(hz)
            and hy-y>C.min_height and hy-y<C.max_height and (hx-x)^2+(hz-z)^2<C.max_hand_distance_squared then
            height=hy-y
            source="hand"
        end
        local sampleoffset=actual_tip and -M.offset(capacity) or M.offset(capacity)
        local sx,sy,sz,found=owner.AnimState:GetSymbolPosition("swap_object",0,sampleoffset,0)
        -- A front-facing braced staff can legitimately end close to the ground.
        -- Keep rejecting underground samples, without reverting a low tip to the hand.
        local min_height=actual_tip and C.held_min_height or C.min_height
        if found and U.finite(sx) and U.finite(sy) and U.finite(sz)
            and sy-y>min_height and sy-y<C.max_height and (sx-x)^2+(sz-z)^2<C.max_hand_distance_squared then
            if actual_tip then
                tip_x,tip_z=sx-x,sz-z
                height=sy-y
                source="tip"
            else
                forward=math.max(forward,math.min(C.max_forward,(sx-x)*dx+(sz-z)*dz))
            end
        end
    end
    -- The held animation owns the full tip displacement, including sideways motion
    -- and recoil. Clearance must follow that segment instead of the aiming ray.
    local ox,oz=tip_x or dx*forward,tip_z or dz*forward
    local distance=tip_x and math.sqrt(ox*ox+oz*oz) or forward
    if aim_distance and distance>aim_distance*C.aim_fraction then
        local scale=aim_distance*C.aim_fraction/distance
        ox,oz=ox*scale,oz*scale
        distance=aim_distance*C.aim_fraction
    end
    if aim_distance and TheWorld.Map then
        local ex,ez=x+ox,z+oz
        local hit=require("nw/geometry").hit
        local t=1
        for _,e in ipairs(require("nw/spell_effects").near(x,z,distance+C.query_padding)) do
            if e~=owner and e:IsValid() and e.components.health and not e.components.health:IsDead() then
                local tx,_,tz=e.Transform:GetWorldPosition()
                t=math.min(t,hit(x,z,ex,ez,tx,tz,math.min(C.max_radius,e:GetPhysicsRadius(C.default_radius))+C.hit_padding) or 1)
            end
        end
        for i=1,C.ground_steps do
            if not TheWorld.Map:IsPassableAtPoint(x+ox*i/C.ground_steps,0,z+oz*i/C.ground_steps,true) then
                t=math.min(t,(i-1)/C.ground_steps);break
            end
        end
        ox,oz=ox*t,oz*t
    end
    return x+ox,y+height,z+oz,source
end
return M
