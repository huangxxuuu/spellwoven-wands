local Visual=require("nw/visual")
local Icon=require("nw/wand_icon")
local inst={code=0,broken=false,events={},changes=0}
inst._nw_look={value=function() return inst.code end}
inst._nw_broken={value=function() return inst.broken end}
function inst:ListenForEvent(event,fn) self.events[event]=fn end
function inst:PushEvent(event) assert(event=="imagechange");self.changes=self.changes+1 end
Icon.install(inst)
local seen={}
for code=0,Visual.count-1 do
    for _,broken in ipairs({false,true}) do
        inst.code,inst.broken=code,broken
        inst.events.nw_lookdirty()
        local layers=inst.layeredinvimagefn(inst)
        assert(layers==inst.layeredinvimagefn(inst),"unchanged look should reuse its layer list")
        local names=Visual.icon_parts(code,broken)
        assert(#layers==3 and #names==3)
        for i,row in ipairs(layers) do
            assert(row.atlas==Visual.atlas(code) and row.image==names[i] and row.offset==nil)
        end
        assert(layers[1].image:match("^body_") and layers[2].image:match("^tail_") and layers[3].image:match("^head_"))
        local key=table.concat(names,":")
        assert(not seen[key]);seen[key]=true
    end
end
assert(inst.changes==8748)
for tier=0,3 do
    local recipe=Icon.recipe(tier)
    local layers=recipe();assert(layers==recipe())
    local names=Visual.icon_parts(Visual.recipe_code(tier),false)
    for i,row in ipairs(layers) do assert(row.image==names[i]) end
end
-- A new client can render before the first dirty event; loading a changed look
-- or a repaired wand refreshes the image even if the image hash arrived first.
inst.code,inst.broken=27,true
assert(inst.layeredinvimagefn(inst)[3].image:find("_broken_",1,true))
inst.broken=false;inst.events.nw_lookdirty()
assert(not inst.layeredinvimagefn(inst)[3].image:find("_broken_",1,true))
print("wand icons: 8748 native layer lists, client dirty events, broken/repair transitions, caching and all recipe tiers")
