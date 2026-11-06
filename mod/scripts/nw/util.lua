local M = {}
function M.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = M.copy(v) end
    return result
end
function M.finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
return M
