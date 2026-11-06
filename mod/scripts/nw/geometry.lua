local M = {}
-- Earliest intersection between a swept point and a target circle.
function M.hit(ax, az, bx, bz, cx, cz, radius)
    local dx, dz, ox, oz = bx-ax, bz-az, ax-cx, az-cz
    local c = ox*ox+oz*oz-radius*radius
    if c <= 0 then return 0 end
    local a = dx*dx+dz*dz
    if a < 1e-12 then return nil end
    local b = 2*(ox*dx+oz*dz)
    local disc = b*b-4*a*c
    if disc < 0 then return nil end
    local t = (-b-math.sqrt(disc))/(2*a)
    return t >= 0 and t <= 1 and t or nil
end
return M
