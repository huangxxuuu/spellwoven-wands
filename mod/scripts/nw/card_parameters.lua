local Copy=require("nw/util").copy
local groups={
    projectile=require("nw/constants/projectiles").cards,
    trigger=require("nw/constants/projectiles").cards,
    field=require("nw/constants/fields").cards,
    modifier=require("nw/constants/modifiers").cards,
    multicast=require("nw/constants/multicast").cards,
    melee=require("nw/constants/melee").cards,
    instant=require("nw/constants/instant").cards,
    note=require("nw/constants/audio").cards,
}
local M={}
function M.get(kind,id)
    local d=Copy(assert(groups[kind] and groups[kind][id],"Unknown card parameters: "..tostring(id)))
    d.id,d.kind=id,kind
    return d
end
return M
