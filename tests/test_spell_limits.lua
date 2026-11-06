local C=require("nw/compiler")
local L=require("nw/spell_limits")
local function wand(depth)
    local w=require("nw/generator").starter()
    w.stats.mana_max=10000;w.cards={}
    for i=1,depth do w.cards[i]={spell_id="trigger_hit",card_uid=tostring(i)} end
    w.cards[depth+1]={spell_id="spark",card_uid=tostring(depth+1)}
    w.runtime=C.initial(w.cards,w.stats,1)
    return w
end
assert(L.range==0 and L.depth==0 and not L.boundary_cleanup and not L.permanent_motion_cleanup)
local plan=assert(C.compile(wand(40)))
assert(#plan.blocks==41,"unlimited nesting must not hit the old node ceiling")
L.depth=30
plan=assert(C.compile(wand(30)));assert(#plan.blocks==31)
local w=wand(31)
local p,err=C.compile(w)
assert(not p and err=="COMPILE_LIMIT" and w.runtime.mana==10000 and #w.runtime.deck==32)
assert(C.compile(w,nil,{depth=0}),"explicit zero disables the configured cap")
L.depth=1
assert(C.compile(wand(1)))
assert(not C.compile(wand(2)))
L.depth=0
assert(C.compile(wand(31)))

-- Check the actual configurable values, including every layer up to 30.
local env=setmetatable({},{__index=_G})
local info=assert(loadfile("mod/modinfo.lua"));setfenv(info,env);info()
local options={}
for _,v in ipairs(env.configuration_options) do options[v.name]=v end
assert(options.limit_range.default==0 and options.limit_depth.default==0 and not options.boundary_cleanup.default)
assert(not options.permanent_motion_cleanup.default)
for _,name in ipairs({"limit_projectiles","limit_range","limit_depth","boundary_cleanup","permanent_motion_cleanup","crystal_limit",
    "limit_sentries","limit_storms","limit_world_storms","limit_lights","limit_cast"}) do
    assert(options[name].default==false or options[name].default==0,"performance option enabled by default: "..name)
end
assert(#options.limit_depth.options==31)
for i=0,30 do assert(options.limit_depth.options[i+1].data==i) end
print("spell limits: default unlimited range/depth, 30-layer selection, deeper plans, rollback and config values")
