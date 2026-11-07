local C=require("nw/compiler")
local D=require("nw/definitions").spells
local function plan(...)
    local w=require("nw/generator").starter();w.stats.mana_max=2000;w.cards={}
    for i,id in ipairs({...}) do w.cards[i]={card_uid=tostring(i),spell_id=id} end
    w.runtime=C.initial(w.cards,w.stats,43)
    return assert(C.compile(w)).blocks[1].projectiles[1]
end
local F=require("nw/field_effects")
local field=plan("explosion","homing","pierce","damage_up","speed_up","long_life","spore_sentry")
local thorn=F.shot(field,"spore_sentry",14,.36)
assert(thorn.damage==16 and thorn.flags.explosive_hit and thorn.flags.homing and thorn.flags.pierce)
assert(thorn.speed==23 and math.abs(F.time(field,10)-13.5)<1e-6)
thorn.flags.homing.radius=100;assert(field.flags.homing.radius==8,"emitted shots own their modifier tables")
assert(not D.crystal_mine.aim_range and not D.sleep_crystal.aim_range)
assert(require("nw/cards").codes.gunpowder==216 and require("nw/cards").codes.ocarina_g==217,"old save codes changed")
assert(not require("nw/acquisition").by_name.nw_inscribe_edge_vault_compass)
assert(require("nw/acquisition").by_name.nw_inscribe_ocarina_g)
-- Interception is a silent cancellation, never a collision/timer release.
local G=require("nw/guard_ring")
local caster={components={},Transform={GetWorldPosition=function() return 0,0,0 end},IsValid=function() return true end}
local function shot(owner)
    return {components={},_shot={owner=owner},IsValid=function() return true end,HasTag=function() return false end,
        Remove=function(self) self.removed=true end,Hit=function() error("payload must not fire") end}
end
local ring={_nw_guard_owner=caster,_nw_guard_radius=2.5,_nw_guard_left=2,
    IsValid=function(self) return not self.removed end,Remove=function(self) self.removed=true end,
    AnimState={PlayAnimation=function() end}}
TheWorld._nw_guards={[ring]=true}
local own=shot(caster);assert(not G.intercept(own,-5,0,5,0))
local enemy=shot({components={}});assert(G.intercept(enemy,-5,0,5,0) and enemy.removed and ring._nw_guard_left==1)
local missed=shot({components={}});assert(not G.intercept(missed,-5,4,5,4))
local another=shot({components={}});assert(G.intercept(another,-5,0,5,0) and ring.removed)
local ammo=shot(nil);ammo._shot=nil;ammo.components.projectile={IsThrown=function() return false end}
assert(not G.accepts(ammo,caster),"ground ammo must not be removed")
local visual=shot({components={}});visual._nw_controller=caster
assert(not G.accepts(visual,caster),"native visual must not consume a second shield charge")
TheWorld._nw_guards=nil
print("review36: field modifier inheritance, finite timing, append-only G note, retired compass and silent guard interception")
