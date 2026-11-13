local B=require("nw/balance")
local D=require("nw/definitions")
local G=require("nw/generator")
local H=require("nw/hover_data")
local I=require("nw/spell_info")
local F=require("nw/wand_factory")
local Sources=require("nw/sources")
local Rules=require("nw/acquisition")
local function fixed(n) return n and 1 or 0 end

assert(not B.is_balanced() and D.spells.mana_reduce.mana==-30)
local old=G.starter()
old.cards={false,false}
local encoded=H.encode(old)
for _,mode in ipairs({"balanced","balanced_loot","fun","balanced"}) do
    B.configure(mode)
    local balanced=mode~="fun"
    assert(B.is_balanced()==balanced and B.is_loot_only()==(mode=="balanced_loot"))
    assert(D.spells.mana_reduce.mana==(balanced and -20 or -30))
    local display=H.wand(encoded,require("nw/cards").encode(old.cards,2),0,"test")
    assert(display.fields[7][2]==(balanced and 10 or 20))
    assert(old.stats.sanity_conversion==20 and H.decode(encoded).sanity_conversion==20)
    assert(F.stat_text(old):find("理智转化率 "..(balanced and 10 or 20),1,true))
    assert(I.detailed_tooltip("mana_reduce"):find("提供 "..(balanced and 20 or 30).." 法力",1,true))
    assert(H.card_details("mana_reduce").effect:find("提供 "..(balanced and 20 or 30).." 法力",1,true))
    for name,rule in pairs(Sources.by_prefab) do
        if rule.group then
            local reward=Sources.roll(name,rule,{},0,1,fixed)
            assert((reward.core==nil)==balanced)
            assert(reward.dust and reward.tier,"difficulty must not remove other boss rewards")
        end
    end
end
-- Recipe materials are deliberately deferred. All hit/timer cards remain loot-only.
for _,recipe in ipairs(Rules.recipes) do
    if recipe.card then
        local d=D.spells[recipe.card]
        assert(not d.imprint and d.event~="hit" and d.event~="timer")
    end
end
assert(Rules.by_name.nw_extract_deerclops_eyeball.count==1)
assert(Rules.by_name.nw_inscribe_delay_seal and Rules.by_name.nw_inscribe_payload_egg)
B.configure("invalid");assert(B.mode=="fun" and D.spells.mana_reduce.mana==-30)

-- Each server owns its difficulty; only the joining client receives it.
local function node(id,mode,server)
    local state=assert(loadfile("mod/scripts/nw/balance.lua"))()
    local n={state=state,client={},server={},sent={},tasks={},refreshes=0}
    local world={ismastersim=server~=false,ismastershard=id=="1"}
    function world:DoPeriodicTask() error("difficulty must not schedule shard polling") end
    local player={userid="u"..id,IsValid=function() return true end}
    function player:ListenForEvent(name,fn) assert(name=="playeractivated");n.activate=fn end
    function player:DoTaskInTime(delay,fn) assert(delay==0);n.tasks[#n.tasks+1]=fn end
    function player:PushEvent(name) assert(name=="refreshcrafting");n.refreshes=n.refreshes+1 end
    local globals={TheWorld=world,
        CLIENT_MOD_RPC={nw_weave={balance_state="balance_state"}},
        MOD_RPC={nw_weave={balance_query="balance_query"}}}
    globals.SendModRPCToClient=function(name,user,value)
        n.sent[#n.sent+1]={name,user,value}
        if n.viewer then n.viewer.client[name](value) end
    end
    globals.SendModRPCToServer=function(name,...)
        n.connected.server[name](player,...)
    end
    state.install({GetModConfigData=function(key) assert(key=="world_difficulty");return mode end,
        AddModRPCHandler=function(_,name,fn) n.server[name]=fn end,
        AddClientModRPCHandler=function(_,name,fn) n.client[name]=fn end,
        AddShardModRPCHandler=function() error("difficulty must not register shard synchronization") end,
        AddPlayerPostInit=function(fn) fn(player) end,
        AddPrefabPostInit=function() error("difficulty does not need a world sync task") end},globals)
    n.globals=globals;n.player=player
    return n
end
local surface=node("1","balanced")
local caves=node("2","balanced_loot")
local third=node("3","fun")
assert(surface.state.mode=="balanced" and caves.state.mode=="balanced_loot" and third.state.mode=="fun")
assert(caves.state.is_balanced() and caves.state.is_loot_only())
-- An unsolicited client-state packet cannot alter a server's local setting.
surface.client.balance_state("fun");assert(surface.state.mode=="balanced")
caves.client.balance_state("balanced");assert(caves.state.is_loot_only())
local client=node("client","fun",false)
client.globals.ThePlayer=client.player
client.connected=surface;surface.viewer=client
client.tasks[1]()
assert(client.state.mode=="balanced" and client.refreshes==1)
client.connected=caves;caves.viewer=client
client.activate()
assert(client.state.is_loot_only() and client.state.is_balanced() and client.refreshes==2)
assert(surface.state.mode=="balanced" and caves.state.mode=="balanced_loot" and third.state.mode=="fun")
client.client.balance_state("invalid");assert(client.state.is_loot_only() and client.refreshes==2)
-- Queries are read-only even when a client supplies an extra requested mode.
caves.server.balance_query(client.player,"fun")
assert(caves.state.is_loot_only() and client.state.is_loot_only() and client.refreshes==2)
client.connected=third;third.viewer=client
client.activate()
assert(client.state.mode=="fun" and not client.state.is_balanced() and client.refreshes==3)
B.configure("fun")
print("balance settings: independent shard difficulty, joined-world client state, dynamic UI, unchanged stored stats and boss core policy")
