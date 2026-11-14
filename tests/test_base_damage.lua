local D=require("nw/definitions")
local B=require("nw/base_damage")
local U=require("nw/util")
local C=require("nw/compiler")
local H=require("nw/hover_data")
local I=require("nw/spell_info")
local baseline=U.copy(D.spells)
local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a).." ~= "..tostring(b)) end
local function cast(...)
    local w=require("nw/generator").starter()
    w.stats.mana_max=1000;w.cards={}
    for i,id in ipairs({...}) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=C.initial(w.cards,w.stats,1)
    return assert(C.compile(w))
end
local function shot(...) return cast(...).blocks[1].projectiles[1] end
local damage_fields={"damage","burn_damage","jump_damage","end_damage","planar",
    "explosion_damage","echo_damage","effect_damage"}
local unchanged={"native_base_damage","damage_add","damage_mult","copy_damage","heal",
    "mana","delay","recharge","speed","lifetime","radius","freeze","burn_ticks","count"}
assert(B.multiplier==1)
for _,rate in ipairs({.5,.75,1,1.25,1.5,.75,1}) do
    B.configure(rate)
    for id,base in pairs(baseline) do
        local d=D.spells[id]
        assert(d.base_damage_multiplier==rate,id)
        for _,key in ipairs(damage_fields) do
            if base[key] then near(d[key],base[key]*rate) else assert(d[key]==nil,id.."."..key) end
        end
        for _,key in ipairs(unchanged) do assert(d[key]==base[key],id.."."..key) end
    end
    near(shot("spark").damage,18*rate)
    -- Adjust the card's base before the ordinary fixed and multiplicative modifiers.
    near(shot("light_shot","damage_up","spark").damage,(18*rate+10)*.75)
    near(shot("heavy_shot","spark").damage,18*rate+12)
    near(shot("damage_up","star_vortex").damage,6*rate+10/4)
    local chain=shot("damage_up","chain")
    near(chain.damage,15*rate+10);near(chain.jump_damage,10*rate+10)
    local plan=cast("spark_hit","fire")
    local carrier=plan.blocks[1].projectiles[1]
    local payload=plan.blocks[carrier.payload].projectiles[1]
    near(carrier.damage,18*rate);near(payload.damage,9*rate);near(payload.burn_damage,3.6*rate)
    near(shot("edge_hambat").damage,59.5*rate)
    near(shot("edge_sword_lunarplant").planar,24*rate)
    assert(shot("heal_bolt").heal==8 and shot("heal_bolt").damage==0)
    assert(shot("damage_up","edge_farm_hoe").damage==0)
    local beam=shot("repeat_4","end_beam")
    local copy=require("nw/cast_templates").resolver()(beam,.45,false)
    near(copy.damage,12*rate*.45);near(copy.end_damage,16*rate*.45)
    near(shot("searing_halo","spark").flags.halo.effect_damage,3*rate)
    near(shot("explosion","spark").flags.explosive_hit.explosion_damage,25*rate)
    near(shot("note_c").echo_damage,8*rate)
    near(H.card("spark").fields[1][2],18*rate)
    assert(H.card_details("chain").fields[1][2]==tostring(15*rate).." / "..tostring(10*rate))
    assert(I.detailed_tooltip("spark"):find(string.format("单弹伤害 %g",18*rate),1,true))
    assert(H.card_details("gunpowder").fields[1][2]==tostring(200*rate).." / 目标")
    assert(I.effect("fire"):find(string.format("每秒 %g 点火伤",3.6*rate),1,true))
    assert(I.effect("chain"):find(string.format("首跳 %g、后续 %g",15*rate,10*rate),1,true))
    assert(I.effect("grow_orb"):find(string.format("%g→%g 伤",12*rate,26*rate),1,true))
    assert(I.effect("note_c"):find(string.format("一次 %g 伤回声",8*rate),1,true))
    assert(I.effect("edge_sword_lunarplant"):find(string.format("位面伤害 %g",24*rate),1,true))
    for _,id in ipairs({"fire_hit","fire_timer"}) do
        assert(I.effect(id):find(string.format("每秒 %g 点火伤",3.6*rate),1,true))
        assert(I.effect(id):find("\n",1,true),"carrier details must retain payload instructions")
    end
    assert(I.effects.fire:find("每秒 3.6 点火伤",1,true),"reference text must not inherit world settings")
