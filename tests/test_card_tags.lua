local D=require("nw/definitions")
local Tags=require("nw/card_tags")
local L=require("nw/locale")
local known={}
assert(#Tags.order==24,"agreed filter vocabulary must stay at 24")
for _,id in ipairs(Tags.order) do assert(not known[id]);known[id]=true end
for _,id in ipairs({"modifier","note","work","instant","broken","projectile","field","size",
    "hit","timer","payload","spread","fire","ice","electric","wet","healing","sanity","pitch"}) do
    assert(not known[id],"retired/merged filter: "..id)
end
local untagged={spark=true,arrow=true,heavy=true,grow_orb=true,spore_sentry=true,bee_swarm=true,fireflies=true,edge_minifan=true}
local count=0
for id,d in pairs(D.spells) do
    local tags=Tags.for_card(id)
    -- Ordinary single-target attacks remain discoverable through the main class.
    assert((next(tags)==nil)==(untagged[id]==true),"unreviewed untagged spell: "..id)
    for tag in pairs(tags) do assert(known[tag],id..": unknown tag "..tag) end
    if tags.damage then
        assert(require("nw/card_visuals").cards[id].primary_class=="modifier","damage filter must only contain modifier cards: "..id)
    end
    assert((tags.trigger==true)==(d.event~=nil or d.imprint~=nil),"trigger means subsequent spells: "..id)
    if d.base then
        for tag in pairs(Tags.for_card(d.base)) do assert(tags[tag],"variant lost base mechanic: "..id.."/"..tag) end
    end
    count=count+1
end
local function has(id,...)
    local tags=Tags.for_card(id)
    for _,tag in ipairs({...}) do assert(tags[tag],id.." missing "..tag) end
end
local function lacks(id,...)
    local tags=Tags.for_card(id)
    for _,tag in ipairs({...}) do assert(not tags[tag],id.." incorrectly tagged "..tag) end
end
has("heal_bolt","recovery")
has("heal_ally","recovery")
has("edge_batbat","recovery")
has("chord_d","music","recovery","area")
has("kantele_g","music","recovery")
has("edge_opalstaff","element","light","recovery","area")
has("edge_yellowstaff","element","light","recovery","area")
lacks("edge_shadow_battleaxe","recovery") -- native level 1 life steal is zero
lacks("edge_nightsword","recovery","tool")
has("fire_timer","element","trigger")
has("delay_seal","trigger")
has("payload_egg","trigger")
for _,id in ipairs({"sleep_crystal","crystal_mine","explosion","spore_ball","note_c","side_embers","leech","end_beam"}) do
    lacks(id,"trigger")
end
has("pitch_octave_up","music")
has("ocarina_g","music")
lacks("pitch_octave_up","speed","lifetime")
has("whirl","melee","area","tool")
has("thrust","melee","area")
has("bog_whip","melee","area")
has("melee_mark","melee","damage")
for _,id in ipairs({"edge_shovel","edge_pickaxe","edge_farm_hoe","edge_fishingrod","edge_oceanfishingrod","edge_staff_tornado"}) do has(id,"tool") end
has("edge_voidcloth_scythe","area","tool")
lacks("edge_voidcloth_scythe","melee","planar") -- removed native weapon damage
has("edge_trident","area","element","tool")
has("edge_lighter","area","element","trajectory")
lacks("edge_lighter","light","tool")
lacks("edge_chum","tool","trigger")
lacks("edge_brush","tool") -- weapon name does not grant the original right-click action
has("edge_orangestaff","movement")
has("land_hook","movement")
lacks("gust","movement")
has("edge_shieldofterror","defense","trajectory")
lacks("edge_wathgrithr_shield","defense") -- legacy melee strike, no active block
has("near_homing","trajectory","homing")
has("speed_down","speed","lifetime")
has("heavy_shot","speed","damage","trajectory")
has("scatter","trajectory")
has("side_embers","trajectory")
lacks("side_embers","element","multicast","copy")
has("orbit","lifetime","trajectory")
has("giant_shot","area")
lacks("giant_shot","damage","speed","lifetime")
lacks("grow_orb","damage")
has("edge_voidcloth_boomerang","planar","trajectory")
lacks("edge_voidcloth_boomerang","damage")
for _,id in ipairs({"damage_up","heavy_shot","light_shot","wet_weak","melee_mark","harmless","crit_rune"}) do has(id,"damage") end
has("edge_torch","light","element")
has("edge_nightstick","light","element")
lacks("edge_fumaroleaxe","element") -- fresh native tools are unheated
has("edge_dumbbell_bluegem","area","element","control","trajectory","pierce")
has("edge_dumbbell_redgem","area","element","trajectory","pierce")
has("edge_dumbbell_heat","area","trajectory","pierce")
lacks("edge_dumbbell_heat","element")
has("edge_whip","control")
for _,id in ipairs({"spore_sentry","bee_swarm","fireflies","guard_ring","storm_cloud","chain"}) do
    lacks(id,"area") -- search/orbit radius; lightning selects one target per strike/hop
end
has("shock_ring","element","area")
has("spore_ball","area","explosive")
has("explosion","area","explosive","element","tool")
has("gunpowder","area","explosive","element","tool")
lacks("deer_decoy","explosive")
has("repeat_4","copy")
lacks("repeat_4","multicast","damage")
lacks("star_vortex","multicast","copy") -- several intrinsic bolts, not extra card draws
lacks("spark","mana","recharge","damage")
has("mana_reduce","mana")
has("recharge_down","recharge")
assert(next(Tags.for_card("unknown"))==nil)
L.configure("zh")
local options=Tags.options(known)
assert(#options==24)
for _,option in ipairs(options) do assert(#option.text==6,"Chinese labels must have two characters: "..option.id) end
L.configure("en")
for _,option in ipairs(Tags.options(known)) do
    for i=1,#option.text do assert(option.text:byte(i)<128,"untranslated filter: "..option.id) end
end
L.configure("zh")
print("card tags: "..count.." definitions reviewed; 24 bilingual filters; trigger, utility, area and native boundaries passed")
