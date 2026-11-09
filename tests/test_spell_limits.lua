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
plan=assert(C.compile(wand(31)));assert(#plan.blocks==32,"configured depth must not reject the cast")
assert(not C.compile(wand(31),nil,{depth=30}),"explicit diagnostic compiler guard remains available")
L.depth=1;assert(C.compile(wand(40)))
L.depth=0

local env=setmetatable({},{__index=_G})
local info=assert(loadfile("mod/modinfo.lua"));setfenv(info,env);info()
local options={}
for _,v in ipairs(env.configuration_options) do options[v.name]=v end
local defaults={client_trail_limit=1700,limit_projectiles=600,limit_fields=200,limit_permanent_fields=100,limit_range=0,limit_depth=5,boundary_cleanup=true,permanent_motion_cleanup=true,sync_performance=true}
for name,value in pairs(defaults) do assert(options[name].default==value) end
for _,name in ipairs({"limit_cast","crystal_limit","limit_sentries","limit_storms","limit_world_storms","limit_lights"}) do assert(not options[name]) end
for i,n in ipairs({0,100,500,900,1300,1700,2100,2500,2900,3300}) do assert(options.client_trail_limit.options[i].data==n) end
for _,key in ipairs({"limit_projectiles","limit_fields","limit_permanent_fields"}) do
    for i,n in ipairs({0,25,50,100,200,300,400,500,600,700,800}) do assert(options[key].options[i].data==n) end
end
assert(#options.limit_depth.options==31)
for i=0,30 do assert(options.limit_depth.options[i+1].data==i) end
print("spell limits: configured limits never reject compilation; eight settings and expanded values")
