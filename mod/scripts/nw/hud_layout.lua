local M={slot=76,mana_width=92,mana_height=12,status_y=56}
function M.frame_width(count)
    -- Leave room for the status controls and guide button even with two slots.
    return math.max(268,count*M.slot+40)
end
function M.bounds(count)
    -- Include a small safe margin around the custom frame's fixed-size corners.
    return M.frame_width(count)+12,-57,89
end
function M.slot_at(x,y,count)
    if math.abs(y)>(M.slot-2)/2 then return nil end
    local i=math.floor((x+count*M.slot/2)/M.slot)+1
    if i<1 or i>count then return nil end
    local cx=(i-(count+1)/2)*M.slot
    return math.abs(x-cx)<=(M.slot-2)/2 and i or nil
end
function M.state(mana,maximum,cooling,total,cancast)
    local fill=maximum>0 and math.max(0,math.min(1,mana/maximum)) or 0
    local progress=cooling>0 and 1-math.min(1,cooling/math.max(1,total)) or 1
    return fill,progress,cooling>0 and "cooling" or cancast and "ready" or "blocked"
end
return M
