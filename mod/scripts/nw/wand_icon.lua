local Visual=require("nw/visual")
local M={}
function M.layers(code,broken)
    local layers={}
    for i,name in ipairs(Visual.icon_parts(code,broken)) do
        layers[i]={atlas=Visual.atlas(code),image=name}
    end
    return layers
end
function M.install(inst)
    local previous_code,previous_broken,cached
    inst.layeredinvimagefn=function(item)
        local code=item._nw_look:value()
        local broken=item._nw_broken:value()
        if code~=previous_code or broken~=previous_broken then
            cached=M.layers(code,broken)
            previous_code,previous_broken=code,broken
        end
        return cached
    end
    inst:ListenForEvent("nw_lookdirty",function() inst:PushEvent("imagechange") end)
end
function M.recipe(tier)
    local layers=M.layers(Visual.recipe_code(tier),false)
    return function() return layers end
end
return M
