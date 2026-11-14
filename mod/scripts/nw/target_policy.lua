local M={}
local exempt={fishingrod=true,oceanfishingrod=true,voidcloth_scythe=true,farm_hoe=true,shieldofterror=true}
local actions={detonate=true,guard_ring=true}
local empty={}
local ignored=setmetatable({},{__mode="k"})
local aftermath=setmetatable({},{__mode="k"})
function M.exempt(p)
    return p and (actions[p.id] or exempt[p.engraving]) or false
end
function M.flags(p,stage)
    local flags=p and p.flags or empty
    local followup=stage=="aftermath"
    if not followup and not M.exempt(p) then return flags end
    if followup and flags._nw_target_bypass then return flags end
    if not followup and not flags.targets then return flags end
    local cache=followup and aftermath or ignored
    local view=cache[flags]
    if not view then
        view={}
        for k,v in pairs(flags) do if k~="targets" then view[k]=v end end
        if followup then view._nw_target_bypass=true end
        cache[flags]=view
    end
    return view
end
function M.infinite_pierce(p)
    return p and (p.id=="edge_yellowstaff" or p.id=="edge_opalstaff") or false
end
return M
