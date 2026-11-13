local G=require("nw/giant_stars")
TUNING={WET_HEAT_FACTOR_PENALTY=.5,SANITY_AURA_SEACH_RANGE=20}
local scale,heat=5,100
local star={_nw_giant_star=scale,components={},IsValid=function() return true end,IsInLimbo=function() return false end,
    HasAnyTag=function() return false end,HasTag=function() return false end}
star.components.heater={GetHeat=function() return heat end,IsExothermic=function() return heat>0 end,IsEndothermic=function() return heat<0 end}
local distance,wet=15,false
local observer={components={},GetDistanceSqToInst=function() return distance^2 end,GetIsWet=function() return wet end}
local c={inst=observer,ignoreheatertags={"INLIMBO"},current=0,overheattemp=70,totalmodifiers=4}
TheWorld={_nw_giant_stars={[star]=true}}
local delta,power=G.heat(c)
assert(math.abs(delta-91)<1e-9 and math.abs(power-.91)<1e-9)
distance=5
local extra=G.heat(c)
assert(math.abs(extra-24)<1e-9,"native inner-disk heating must not be counted twice")
distance=15
wet=true;assert(math.abs(G.heat(c)-45.5)<1e-9)
heat=-100;c.current=70;wet=false
assert(math.abs(G.heat(c)+154.7)<1e-9)
distance=50;assert(G.heat(c)==0)
distance=15;heat=100;c.current=0
observer.components.inventoryitem={owner={HasTag=function(_,tag) return tag=="pocketdimension_container" end}}
assert(G.heat(c)==0);observer.components.inventoryitem=nil
local updates=0
c.OnUpdate=function(self,dt) updates=updates+1;assert(dt==.1);self.delta=self.totalmodifiers;self.externalheaterpower=2 end
G.temperature(c);c:OnUpdate(.1)
assert(updates==1 and c.totalmodifiers==4 and math.abs(c.delta-95)<1e-9 and math.abs(c.externalheaterpower-2.91)<1e-9)
local immune=false
star.components.sanityaura={GetAura=function() return .2 end}
local sanity={inst=observer,sanity_aura_immune_sources={Get=function() return immune end}}
assert(G.aura(sanity)==0,"native aura search already handles the inner disk")
distance=25
assert(G.aura(sanity)==.2);immune=true;assert(G.aura(sanity)==0);immune=false
star.HasTag=function(_,tag) return tag=="coldstar" end
sanity.sanity_aura_immunities={coldstar={Get=function() return true end}}
assert(G.aura(sanity)==0);sanity.sanity_aura_immunities=nil
local modifier=0
sanity.externalmodifiers={SetModifier=function(_,_,v) modifier=v end,RemoveModifier=function() modifier=0 end}
sanity.Recalc=function(self) self.rate=modifier end
G.sanity(sanity);sanity:Recalc();assert(sanity.rate==.2 and modifier==0)
TheWorld._nw_giant_stars=nil;c:OnUpdate(.1);assert(c.delta==4 and c.externalheaterpower==2)
TheWorld._nw_giant_stars={[star]=true};distance=15
local item={inst=observer,temperature=0,maxtemp=90,GetTargetDeltaTemperature=function(self) self.externalheaterpower=0;return 12 end}
G.item_temperature(item)
assert(math.abs(item:GetTargetDeltaTemperature()-103)<1e-9)
-- Scale the native pulse's result once each time on both replicas.
local radius=0
local task={period=.1,fn=function() radius=11.5 end}
local light={pendingtasks={[task]=true},Light={GetRadius=function() return radius end,SetRadius=function(_,r) radius=r end},
    _nw_star_size={value=function() return scale end}}
G.pulse(light)
for i=1,10 do task.fn(light);assert(radius==57.5) end
scale=1;task.fn(light);assert(radius==11.5)
scale=.4;task.fn(light);assert(math.abs(radius-4.6)<1e-9)
scale=0;task.fn(light);assert(radius==11.5,"uninitialized replica keeps the native light")
star._nw_giant_star=.4;distance=5;wet=false;heat=100;c.current=0
local delta,power=G.heat(c)
assert(math.abs(delta+75)<1e-9 and math.abs(power+.75)<1e-9,"remove native heat outside the smaller disk")
distance=2
delta,power=G.heat(c)
assert(math.abs(delta+21)<1e-9 and math.abs(power+.21)<1e-9,"replace native inner heat with scaled falloff")
heat=-100;c.current=70;distance=5
assert(math.abs(G.heat(c)-127.5)<1e-9,"remove native cooling outside the smaller disk")
-- Applying the descriptor must register small stars too, including restored
-- placements; their aura/propagator and physical extent scale exactly once.
TUNING.SANITY_EFFECT_RANGE=10
local body,render,removed=.1,1,nil
local small={components={sanityaura={},propagator={propagaterange=5,damagerange=4}},
    _nw_star_size={set=function(_,v) assert(v==.4) end},
    Transform={GetScale=function() return render,render,render end,SetScale=function(_,v) render=v end},
    GetPhysicsRadius=function() return body end,SetPhysicsRadiusOverride=function(_,v) body=v end,
    ListenForEvent=function(_,event,fn) assert(event=="onremove");removed=fn end}
G.apply(small,{size_mult=.4});G.apply(small,{size_mult=.4})
assert(TheWorld._nw_giant_stars[small] and small._nw_giant_star==.4)
assert(math.abs(small.components.sanityaura.max_distsq-16)<1e-9)
assert(math.abs(small.components.sanityaura.fallofffn(nil,nil,4)-25)<1e-9)
assert(math.abs(small.components.propagator.propagaterange-2)<1e-9 and math.abs(body-.04)<1e-9 and render==.4)
removed();assert(not TheWorld._nw_giant_stars[small])
print("giant environment: enlarged heat/aura reach, wetness, insulation input, immunity, pocket storage, cleanup and noncompounding light pulse")
