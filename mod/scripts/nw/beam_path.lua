local C=require("nw/constants/projectile_runtime").beam
local M={hold=C.hold,fade=C.fade,lifetime=C.hold+C.fade,interval=C.interval,snapshot_interval=C.snapshot_interval}
M.front_max_age=M.snapshot_interval*C.front_snapshot_count+1/C.front_frame_rate
M.front_max_distance=require("nw/spell_limits").max_speed*M.front_max_age

function M.width(age)
    return math.max(0,math.min(1,(M.lifetime-math.max(0,age))/M.fade))
end

function M.encode(segments,now)
    local rows={string.format("1,%.3f",now)}
    for _,s in ipairs(segments) do
        local age=math.max(0,now-s.born)
        if age<M.lifetime then
            rows[#rows+1]=string.format("%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f",
                s.id,s.x1,s.z1,s.x2,s.z2,age,s.radius)
        end
    end
    return table.concat(rows,";")
end

function M.decode(text)
    if type(text)~="string" or text=="" then return end
    local rows={}
    for row in text:gmatch("[^;]+") do rows[#rows+1]=row end
    if not rows[1] then return end
    local version,stamp=rows[1]:match("^(%d+),([%d%.%-]+)$")
    if version~="1" or not tonumber(stamp) then return end
    local result={time=tonumber(stamp),segments={}}
    for index=2,#rows do
        local values={}
        for value in rows[index]:gmatch("[^,]+") do
            local number=tonumber(value)
            if not number or number~=number or math.abs(number)==math.huge then return end
            values[#values+1]=number
        end
        if #values~=7 or values[1]<1 or values[1]%1~=0 or values[6]<0 or values[7]<0 then return end
        result.segments[#result.segments+1]={id=values[1],x1=values[2],z1=values[3],
            x2=values[4],z2=values[5],age=values[6],radius=values[7]}
    end
    return result
end

return M
