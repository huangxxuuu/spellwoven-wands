local M={order={"spark","arrow","heavy","scatter","double","triple","speed_up","speed_down","damage_up","precision",
    "fire","frost","sine","spiral","homing","bounce","pierce","explosion","chain","knockback","leech","light",
    "trigger_hit","trigger_timer","weak_homing"}}
local Info=require("nw/spell_info")
M.names=Info.names;M.short=Info.short;M.playable=Info.playable
local retired_code=193 -- target_players_all in 0.19.0
M.codes={}
M.bycode={[retired_code]="target_players_other"}
function M.migrate_id(id)
    return id=="target_players_all" and "target_players_other" or id
end
for i,id in ipairs(M.order) do M.codes[id]=i;M.bycode[i]=id end
for _,id in ipairs(require("nw/definitions").order) do
    if not M.codes[id] then
        M.order[#M.order+1]=id
        local code=#M.order
        if code>=retired_code then code=code+1 end
        M.codes[id]=code;M.bycode[code]=id
    end
end
function M.encode(cards,capacity)
    local result={}
    for i=1,capacity do result[i]=tostring(cards[i] and M.codes[cards[i].spell_id] or 0) end
    return table.concat(result,",")
end
function M.decode(s)
    local result={}
    for value in string.gmatch(s,"[^,]+") do result[#result+1]=M.bycode[tonumber(value)] or false end
    return result
end
return M
