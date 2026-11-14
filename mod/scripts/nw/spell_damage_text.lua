local P=require("nw/spell_parameter_text")
local Locale=require("nw/locale")
local D=require("nw/definitions")
local M={}
function M.get(id, fallback)
    local d=D.spells[id]
    if not d then return fallback end
    local rate=d.base_damage_multiplier or 1
    if rate==1 then return fallback end
    local key=(id=="fire_hit" or id=="fire_timer") and "fire" or id
    local text=(d.damage~=nil or d.explosion_damage or d.effect_damage or key=="gunpowder") and P.effect(key,d)
    if text then
        if key=="fire" and id~=key then text=text..(fallback:match("\n.*") or "") end
        if require("nw/arsenal").notes[id] then text=text.." "..require("nw/arsenal").tone_description(id) end
        return text
    end
    if d.planar and fallback then
        local label=Locale.t(" 位面伤害 ")
        local start,finish=fallback:find(label,1,true)
        if start then
            local number_end=fallback:find("[^%d%.]",finish+1) or (#fallback+1)
            return fallback:sub(1,finish)..string.format("%g",d.planar)..fallback:sub(number_end)
        end
    end
    return fallback
end
return M
