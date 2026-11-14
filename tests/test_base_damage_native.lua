local Native=require("nw/base_damage_native")
local Balance=require("nw/balance")
local Damage=require("nw/balance_damage")
local function close(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." ~= "..tostring(b)) end
local p={id="edge_trident",engraving="trident",base_damage_multiplier=.5,_nw_root="test"}
local weapon={prefab="trident"};Native.tag(weapon,p)
assert(weapon._nw_native_base_multiplier==.5)
local normal={prefab="trident"}
local player={prefab="wilson"};Native.tag(player,p);assert(player._nw_native_base_multiplier==nil)
local outgoing={prefab="voidcloth_boomerang_proj",_nw_controller={}}
Native.tag(outgoing,{engraving="voidcloth_boomerang",base_damage_multiplier=1.5})
assert(outgoing._nw_native_base_multiplier==nil)
outgoing._nw_controller=nil;Native.tag(outgoing,{engraving="voidcloth_boomerang",base_damage_multiplier=1.5})
assert(outgoing._nw_native_base_multiplier==1.5)
for _,row in ipairs({{"tornado","staff_tornado"},
    {"voidcloth_boomerang_proj","voidcloth_boomerang"}}) do
    local wrapped={prefab="nw_native_"..row[1],_nw_native_prefab=row[1]}
    Native.tag(wrapped,{engraving=row[2],base_damage_multiplier=.75})
    assert(wrapped._nw_native_base_multiplier==.75 and wrapped.prefab=="nw_native_"..row[1],"wrapper identity must preserve native damage without overwriting prefab")
end
for _,row in ipairs({{"trident","trident"},{"tornado","staff_tornado"},
    {"staff_lunarplant","staff_lunarplant"},{"brilliance_projectile_fx","staff_lunarplant"},
    {"dumbbell_marble","dumbbell_marble"}}) do
    local e={prefab=row[1]};Native.tag(e,{engraving=row[2]})
    assert(e._nw_native_base_multiplier==1,"old snapshots default to native damage")
end
local tentacle={prefab="shadowtentacle"}
Native.tag(tentacle,{source_weapon="ruins_bat",base_damage_multiplier=.75})
assert(tentacle._nw_native_base_multiplier==.75)
local bomb={prefab="gunpowder"};Native.tag(bomb,p);assert(bomb._nw_native_base_multiplier==nil)
GetTime=function() return 0 end
local function target(order)
    local e={components={}}
    local h={currenthealth=10000,DoDelta=function(self,n) self.currenthealth=self.currenthealth+n end}
    local c={inst=e}
    function c:GetAttacked_Internal(a,n,w,s,sp,flag)
        self.last={n=n,planar=sp and sp.planar,flag=flag}
        if self.redirect then
            self.redirect.redirected_from=e
            self.redirect:GetAttacked_Internal(a,n,w,s,sp,true)
            self.redirect.redirected_from=nil
        else
            h:DoDelta(-(n or 0)-(sp and sp.planar or 0))
            if self.after then self.after() end
        end
        return "ok",nil,7
    end
    function c:GetAttacked(...) return self:GetAttacked_Internal(...) end
    e.components.health=h;e.components.combat=c
    if order then Damage.wrap_combat(c);Native.wrap_combat(c)
    else Native.wrap_combat(c);Damage.wrap_combat(c) end
    return e,c,h
end
for _,order in ipairs({false,true}) do
    Balance.configure("fun")
    local e,c,h=target(order)
    local sp={planar=20,tag="keep"}
    local a,b,d=c:GetAttacked_Internal(player,100,weapon,nil,sp,true)
    assert(a=="ok" and b==nil and d==7 and c.last.flag)
    close(10000-h.currenthealth,60);assert(sp.planar==20)
    local before=h.currenthealth;c:GetAttacked(player,100,normal,nil,sp)
    close(before-h.currenthealth,120)
    local _,redirect,rh=target(order);c.redirect=redirect
    before=rh.currenthealth;c:GetAttacked(player,100,weapon,nil,sp)
    close(before-rh.currenthealth,60)
    -- A fresh attack nested inside a redirected hit is not another forwarding.
    local nesting=false
    redirect.after=function()
        if not nesting then nesting=true;redirect:GetAttacked(player,100,weapon);nesting=false end
    end
    before=rh.currenthealth;c:GetAttacked(player,100,weapon)
    close(before-rh.currenthealth,100);redirect.after=nil
    Balance.configure("balanced");Damage.tag(weapon,p)
    before=rh.currenthealth;c:GetAttacked(player,100,weapon,nil,sp)
    close(before-rh.currenthealth,60)
    before=rh.currenthealth;c:GetAttacked(player,100,weapon,nil,sp)
    close(before-rh.currenthealth,55.2)
    assert(not c._nw_native_base_forward and not redirect._nw_native_base_forward)
end
Balance.configure("fun")
local _,broken=target()
broken.after=function() error("native error") end
assert(not pcall(broken.GetAttacked,broken,player,100,weapon))
assert(not broken._nw_native_base_forward,"errors must restore adapter state")
