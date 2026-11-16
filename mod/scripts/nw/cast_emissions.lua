local M={}
function M.new() return {permanent_spawned=0} end
local function registry()
    local pool=TheWorld._nw_cast_emissions
    if not pool then
        pool=setmetatable({},{__mode="v"})
        TheWorld._nw_cast_emissions=pool
    end
    return pool
end
function M.save(context)
    if not context.id then context.id=TheWorld.components.nw_identity:Next() end
    registry()[context.id]=context
    return {id=context.id,permanent_spawned=context.permanent_spawned}
end
function M.restore(data)
    if type(data)~="table" or type(data.id)~="string" or data.id==""
        or not require("nw/util").finite(data.permanent_spawned)
        or data.permanent_spawned<0 or data.permanent_spawned~=math.floor(data.permanent_spawned) then
        return M.new()
    end
    TheWorld.components.nw_identity:Observe(data.id)
    local pool=registry()
    local context=pool[data.id] or {id=data.id,permanent_spawned=0}
    context.permanent_spawned=math.max(context.permanent_spawned,data.permanent_spawned)
    pool[data.id]=context
    return context
end
return M
