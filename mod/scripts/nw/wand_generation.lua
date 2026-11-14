local C=require("nw/constants/wands")
local M=require("nw/util").copy(C.generation)
function M.distribution(tier,kind,key)
    local row=assert(M.tiers[tier],"invalid tier")[key]
    local profile=assert(M.types[kind],"invalid archetype")
    local scale=key=="recharge" and require("nw/balance").is_balanced() and C.balance.recharge_mult or 1
    return row[1]*scale,row[2]*scale,(row[3]+(profile.offset[key] or 0)*row[4])*scale,
        row[4]*(profile.width or 1)*scale,M.bounds[key][3]*scale
end
return M
