-- Local renderer contract; this harness does not emulate network replication.
local Glow=require("nw/projectile_glow")
local now,dedicated,point,ambient=10,false,.05,0
local samples,started,cancelled=0,0,0
GetTime=function() return now end
TheNet={IsDedicated=function() return dedicated end}
local function events(e)
    e.callbacks={}
    function e:ListenForEvent(name,fn)
        self.callbacks[name]=self.callbacks[name] or {};self.callbacks[name][fn]=true
    end
    function e:RemoveEventCallback(name,fn)
        if self.callbacks[name] then
            self.callbacks[name][fn]=nil
            if not next(self.callbacks[name]) then self.callbacks[name]=nil end
        end
    end
    function e:PushEvent(name)
        local callbacks={}
        for fn in pairs(self.callbacks[name] or {}) do callbacks[#callbacks+1]=fn end
        for _,fn in ipairs(callbacks) do fn(self) end
    end
    return e
end
TheWorld=events({components={ambientlighting={GetVisualAmbientValue=function() return ambient end}}})
function TheWorld:DoPeriodicTask(period,fn)
    assert(period==1/30 and not self.tick,"ordinary heads share one 30Hz clock")
    self.tick=fn;started=started+1
    return {Cancel=function() self.tick=nil;cancelled=cancelled+1 end}
end
TheSim={GetLightAtPoint=function(_,x,y,z)
    samples=samples+1
    assert(x==3 and y==1.4 and z==7,"sample each fx's current world position")
    return point
end}
local function observer(nightvision)
    return {IsValid=function() return true end,components={playervision={HasNightVision=function() return nightvision end}},
        Transform={GetWorldPosition=function() error("observer position must not drive fx light") end}}
end
ThePlayer=observer(false)
local function visual(prefab)
    local fx=events({valid=true,prefab=prefab,AnimState={},Transform={},override=1,bloom="native",alpha=.27})
    function fx:IsValid() return self.valid end
    function fx:Hide() self.hidden=true;self.hides=(self.hides or 0)+1 end
    function fx:Show() self.hidden=false;self.shows=(self.shows or 0)+1 end
    function fx:Remove() self.valid=false;self:PushEvent("onremove") end
    fx.Transform.GetWorldPosition=function() return 3,1.4,7 end
    function fx.AnimState:SetLightOverride(value) fx.override=value;fx.overrides=(fx.overrides or 0)+1 end
    function fx.AnimState:SetBloomEffectHandle() error("glow must not enable bloom") end
    function fx.AnimState:ClearBloomEffectHandle() fx.bloom=nil end
    function fx.AnimState:ClearSymbolBloom(symbol) fx.cleared=symbol end
    function fx.AnimState:SetSymbolLightOverride(symbol,value) fx.symbol=symbol;fx.symbol_light=value end
    function fx.AnimState:OverrideMultColour(r,g,b,a) fx.mask=r and {r,g,b,a} or nil end
    function fx.AnimState:GetMultColour() return unpack(fx.mask or fx.colour or {.8,.6,.4,fx.alpha}) end
    function fx.AnimState:SetMultColour() error("glow must preserve renderer-owned lifetime alpha") end
    return fx
end
local function near(a,b) assert(math.abs(a-b)<.00001,tostring(a).." ~= "..tostring(b)) end
local function tick(time) now=time;if TheWorld.tick then TheWorld.tick(TheWorld) end end

local head=visual()
assert(Glow.attach(head))
near(head.override,1)
assert(TheWorld._nw_projectile_glows and started==1)
local other=visual();Glow.attach(other);Glow.attach(other)
assert(started==1 and #TheWorld._nw_projectile_glows.items==2,"idempotent attachment uses a shared clock")
point=.025;tick(10.01);near(head.override,.5);near(other.override,.5)
point=.01;tick(10.02);near(head.override,.2)
point=.1;tick(10.03);near(head.override,1)

-- A fixed 0.2s ramp begins at first zero, not at the previous lit update.
point=0;tick(11);near(head.override,1)
tick(11.05);near(head.override,.75)
for _=1,20 do Glow.update(head) end
near(head.override,.75) -- Duplicate updates cannot accelerate or restart it.
tick(11.1);near(head.override,.5)
tick(11.2);near(head.override,0)
tick(12);near(head.override,0)
point=.02;tick(12.01);near(head.override,.4)
point=0;tick(12.02);near(head.override,.4)
tick(12.12);near(head.override,.2)
point=.05;tick(12.13);near(head.override,1) -- Early recovery is immediate.
point=0;tick(12.14);near(head.override,1)
tick(12.24);near(head.override,.5) -- Re-entry owns a new ramp.
tick(12.34);near(head.override,0)
assert(not head.hidden and not head.hides and not head.shows and not head.mask and head.alpha==.27,
    "ordinary darkness only changes selflight; visibility and lifetime alpha survive")
local born_dark=visual();Glow.attach(born_dark);near(born_dark.override,0)
tick(12.35);near(born_dark.override,0)

-- Two observers at the same fx coordinate have independent local vision.
local ordinary_observer,night_observer=observer(false),observer(true)
ThePlayer=ordinary_observer;local ordinary=visual();Glow.update(ordinary);near(ordinary.override,0)
ThePlayer=night_observer;local night=visual();Glow.update(night);near(night.override,1)
ThePlayer=ordinary_observer;Glow.update(ordinary);near(ordinary.override,0)
assert(not ordinary._nw_projectile_glow.pool and not night._nw_projectile_glow.pool,
    "beam/trail updates reuse caller clocks")
ambient=.025;Glow.update(ordinary);near(ordinary.override,.5)
point=.04;Glow.update(ordinary);near(ordinary.override,.8)
ambient=.05;Glow.update(ordinary);near(ordinary.override,1)
ambient=0;point=0;ThePlayer=nil
local no_player=visual();Glow.update(no_player);near(no_player.override,0)
ThePlayer=ordinary_observer

local beam=visual();point=.05
Glow.update(beam,{visible=false,manage_visibility=true})
assert(beam.hidden);near(beam.override,1)
Glow.update(beam,{visible=true,manage_visibility=true})
assert(not beam.hidden,"illumination recovery cannot replace geometry clipping")
assert(started==1,"externally updated visuals never register a second task")

head:Remove()
assert(#TheWorld._nw_projectile_glows.items==2 and not head.callbacks.onremove)
Glow.detach(other);Glow.detach(other)
assert(#TheWorld._nw_projectile_glows.items==1)
born_dark:Remove()
assert(not TheWorld._nw_projectile_glows and not TheWorld.tick and started==cancelled)
local a,b=visual(),visual();Glow.attach(a);Glow.attach(b)
TheWorld:PushEvent("onremove")
assert(not TheWorld._nw_projectile_glows and not TheWorld.tick and started==cancelled)
assert(not a.callbacks.onremove and not b.callbacks.onremove and not next(TheWorld.callbacks))

-- Wrappers retain native factories, gameplay identity and native Hide/Show.
local factories={}
Prefab=function(name,fn,assets,dependencies)
    assert(assets==nil and #dependencies==1)
    factories[name]={fn=fn,native=dependencies[1]}
    return name
end
Prefabs={}
local names={"fire_projectile","ice_projectile","voidcloth_boomerang_proj","tornado"}
local original_calls=0
for _,name in ipairs(names) do
    Prefabs[name]={fn=function()
        original_calls=original_calls+1
        local fx=visual(name)
        fx.components={projectile={onhit=function() end}}
        fx.Physics={native=true};fx.sg={native=true}
        fx.OnRemoveEntity=function() end
        fx._native_identity={fx.components,fx.Physics,fx.sg,fx.OnRemoveEntity}
        fx.OnEntityReplicated=function(self) self.original_replicated=true end
        return fx
    end}
end
require("prefabs/nw_native_projectiles")
assert(not factories.nw_native_brilliance_projectile_fx,"native brilliance remains excluded")
TheWorld.ismastersim=false
point=.05
for index,name in ipairs(names) do
    local entry=factories["nw_native_"..name]
    assert(entry.native==name)
    local before=samples
    local fx=entry.fn()
    local identity=fx._native_identity
    assert(fx.components==identity[1] and fx.Physics==identity[2] and fx.sg==identity[3] and fx.OnRemoveEntity==identity[4])
    assert(fx.override==1 and not fx.bloom and fx.mask[4]==0 and not fx._nw_projectile_glow.ready)
    Glow.update(fx)
    assert(samples==before and not fx.hides and not fx.shows,"wait for replicated position without native Hide/Show")
    local baseline_calls=fx.overrides
    fx:Hide();fx:OnEntityReplicated()
    assert(fx.original_replicated and fx._nw_projectile_glow.ready and fx.hidden and not fx.mask and not fx.shows)
    fx:Show()
    point=.025;Glow.update(fx)
    near(fx.mask[1],.4);near(fx.mask[2],.3);near(fx.mask[3],.2);near(fx.mask[4],.27)
    for _=1,20 do Glow.update(fx) end
    near(fx.mask[1],.4) -- Getter returns overrides: old masks must not compound.
    fx.colour={.2,.4,.6,.15};Glow.update(fx)
    near(fx.mask[1],.1);near(fx.mask[2],.2);near(fx.mask[3],.3);near(fx.mask[4],.15)
    now=20+index;point=0;Glow.update(fx)
    now=now+.1;Glow.update(fx);near(fx.mask[1],.05);near(fx.mask[4],.15)
    now=now+.1;Glow.update(fx)
    for i=1,4 do near(fx.mask[i],0) end
    assert(not fx.hidden and fx.hides==1 and fx.shows==1)
    ThePlayer=night_observer;Glow.update(fx)
    assert(not fx.mask and fx.overrides==baseline_calls,"observer vision only changes the local native colour mask")
    ThePlayer=ordinary_observer
    if name=="voidcloth_boomerang_proj" then near(fx.symbol_light,1) end
    fx:Remove();point=.05
end
assert(original_calls==4)
local untouched=Prefabs.fire_projectile.fn()
assert(not untouched._nw_native_prefab and not untouched._nw_projectile_glow and untouched.override==1 and untouched.bloom=="native")
TheWorld.ismastersim=true
local before=samples
local host=factories.nw_native_fire_projectile.fn()
assert(samples==before and not host._nw_projectile_glow.ready and host.mask[4]==0)
host:Hide();Glow.native(host)
assert(host.hidden and host._nw_projectile_glow.ready and host.override==1 and not host.mask and not host.shows)
host:Remove()
assert(not TheWorld.tick and started==cancelled)

dedicated=true
local before=samples
local server=visual();Glow.attach(server);Glow.update(server)
assert(samples==before and not server._nw_projectile_glow and not TheWorld.tick)
local server_native=factories.nw_native_tornado.fn()
assert(server_native._nw_native_prefab=="tornado" and not server_native._nw_projectile_glow)
assert(server_native.override==1 and not server_native.bloom and not server_native.mask and samples==before)
dedicated=false
Glow.attach(nil)
local removed=visual();removed:Remove();Glow.attach(removed)
assert(not removed._nw_projectile_glow)
print("projectile glow: point/ambient/observer light, linear zero fade, shared scheduler, native fixed baseline/local colour mask and cleanup")
