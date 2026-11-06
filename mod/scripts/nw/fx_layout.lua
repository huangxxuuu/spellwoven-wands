local M={pixels_per_unit=150,blast_pixels=256,arc_pixels=324,arc_thickness=1}

-- Local segments start at the first target and partition exactly the vector
-- to the second. Scaling uses the real bitmap width compiled by Klei.
function M.arc(dx,dz)
    local length=math.sqrt(dx*dx+dz*dz)
    if length<.001 then return 0 end
    local count=math.max(1,math.floor(length*M.pixels_per_unit/M.arc_pixels+.5))
    return count,length/count*M.pixels_per_unit/M.arc_pixels,-math.deg(math.atan2(dz,dx))
end

function M.blast_scale(radius)
    return 2*radius*M.pixels_per_unit/M.blast_pixels
end
return M
