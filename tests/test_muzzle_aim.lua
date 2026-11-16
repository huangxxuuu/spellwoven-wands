-- Exercise the real Cast -> muzzle -> executor -> planar collision chain.
Class=function(ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...) local o=setmetatable({},cls);ctor(o,...);return o end})
end
DEGREES=math.pi/180
GetTime=function() return 0 end -- all changing samples deliberately share one tick
local instant=true
require("nw/cast_mode").enabled=function() return instant end
TheWorld={ismastersim=true,Map={IsPassableAtPoint=function() return true end}}
local candidates={}
TheSim={FindEntities=function() return candidates end}
local W=require("components/nw_wand")
local Muzzle=require("nw/muzzle")
local Executor=require("nw/executor")
local Projectiles=require("nw/projectiles")
local w=W({})
w.data=require("nw/generator").starter()
w.data.runtime={mana=100}
w.Sync=function() end
local plan
w.CanCast=function() return true,nil,plan end
local samples,tip=0,{x=.15,y=2.7,z=.8}
local owner={GUID=901,components={combat={CanTarget=function() return true end}},
    Transform={GetWorldPosition=function() return 0,0,0 end},AnimState={},
    IsValid=function() return true end,HasTag=function() return false end}
function owner.AnimState:GetSymbolPosition(_,x,y,z)
    assert(x==0 and z==0)
    if y==0 then return .1,1.2,.1,true end
    samples=samples+1
    assert(y==(instant and -1 or 1)*Muzzle.offset(w.data.stats.capacity),"instant idle and pose must sample the head, not the tail")
    return tip.x,tip.y,tip.z,true
