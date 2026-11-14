-- Exercise the real chain scheduler, target selection, attacks and fog hooks.
DEGREES=math.pi/180
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
local time,tasks,targets,points,paths,arcs,attacks=0,{},{},{},{},{},{}
GetTime=function() return time end
local Target=require("nw/targeting")
Target.allowed=function(_,e) return e.valid end
Target.hittable=function(_,e) return e.valid end
local Fog={leave=function(owner,x,z,p) points[#points+1]={owner=owner,x=x,z=z,p=p} end,
    trail=function(state,s,x,z,tx,tz,continuous)
        assert(continuous and s.p.flags.dark)
        paths[#paths+1]={state=state,p=s.p,x=x,z=z,tx=tx,tz=tz}
    end}
package.loaded["nw/dark_fog"]=Fog
package.loaded["nw/explosions"]={hit=function() end}
local Effects=require("nw/spell_effects")
Effects.native_hit=function() end
Effects.scan=function() return targets end
local function entity(x,z)
    local e={x=x,z=z,valid=true,GUID=x*10+z,components={}}
    function e:IsValid() return self.valid end
    function e:HasTag() return false end
    function e:GetDistanceSqToPoint(x,_,z) return (self.x-x)^2+(self.z-z)^2 end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end}
    e.components.health={currenthealth=100,IsDead=function() return false end}
    e.components.combat={}
    return e
end
local owner=entity(0,0)
owner.components.combat={DoAttack=function(_,e,weapon)
    attacks[#attacks+1]=e
    e.components.health.currenthealth=e.components.health.currenthealth-weapon.damage
end}
TheWorld={components={},state={israining=false},DoTaskInTime=function(_,delay,fn)
    assert(delay==.15);tasks[#tasks+1]=fn
end}
Effects.fx=function(name,x,z)
    if name~="nw_arc_fx" then return {} end
    local e={x=x,z=z,components={}}
    e.components.weapon={SetDamage=function(_,n) e.damage=n end}
    e.SetSpan=function(_,dx,dz,target) e.dx,e.dz,e.target=dx,dz,target end
    arcs[#arcs+1]=e;return e
end
math.random=function() return .5 end
local function next_hop() time=time+.15;local fn=table.remove(tasks,1);assert(fn);fn() end
local function reset()
    time=0;tasks={};targets={};points={};paths={};arcs={};attacks={};owner.valid=true
end
local function params(dark,scale)
    return {id="chain",flags={dark=dark},radius=6*scale,damage=15,jump_damage=10,max_targets=4,size_mult=scale}
end
local a,b=entity(3,0),entity(3,4)
targets={a,b}
Effects.chain(owner,a,0,0,params(true,.8),1,0,true)
assert(#attacks==1 and attacks[1]==a and #paths==1 and #points==2)
assert(points[1].x==0 and points[2].x==3 and paths[1].tx==3)
assert(paths[1].p.size_mult==.8 and paths[1].p~=nil)
next_hop();assert(attacks[2]==b and paths[2].x==3 and paths[2].tz==4)
next_hop();next_hop()
assert(#paths==4 and #arcs==4 and #attacks==2 and #points==8 and #tasks==0)
assert(paths[3].tx>3 and paths[3].tz==4,"empty hop leaves arc path and landing fog")
assert(paths[4].state==paths[1].state,"one continuous sampling state per chain")
assert(a.components.health.currenthealth==85 and b.components.health.currenthealth==90)
-- A giant empty hop longer than the normal teleport guard remains a real path.
reset();Effects.chain(owner,nil,10,20,params(true,5),1,0,true)
assert(paths[1].x==10 and paths[1].tx==40 and paths[1].p.size_mult==5)
assert(points[2].x==40 and points[2].z==20)
-- Losing the caster stops scheduled fog as well as damage.
owner.valid=false;next_hop();assert(#paths==1 and #tasks==0)
-- An ordinary chain never enters the fog path.
reset();Effects.chain(owner,nil,0,0,params(false,1),1,0,true)
next_hop();next_hop();next_hop();assert(#arcs==4 and #points==0 and #paths==0)
-- Failed arc creation cannot create an invisible chain of fog.
reset();Effects.fx=function() return nil end
Effects.chain(owner,nil,0,0,params(true,1),1,0,true)
assert(#points==0 and #paths==0 and #tasks==0)
print("chain dark: real hit/empty hop scheduler, endpoints and paths, size propagation, giant spans, no-dark, failed arc and caster loss passed")
