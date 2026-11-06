-- Drive the registered game-event handlers in order, including false victories.
local init={}
local function entity(name)
    local e={prefab=name, components={}, handlers={}, count={}, alive=true, sg={currentstate={name="idle"}}}
    function e:ListenForEvent(key,fn) self.handlers[key]=fn end
    function e:PushEvent(key,data) if key=="death" then TheWorld:PushEvent("entity_death",{inst=self}) end; if self.handlers[key] then self.handlers[key](self,data) end end
    function e:AddComponent(key) self.components[key]={} end
    function e:HasTag() return false end
    function e:GetPosition() return {} end
    e.components.health={maxhealth=500,IsDead=function() return not e.alive end}
    e.components.lootdropper={SpawnLootPrefab=function(_,which)
        e.count[which]=(e.count[which] or 0)+1
        return {SetSpell=function(_,id) e.dropped_card=id end,
            components={nw_wand={InitializeNew=function(self,tier) e.tier=tier;self.data={cards={{spell_id="spark"}}} end},
            stackable={SetStackSize=function(_,n) e.dust=n end}}}
    end}
    return e
end
local starting_wand=false
local env={GetModConfigData=function(key)
    if key=="starting_wand" then return starting_wand end
    return 0
end,AddPrefabPostInit=function(key,fn) init[key]=fn end}
require("nw/rewards").install(env)
local disabled=entity("world");disabled.ismastersim=true;init.world(disabled)
assert(not disabled.handlers.ms_newplayerspawned)
starting_wand=true
TheWorld=entity("world");TheWorld.ismastersim=true;init.world(TheWorld)
TheWorld.components.playerspawner={IsPlayersInitialSpawn=function(_,player) return player.initial end}
local player={initial=true,components={inventory={GiveItem=function(_,wand) assert(wand.tier==0) end}}}
local gifts=0
function SpawnPrefab(name)
    assert(name=="nw_wand"); gifts=gifts+1
    local wand={components={inventoryitem={IsHeld=function() return true end}}}
    wand.components.nw_wand={InitializeNew=function(_,tier,source) assert(source=="starter");wand.tier=tier end}
    return wand
end
TheWorld:PushEvent("ms_newplayerspawned",player)
player.initial=false
TheWorld:PushEvent("ms_newplayerspawned",player)
TheWorld:PushEvent("ms_playerjoined",player)
assert(gifts==1)
local function target(name)
    local e=entity(name);if init[name] then init[name](e) end;return e
end
local function loot(e) TheWorld:PushEvent("entity_droploot",{inst=e}) end
local function paid(e,tier)
    assert(e.count.nw_overlord_core==1 and e.tier==tier and e.count.nw_wand==(tier and 1 or nil),e.prefab)
end
local scion=target("alterguardian_phase4_lunarrift")
scion.alive=false;loot(scion);assert(not next(scion.count))
TheWorld:PushEvent("ms_wagboss_alter_defeated",scion);assert(not next(scion.count))
scion.sg.currentstate.name="selfdestruct";loot(scion);loot(scion);paid(scion,4)
local shadow=target("shrouden")
shadow.alive=false;shadow:PushEvent("death");loot(shadow);assert(not next(shadow.count))
shadow:PushEvent("ms_charlie_boss_defeated");shadow:PushEvent("ms_charlie_boss_defeated");paid(shadow,4)
local worm=target("worm_boss_shadow")
loot(worm);assert(not next(worm.count));worm.alive=false;loot(worm);loot(worm);paid(worm,4)
for _,name in ipairs({"charlie_boss","stalker_npc","wagboss_robot","worm_boss_shadow_head","alterguardian_phase1_lunarrift"}) do
    local e=target(name); e.alive=false; e:PushEvent("death");loot(e);assert(not next(e.count),name)
end
local tower=target("vault_pillar_guard")
tower.alive=false;loot(tower);tower.trial={};loot(tower);assert(not next(tower.count))
tower._vault_death_loot=true;loot(tower);loot(tower);paid(tower,nil)
local klaus=target("klaus")
klaus.alive=false
function klaus:IsUnchained() return self.final end
klaus:PushEvent("death");klaus:PushEvent("dropkey");assert(not next(klaus.count))
klaus.final=true;klaus:PushEvent("dropkey");klaus:PushEvent("dropkey");paid(klaus,nil)
local bat=target("bat_boss_shadow")
bat.alive=false;local twin=target("bat_boss_shadow")
bat.components.entitytracker={GetEntity=function() return twin end}
bat:PushEvent("death");assert(not next(bat.count))
local rewards=require("nw/rewards")
rewards.cardmult=1
math.random=function(n) return n or 0 end -- select a signature first, last fallback card on empty rolls
local first=target("twinofterror1");first.alive=false
first:PushEvent("death");loot(first);assert(not next(first.count))
local second=target("twinofterror2");second.alive=false
second.components.lootdropper.loot={"shieldofterror"};loot(second);loot(second)
assert(second.count.nw_spellcard==1)
local unrelated=target("unlisted_beast")
unrelated.HasTag=function(_,tag) return tag=="animal" end
unrelated.components.lootdropper.GetAllPossibleLoot=function(_,setup) assert(not setup);return {} end
unrelated.alive=false;unrelated:PushEvent("death");unrelated:PushEvent("death")
assert(unrelated.count.nw_spellcard==1 and unrelated.dropped_card)
local wall=target("mod_wall");wall.HasTag=function(_,tag) return tag=="wall" end
wall.alive=false;wall:PushEvent("death");assert(not next(wall.count))
local walrus=target("walrus");walrus.alive=false;walrus:PushEvent("death")
assert(walrus.dropped_card=="speed_up" and walrus.count.nw_spellcard==1)
local signature=target("mutatedbearger");signature.alive=false;signature:PushEvent("death")
assert(signature.dropped_card=="repeat_4" and signature.tier==4)
local rolls=0
math.random=function(n) rolls=rolls+1;return rolls==1 and .999 or n or 0 end
local boss=target("mutateddeerclops");boss.alive=false;boss:PushEvent("death")
assert(boss.tier==4 and not boss.count.nw_spellcard,"loaded wand must block wildcard")
math.random=function(n) return n or 0 end
twin.components.entitytracker={GetEntity=function() return bat end}
twin.alive=false;twin:PushEvent("death");paid(twin,4)
-- Replaying the first death after its sibling died must not pay again.
bat:PushEvent("death");assert(not next(bat.count))
AllPlayers={}
for i=1,2 do
    AllPlayers[i]={components={nw_firstboss={claimed=false}},IsValid=function() return true end,
        IsInLimbo=function() return false end,GetDistanceSqToInst=function() return 144 end}
end
local bonus=target("mutatedbearger");bonus.alive=false;bonus:PushEvent("death")
assert(bonus.count.nw_spellcard==3,"normal one-card reward plus two independent first-boss cards")
bonus:PushEvent("death");loot(bonus);assert(bonus.count.nw_spellcard==3,"no duplicate event bonus")
for _,p in ipairs(AllPlayers) do assert(p.components.nw_firstboss.claimed) end
rewards.cardmult=0
AllPlayers[1].components.nw_firstboss.claimed=false
local guaranteed=target("deerclops");guaranteed.alive=false;guaranteed:PushEvent("death")
assert(guaranteed.count.nw_spellcard==1,"first-boss guarantee is independent of normal drop-rate setting")
AllPlayers=nil
print("encounters: final gates, clones, boss parts, friendly towers and duplicate events")