end
-- Existing compiled payloads own their values, not a pointer to world definitions.
B.configure(.5)
local plan=cast("payload_egg","fire")
local saved=require("nw/cast_templates").snapshot(plan.blocks,2,1,false,1)
B.configure(1.5)
near(saved.blocks[1].projectiles[1].damage,4.5)
near(saved.blocks[1].projectiles[1].burn_damage,1.8)
near(shot("fire").damage,13.5)
B.configure(1.5);near(D.spells.spark.damage,27)
for _,invalid in ipairs({false,0,-1,2,"1.5",math.huge}) do
    B.configure(invalid);assert(B.multiplier==1 and D.spells.spark.damage==18)
end
B.configure(nil);assert(B.multiplier==1)

-- Isolated definition tables model separate server/client Lua processes.
local function node(rate,server)
    local defs={spells=U.copy(baseline)}
    local fn=assert(loadfile("mod/scripts/nw/base_damage.lua"))
    setfenv(fn,setmetatable({require=function(name)
        if name=="nw/definitions" then return defs end
        assert(name=="nw/constants/balance");return require(name)
    end},{__index=_G}))
    local state=fn()
    local n={state=state,defs=defs,server={},client={},refreshes=0}
    local player={userid="viewer",IsValid=function() return true end}
    function player:ListenForEvent(event,callback) assert(event=="playeractivated");n.activate=callback end
    function player:DoTaskInTime(delay,callback) assert(delay==0);n.initial=callback end
    function player:PushEvent(event) assert(event=="refreshcrafting");n.refreshes=n.refreshes+1 end
    local globals={TheWorld={ismastersim=server},ThePlayer=not server and player or nil,
        CLIENT_MOD_RPC={nw_weave={base_damage_state="base_damage_state"}},
        MOD_RPC={nw_weave={base_damage_query="base_damage_query"}}}
    globals.SendModRPCToClient=function(name,user,value)
        assert(user==player.userid)
        if n.viewer then n.viewer.client[name](value) end
    end
    globals.SendModRPCToServer=function(name,...) n.connected.server[name](player,...) end
    state.install({GetModConfigData=function(key) assert(key=="base_damage_multiplier");return rate end,
        AddModRPCHandler=function(_,name,callback) n.server[name]=callback end,
        AddClientModRPCHandler=function(_,name,callback) n.client[name]=callback end,
        AddPlayerPostInit=function(callback) callback(player) end},globals)
    n.player=player
    return n
end
local surface=node(.5,true)
local caves=node(1.5,true)
local client=node(1,false)
client.connected=surface;surface.viewer=client;client.initial()
assert(client.state.multiplier==.5 and client.defs.spells.spark.damage==9 and client.refreshes==1)
client.initial();assert(client.refreshes==1,"identical synchronization must not multiply again")
client.connected=caves;caves.viewer=client;client.activate()
assert(client.state.multiplier==1.5 and client.defs.spells.spark.damage==27 and client.refreshes==2)
surface.client.base_damage_state(1.5)
assert(surface.state.multiplier==.5 and caves.state.multiplier==1.5)
caves.server.base_damage_query(client.player,.5)
assert(client.state.multiplier==1.5 and caves.state.multiplier==1.5)
client.client.base_damage_state(2);assert(client.state.multiplier==1.5)
client.connected=surface;client.activate()
assert(client.state.multiplier==.5 and client.defs.spells.spark.damage==9 and client.refreshes==3)
B.configure(1)
print("base damage: all five rates, modifier order, payloads, healing, UI, frozen plans and joined-world synchronization")
