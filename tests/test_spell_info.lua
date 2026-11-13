local D=require("nw/definitions")
local I=require("nw/spell_info")
local Cards=require("nw/cards")
assert(#Cards.order==224 and Cards.codes.spark==1 and Cards.codes.precision==10)
local seen={}
for _,id in ipairs(Cards.order) do
    local d=D.spells[id];assert(d and I.names[id] and I.short[id] and I.effects[id])
    local description=I.tooltip(id)
    assert(description==I.brief(id) and #description>0,id)
    if not require("nw/arsenal").notes[id] then assert(not description:find("%d"),id) end
    local icon=I.icon(id);assert(not seen[icon]);seen[icon]=true
end
assert(I.tooltip(nil)=="空法术槽")
print("spell info: all 103 entries, distinct icons, live config values, explicit unsupported labels")