end
local launched={}
SpawnPrefab=function(name)
    if name~="nw_projectile" and name~="nw_end_beam" and name~="nw_aim_probe" then
        return {Transform={SetPosition=function() end},SetImpact=function() end}
    end
    local e={valid=true,Transform={},Physics={SetMotorVel=function() end}}
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false;if self.cleanup then self.cleanup() end end
    e.Transform.GetWorldPosition=function() return e.x,e.y or 0,e.z end
    e.Transform.SetRotation=function() end
    e.Physics.Teleport=function(_,x,y,z) e.x,e.y,e.z=x,y,z end
    function e:Launch(caster,p,x,z,dx,dz,cleanup,height)
        self.cleanup=cleanup;self.x,self.z=x,z
        self.start={x=x,z=z,dx=dx,dz=dz,height=height}
        self._shot={owner=caster,p=p,x=x,z=z,dx=dx,dz=dz,height=height,
            damage=p.damage,speed=p.speed,remaining=p.lifetime,time=0,age=0,travelled=0,hit={}}
        if p.ballistic then
            self.components={complexprojectile={velocity={},SetGravity=function(c,g) c.gravity=g end}}
        end
        launched[#launched+1]=self
    end
    return e
end
local function close(a,b,message) assert(math.abs(a-b)<1e-8,message) end
local function cast(aim,p,child)
    for _,e in ipairs(launched) do e:Remove() end
    launched={}
    p=p or {id="aim_probe",kind="projectile",flags={},damage=20,speed=20,lifetime=5}
    plan={projectile_count=p.count or 1,mana_spent=0,cooldown=0,
        blocks={{projectiles={p}}},next_state={rng_state=17,mana=100}}
    if child then plan.blocks[2]={projectiles={child}} end
    local before=samples
    assert(w:Cast(owner,aim))
    assert(samples==before+1,"every cast must sample the current symbol even in the same tick")
    return launched[1]
end
local target={GUID=902,components={health={IsDead=function() return false end}},
    IsValid=function() return true end,IsInLimbo=function() return false end,
    HasTag=function() return false end,GetPhysicsRadius=function() return .05 end}
local damage=0
target.components.combat={GetAttacked=function(_,_,amount) damage=damage+amount end}
local function hit(aim,e)
    local s=e.start
    local distance=math.sqrt((aim.x-s.x)^2+(aim.z-s.z)^2)
    close(s.x+s.dx*distance,aim.x,"muzzle ray must reach target X")
    close(s.z+s.dz*distance,aim.z,"muzzle ray must reach target Z")
    close(s.dx*s.dx+s.dz*s.dz,1,"corrected heading must be normalized")
    close(s.height,tip.y,"planar correction must preserve sampled visual height")
    target.Transform={GetWorldPosition=function() return aim.x,0,aim.z end}
    candidates={target}
    e.x,e.z=s.x+s.dx*(distance+1),s.z+s.dz*(distance+1)
    local before=damage
    Projectiles.step(e,.5,{},{})
    assert(damage==before+20 and not e:IsValid(),"real projectile sweep must damage the aimed entity")
    candidates={}
end
-- Idle single click / first shot without pose RPC, pre, loop and recoil.
for _,capacity in ipairs({4,8,12}) do
    w.data.stats.capacity=capacity
    for _,angle in ipairs({0,math.pi/2,math.pi,3*math.pi/2}) do
        local co,si=math.cos(angle),math.sin(angle)
        for phase,offset in ipairs({{.15,2.7,.8},{.6,2.2,.65},{1.3,1.5,.75},{.8,1.7,.9}}) do
            owner._nw_pose_hold=phase>1 and {} or nil
            owner.sg={currentstate={name=phase>1 and "nw_hold_pose" or "idle"}}
            tip={x=offset[1]*co-offset[3]*si,y=offset[2],z=offset[1]*si+offset[3]*co}
            local aim={x=8*co,z=8*si}
            hit(aim,cast(aim))
        end
    end
end
-- Mouse mode passes its ground point; entity mode resolves the live entity point.
-- Both feed Cast a world point, and target altitude does not alter planar collision.
owner._nw_pose_hold=nil;owner.sg.currentstate.name="idle"
tip={x=.2,y=2.8,z=.85}
for _,aim in ipairs({{x=5,y=0,z=2},{x=7,y=1.4,z=-3}}) do hit(aim,cast(aim)) end
-- Point-blank clearance must be applied before deriving the final direction.
tip={x=2,y=2,z=2}
hit({x=.1,z=0},cast({x=.1,z=0}))
-- Aiming changes only the base ray: formations/spread retain their angles,
-- ring shots remain radial, and offset scatter remains three parallel lanes.
tip={x=.2,y=2,z=1}
local aim={x=9,z=-2}
local base=cast(aim).start
local function descriptor(id)
    return {id=id,kind="projectile",flags={},damage=20,speed=20,lifetime=5}
end
local fan=descriptor("aim_probe");fan.count=3;fan.angles={-25,0,25}
cast(aim,fan)
for i,e in ipairs(launched) do
    local a=fan.angles[i]*DEGREES
    close(e.start.dx,base.dx*math.cos(a)-base.dz*math.sin(a),"fan angle was retargeted")
    close(e.start.dz,base.dx*math.sin(a)+base.dz*math.cos(a),"fan angle was retargeted")
end
local ring=descriptor("aim_probe");ring.count=4;ring.angles={0,90,180,270}
cast(aim,ring)
close(launched[1].start.dx+launched[3].start.dx,0,"ring opposite rays")
close(launched[2].start.dz+launched[4].start.dz,0,"ring opposite rays")
local scatter=descriptor("scatter");scatter.count=3
cast(aim,scatter)
for _,e in ipairs(launched) do close(e.start.dx,base.dx,"scatter lanes must stay parallel") end
assert(launched[1].start.z~=launched[3].start.z,"scatter lane offsets were removed")
local spread=descriptor("aim_probe");spread.spread=15
local a=cast(aim,spread).start
local delta=math.atan2(base.dx*a.dz-base.dz*a.dx,base.dx*a.dx+base.dz*a.dz)
assert(math.abs(delta)>1e-6 and math.abs(delta)<=15*DEGREES,"random spread must survive muzzle correction")
local field=descriptor("aim_probe");field.kind="field";field.aim_range=20
local placement=cast(aim,field).start
close(placement.x,aim.x,"point placement X");close(placement.z,aim.z,"point placement Z")
field.aim_range=2
placement=cast(aim,field).start
close(placement.x,base.x+base.dx*2,"placement range clamp X")
close(placement.z,base.z+base.dz*2,"placement range clamp Z")
local beam=cast(aim,descriptor("end_beam")).start
close(beam.dx,base.dx,"beam heading");close(beam.height,tip.y,"beam height")
-- Ballistic aiming uses the same corrected XZ ray and the real tip altitude.
local ballistic=descriptor("edge_chum");ballistic.engraving="chum";ballistic.ballistic=true
ballistic.speed=require("nw/definitions").spells.edge_chum.speed
local e=cast(aim,ballistic)
local c=e.components.complexprojectile
local distance=math.sqrt((aim.x-e.start.x)^2+(aim.z-e.start.z)^2)
local time=distance/c.velocity.x
close(e.start.x+e.start.dx*c.velocity.x*time,aim.x,"ballistic landing X")
close(e.start.z+e.start.dz*c.velocity.x*time,aim.z,"ballistic landing Z")
close(tip.y+c.velocity.y*time+.5*c.gravity*time*time,0,"ballistic must descend from current tip to ground")
-- A delayed child keeps its impact heading; it must not re-aim at the root point.
local trigger=descriptor("aim_probe");trigger.payload=2;trigger.event="hit"
e=cast(aim,trigger,descriptor("aim_probe"))
assert(e._shot.fire(3,4,0,1,target))
local child=launched[2].start
close(child.x,3,"payload origin X");close(child.z,4,"payload origin Z")
close(child.dx,0,"payload must retain impact heading X");close(child.dz,1,"payload must retain impact heading Z")
-- Ordinary animation/mounted fallback retain their previous contract.
instant=false;owner._nw_pose_hold=nil
local ordinary=cast({x=8,z=0}).start
close(ordinary.dx,1,"ordinary heading changed");close(ordinary.dz,0,"ordinary heading changed")
close(ordinary.height,1.2,"ordinary hand height changed")
for _,e in ipairs(launched) do e:Remove() end
assert(Executor.stats()==0)
print("muzzle aim: every-shot idle/pre/loop/recoil samples, all lengths/facings, mouse/entity points, real hits, clearance, formations/spread/scatter, placement and beam")
