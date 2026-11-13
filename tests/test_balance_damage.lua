local Balance=require("nw/balance")
local D=require("nw/balance_damage")
Balance.configure("balanced")
local now,sequence=0,0
GetTime=function() return now end
TheWorld={ismastersim=true,components={nw_identity={Next=function()
    sequence=sequence+1;return "test-root:"..sequence
end}}}
local function close(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." ~= "..tostring(b)) end
local function target()
    local e={components={},tasks={}}
    function e:DoTaskInTime(delay,fn)
        local task={at=now+delay,fn=fn};self.tasks[#self.tasks+1]=task;return task
    end
    local h={currenthealth=100000}
    function h:DoDelta(n) if not self.invincible then self.currenthealth=self.currenthealth+n end;return n end
    local c={inst=e}
    function c:GetAttacked_Internal(a,n,w,s,sp,from_attack)
        self.received={damage=n,planar=sp and sp.planar,from_attack=from_attack}
        if self.redirect then
            self.redirect.redirected_from=e
            self.redirect:GetAttacked_Internal(a,n,w,s,sp,true)
            self.redirect.redirected_from=nil
        elseif not self.blocked then
            h:DoDelta(-(n or 0)-(sp and sp.planar or 0))
            if self.after then self.after() end
        end
        return "native",nil,7
    end
    function c:GetAttacked(...) return self:GetAttacked_Internal(...) end
    e.components.health=h;e.components.combat=c
    D.wrap_combat(c)
    return e,c,h
end
local actor={};local a,ca,ha=target();local b,cb,hb=target()
local p={_nw_root=D.root()};local other={_nw_root=D.root()}
for i=1,12 do
    local before=ha.currenthealth
    local first,second,third=D.attack(p,actor,a,100)
    assert(first=="native" and second==nil and third==7)
    close(before-ha.currenthealth,20+80*.9^(i-1))
end
assert(a._nw_balance_hits[p._nw_root].count==12)
D.attack(p,actor,b,100);close(100000-hb.currenthealth,100)
local before=ha.currenthealth
D.attack(other,actor,a,100);close(before-ha.currenthealth,100)
-- Other players/ownership changes do not reset an existing root.
before=ha.currenthealth;D.attack(p,{},a,100);close(before-ha.currenthealth,20+80*.9^12)
-- A different cast refreshes neither the original count nor its timeout.
now=9;D.attack(other,actor,a,10)
now=10;before=ha.currenthealth;D.attack(p,actor,a,100);close(before-ha.currenthealth,100)
now=19.999;before=ha.currenthealth;D.attack(p,actor,a,100);close(before-ha.currenthealth,92)
now=29.999;before=ha.currenthealth;D.attack(p,actor,a,100);close(before-ha.currenthealth,100)
-- Zero, blocked and invulnerable hits neither count nor keep history alive.
now=30;local count=a._nw_balance_hits[p._nw_root].count
D.attack(p,actor,a,0);assert(a._nw_balance_hits[p._nw_root].count==count)
ca.blocked=true;D.attack(p,actor,a,100);ca.blocked=false
ha.invincible=true;D.attack(p,actor,a,100);ha.invincible=false
assert(a._nw_balance_hits[p._nw_root].count==count and a._nw_balance_hits[p._nw_root].last==29.999)
now=40;before=ha.currenthealth;D.attack(p,actor,a,100);close(before-ha.currenthealth,100)
-- A single native physical+planar attack counts once and preserves input tables.
local weapon={};D.tag(weapon,p)
local sp={planar=50};before=ha.currenthealth
ca:GetAttacked_Internal(actor,100,weapon,nil,sp,true)
close(before-ha.currenthealth,138);close(ca.received.damage,92);close(ca.received.planar,46)
assert(sp.planar==50 and ca.received.from_attack and a._nw_balance_hits[p._nw_root].count==2)
-- Tagged native continuations are independent attacks; direct health damage
-- shares their root, while unrelated native player attacks stay unchanged.
local native={};D.tag(native,p)
before=ha.currenthealth;ca:GetAttacked(native,100);close(before-ha.currenthealth,84.8)
before=ha.currenthealth;D.delta(p,a,-100);close(before-ha.currenthealth,78.32)
before=ha.currenthealth;ca:GetAttacked(actor,100);close(before-ha.currenthealth,100)
assert(a._nw_balance_hits[p._nw_root].count==4 and not actor._nw_root)
-- The combat hit is committed before on-hit explosions/other callbacks.
local nested={_nw_root=D.root()};local nesting=false
ca.after=function()
    if not nesting then nesting=true;D.attack(nested,actor,a,100);nesting=false end
end
before=ha.currenthealth;D.attack(nested,actor,a,100);close(before-ha.currenthealth,192)
ca.after=nil;assert(a._nw_balance_hits[nested._nw_root].count==2)
-- Native damage redirection uses only the actual recipient's multiplier.
local redirectp={_nw_root=D.root()}
D.attack(redirectp,actor,a,100);D.attack(redirectp,actor,a,100)
ca.redirect=cb
before=hb.currenthealth;D.attack(redirectp,actor,a,100,nil,nil,{planar=50})
close(before-hb.currenthealth,150)
before=hb.currenthealth;D.attack(redirectp,actor,a,100,nil,nil,{planar=50})
close(before-hb.currenthealth,138)
assert(a._nw_balance_hits[redirectp._nw_root].count==2 and b._nw_balance_hits[redirectp._nw_root].count==2)
ca.redirect=nil
-- Fun mode remains numerically identical even for previously tagged natives.
Balance.configure("fun");before=ha.currenthealth
for i=1,3 do D.attack(p,actor,a,100);ca:GetAttacked(native,100) end
close(before-ha.currenthealth,600);assert(D.root()==nil)
assert(a._nw_balance_hits[p._nw_root].count==4)
Balance.configure("balanced")
-- No target history enters a save/template; cleanup removes inactive entries.
now=60
for _,task in ipairs(a.tasks) do if task.at<=now then task.fn(a) end end
assert(a._nw_balance_hits==nil and not p.count and not p.last)
-- First hits stay useful, while sustained equal hits approach the 20% floor.
local total,previous=0,1
for n=1,1000 do
    local factor=D.multiplier(n-1)
    assert(factor>=.2 and factor<=previous)
    previous=factor
    if n<=39 then total=total+factor end
end
assert(total/39>.40 and total/39<.41)
close(D.multiplier(1000),.2)
-- Compile the user's timer-scatter build: payload modifiers must not leak to
-- the three 9-damage carriers. Each carrier emits six 29-damage children.
local C=require("nw/compiler")
local wand=require("nw/generator").starter()
wand.stats.mana_max=2000;wand.cards={}
for i,id in ipairs({"scatter_timer","damage_up","damage_up","homing","pierce","repeat_2","scatter"}) do
    wand.cards[i]={spell_id=id,card_uid=tostring(i)}
end
wand.runtime=C.initial(wand.cards,wand.stats,42)
local plan=assert(C.compile(wand))
local carrier=plan.blocks[1].projectiles[1]
local payload=plan.blocks[carrier.payload]
local child=payload.projectiles[1]
assert(carrier.count==3 and carrier.damage==9 and child.damage==29)
assert(carrier.count*payload.copies*child.count==18 and plan.projectile_count==21)
local expected={399.0298168417636,421.28905841416093,441.412985437495}
for order=1,3 do
    local t,_,h=target()
    local cast={_nw_root=D.root()}
    local original=0
    local function hit(damage,n)
        for _=1,n do original=original+damage;D.attack(cast,actor,t,damage) end
    end
    if order==1 then hit(carrier.damage,3);hit(child.damage,36)
    elseif order==2 then for _=1,3 do hit(carrier.damage,1);hit(child.damage,12) end
    else hit(child.damage,36);hit(carrier.damage,3) end
    assert(original==1071 and t._nw_balance_hits[cast._nw_root].count==39)
    close(100000-h.currenthealth,expected[order])
end
print("balance damage: gentle early falloff, ~40% over 39 equal hits, 20% floor, per-root/target timeout, native+planar, nesting, fun parity")
