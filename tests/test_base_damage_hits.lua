local hits,shots={},{}
local enemy={components={health={IsDead=function() return false end,currenthealth=100},combat={}},
    IsValid=function() return true end,GetDistanceSqToPoint=function() return 0 end,
    GetPhysicsRadius=function() return .5 end,Transform={GetWorldPosition=function() return 0,0,0 end}}
package.loaded["nw/targeting"]={query=function() return {enemy} end,accepts=function() return true end,
    damage=function(_,_,n) hits[#hits+1]=n end}
package.loaded["nw/spell_effects"]={direct=function(_,_,p) hits[#hits+1]=p.damage end,
    scan=function() return {enemy} end,wet_mult=function() return 1 end,
    native_hit=function() end,fx=function() return {SetSpan=function() end} end}
package.loaded["nw/balance_damage"]={attack=function(_,_,_,n,_,_,sp) hits[#hits+1]=n;hits.planar=sp.planar end}
package.loaded["nw/executor"]={execute=function(plan) shots[#shots+1]=plan.blocks[1].projectiles[1] end}
package.loaded["nw/geometry"]={hit=function() return true end}
GetTime=function() return 0 end
local H=require("nw/expanded_hits")
local function close(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." ~= "..tostring(b)) end
local s={p={id="note_c",damage=0,echo_damage=12,effect_scale=.45,flags={}},age=0,dx=1,dz=0}
enemy._nw_note_until=1;H.impact(s,enemy,0,0);close(hits[#hits],5.4)
s.p.echo_damage=nil;s.p.effect_scale=nil
enemy._nw_note_until=1;H.impact(s,enemy,0,0);close(hits[#hits],8)
s.p={id="grow_orb",damage=18,flags={}};s.age=1
H.impact(s,enemy,0,0);close(hits[#hits],39)
-- The outgoing base includes +10 already; only native growth receives 1.5.
s.p={id="edge_voidcloth_boomerang",engraving="voidcloth_boomerang",damage=17.5,
    planar=7.5,growth_mult=1,base_damage_multiplier=1.5,flags={}}
s.native={components={weapon={damage=25},damagetypebonus={GetBonus=function() return 1 end},
    planardamage={GetBaseDamage=function() return 20 end}}}
H.impact(s,enemy,0,0);close(hits[#hits],47.5);close(hits.planar,30)
s={p={flags={side_embers={effect_damage=6}},effect_scale=.45},x=0,z=0,dx=1,dz=0,
    travelled=3,context={side_left=4,side_groups=0}}
H.step(s,0);assert(#shots==2);close(shots[1].damage,2.7)
s={p={flags={halo={effect_damage=4.5}},effect_scale=.45},x=0,z=0,context={}}
H.step(s,0);close(hits[#hits],2.025)
-- Saved older modifier tables have no effect_damage field.
s={p={flags={halo={}},effect_scale=.45},x=0,z=0,context={}}
H.step(s,0);close(hits[#hits],1.35)
H.electric=function(_,_,_,_,n) hits[#hits+1]=n end
s={p={flags={twin_arc={effect_damage=6}},effect_scale=.45},x=0,z=0,height=1,
    context={arcs={}},partner={IsValid=function() return true end,Transform={GetWorldPosition=function() return 1,0,0 end}}}
H.step(s,0);close(hits[#hits],2.7)
