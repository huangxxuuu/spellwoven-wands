local catalog = {}
local function family(materials, names)
    local set = {}
    for material in materials:gmatch("%S+") do set[material] = true end
    for name in names:gmatch("%S+") do catalog[name] = set end
end
for _,row in ipairs(require("nw/constants/acquisition").natural_families) do family(row[1],row[2]) end
return catalog
