local C=require("nw/compiler")
local D=require("nw/definitions").spells
local function cast(...)
    local w=require("nw/generator").starter();w.stats.mana_max=2000;w.stats.recharge=.1;w.cards={}
    for i,id in ipairs({...}) do w.cards[i]={card_uid=tostring(i),spell_id=id} end
    w.runtime=C.initial(w.cards,w.stats,31)
    return assert(C.compile(w))
end
local p=cast("recharge_down","recharge_down","spark")
assert(p.next_state.remaining_recharge==0)
assert(D.homing.acceleration==36 and D.near_homing.acceleration==72)
assert(D.homing.acceleration/D.homing.damping==50 and D.near_homing.acceleration/D.near_homing.damping==50)
assert(D.homing.turn_rate==180 and D.homing_rotate.turn_rate==180)
p=cast("explosion","arrow_hit","spark")
assert(p.blocks[1].projectiles[1].flags.explosive_hit and not p.blocks[2].projectiles[1].flags.explosive_hit)
assert(cast("explosion").projectile_count==0)
assert(cast("scatter_timer","spark").projectile_count==6)
assert(cast("scatter_hit","scatter_timer","spark").projectile_count==21)
assert(cast("repeat_2","scatter_timer","spark").projectile_count==12)
local Ground=require("nw/ground_fields")
local boat={}
TheWorld={Map={IsOceanAtPoint=function(_,x) return x>=1 end,
    GetPlatformAtPoint=function(_,x) return x>=2 and x<4 and boat or nil end}}
assert(Ground.surface(0,0)=="land" and Ground.surface(1.5,0)=="ocean" and Ground.surface(3,0)==boat)
for _,id in ipairs({"payload_egg","crystal_mine","sleep_crystal","gunpowder"}) do
    local s={p={id=id}}
    local t=Ground.clip(s,0,0,5,0);assert(t>.19 and t<.2,"fast crossing must stop before shore")
    t=Ground.clip(s,3,0,5,0);assert(t>.49 and t<.5,"must stay on current boat")
    assert(not Ground.clip(s,-1,0,0,0))
end
assert(not Ground.clip({p={id="edge_yellowstaff"}},0,0,5,0))
local removed,splashed=false,false
SpawnPrefab=function(name) assert(name=="splash_sink");return {Transform={SetPosition=function() splashed=true end}} end
assert(Ground.sink({Transform={GetWorldPosition=function() return 1.5,0,0 end},Remove=function() removed=true end}))
assert(removed and splashed)
local out=require("nw/inventory_hint").actions({GetDescriptionString=function() return "法杖\n左键: 检查\n右键: 装备" end})
assert(out=="左键: 检查\n右键: 装备")
print("revision rules: zero recharge, force/turn settings, independent nested scatter budgets, impact-only explosion and ground/boat boundaries")
