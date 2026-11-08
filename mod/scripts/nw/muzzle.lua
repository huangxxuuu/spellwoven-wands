local U=require("nw/util")
local Visual=require("nw/visual")
local M={default_height=1.2}
-- Same tip distances as the three held layouts in nw_parts. Animation XML
-- uses negative Y upwards; GetSymbolPosition's offset uses positive Y upwards.
-- These offsets only retain the existing horizontal clearance, not flight height.
function M.offset(capacity)
    local tip=capacity<=4 and 80*Visual.scale.short or capacity<=8 and 94*Visual.scale.medium or 110*Visual.scale.long
    return tip*Visual.held_multiplier
end
function M.origin(owner,capacity,dx,dz,aim_distance)
    local x,y,z=owner.Transform:GetWorldPosition()
    local forward=capacity<=4 and 1 or capacity<=8 and 1.2 or 1.4
    -- Use the grip itself, without the old tip offset or length-dependent floor.
    -- The fallback also covers custom characters/headless hosts without a symbol.
    local height=M.default_height
    local source="fallback"
    if owner.components and owner.components.rider and owner.components.rider:IsRiding() then height=height+1 end
    if owner.AnimState and owner.AnimState.GetSymbolPosition then
        local hx,hy,hz,hand_found=owner.AnimState:GetSymbolPosition("swap_object",0,0,0)
        if hand_found and U.finite(hx) and U.finite(hy) and U.finite(hz)
            and hy-y>.2 and hy-y<4.5 and (hx-x)^2+(hz-z)^2<16 then
            height=hy-y
            source="hand"
        end
        local sx,sy,sz,found=owner.AnimState:GetSymbolPosition("swap_object",0,M.offset(capacity),0)
        -- The symbol may be unavailable on custom characters or headless hosts.
        if found and U.finite(sx) and U.finite(sy) and U.finite(sz)
            and sy-y>.2 and sy-y<4.5 and (sx-x)^2+(sz-z)^2<16 then
            forward=math.max(forward,math.min(1.7,(sx-x)*dx+(sz-z)*dz))
        end
    end
    if aim_distance then forward=math.min(forward,aim_distance*.8) end
    if aim_distance and TheWorld.Map then
        -- Never spawn on the far side of a point-blank target or wall.
        local ex,ez=x+dx*forward,z+dz*forward
        local hit=require("nw/geometry").hit
        local t=1
        for _,e in ipairs(require("nw/spell_effects").near(x,z,forward+3.12)) do
            if e~=owner and e:IsValid() and e.components.health and not e.components.health:IsDead() then
                local tx,_,tz=e.Transform:GetWorldPosition()
                t=math.min(t,hit(x,z,ex,ez,tx,tz,math.min(3,e:GetPhysicsRadius(.5))+.12) or 1)
            end
        end
        for i=1,3 do
            if not TheWorld.Map:IsPassableAtPoint(x+dx*forward*i/3,0,z+dz*forward*i/3,true) then
                t=math.min(t,(i-1)/3);break
            end
        end
        forward=forward*t
    end
    return x+dx*forward,y+height,z+dz*forward,source
end
return M
