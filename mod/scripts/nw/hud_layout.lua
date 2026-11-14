local C=require("nw/constants/ui").hud_layout
local M={slot=C.slot,slot_step=C.slot_step,mana_width=C.mana_width,mana_height=C.mana_height,status_y=C.status_y}
function M.frame_width(count)
    return math.max(C.minimum_width,(count-1)*M.slot_step+M.slot+C.horizontal_padding)
end
function M.bounds(count)
    return M.frame_width(count)+C.bounds_padding,C.bottom,C.top
end
function M.slot_at(x,y,count)
    if math.abs(y)>(M.slot-C.slot_inset)/2 then return nil end
    local i=math.floor((x+count*M.slot_step/2)/M.slot_step)+1
    if i<1 or i>count then return nil end
    local cx=(i-(count+1)/2)*M.slot_step
    return math.abs(x-cx)<=(M.slot-C.slot_inset)/2 and i or nil
end
function M.state(mana,maximum,cooling,total,cancast)
    local fill=maximum>0 and math.max(0,math.min(1,mana/maximum)) or 0
    local progress=cooling>0 and 1-math.min(1,cooling/math.max(1,total)) or 1
    return fill,progress,cooling>0 and "cooling" or cancast and "ready" or "blocked"
end
return M
