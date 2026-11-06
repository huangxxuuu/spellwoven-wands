Class=function(constructor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...) local self=setmetatable({},cls);constructor(self,...);return self end})
end
local Receipt=require("components/nw_firstboss")
local Bonus=require("nw/first_boss_reward")
local function player(distance,ghost)
    local p={components={},distance=distance,ghost=ghost}
    function p:IsValid() return true end
    function p:IsInLimbo() return false end
    function p:GetDistanceSqToInst() return self.distance*self.distance end
    p.components.nw_firstboss=Receipt(p)
    return p
end
local boss={prefab="deerclops",HasTag=function(_,tag) return tag=="epic" end}
local a,b,c=player(0),player(12,true),player(12.01)
AllPlayers={a,b,c}
local cards={}
local function drop(prefab)
    assert(prefab=="nw_spellcard")
    local card={SetSpell=function(self,id) self.id=id end}
    cards[#cards+1]=card;return card
end
math.random=function(n) return n or .5 end
assert(Bonus.pay(boss,boss,drop,{})==2 and #cards==2)
assert(cards[1].id=="frost_hit" and cards[2].source=="first_boss:deerclops")
assert(not c.components.nw_firstboss.claimed)
assert(Bonus.pay(boss,boss,drop,{})==0,"one reward per nearby player")
c.distance=5;math.random=function() return .0499 end
assert(Bonus.pay(boss,boss,drop,{})==1 and cards[3].id=="imprint_hit")
local restored=Receipt(c);restored:OnLoad(c.components.nw_firstboss:OnSave());assert(restored.claimed)
local fresh=player(1);AllPlayers={fresh}
assert(Bonus.pay(boss,boss,function() return nil end,{})==0 and not fresh.components.nw_firstboss.claimed)
local ordinary={prefab="spider",HasTag=function() return false end}
assert(Bonus.pay(ordinary,ordinary,drop,{})==0)
assert(Bonus.pay(ordinary,ordinary,drop,{group="A"})==1,"registered final encounter qualifies")
-- Character reroll preserves the receipt alongside native data.
TheWorld={ismastersim=true};local init
Bonus.install({AddPlayerPostInit=function(fn) init=fn end})
local p={components={},AddComponent=function(self) self.components.nw_firstboss=Receipt(self) end,
    SaveForReroll=function() return {age=123} end,LoadForReroll=function(self,data) self.age=data.age end}
init(p);p.components.nw_firstboss.claimed=true
local saved=p:SaveForReroll();assert(saved.age==123 and saved.nw_firstboss.claimed)
p.components.nw_firstboss.claimed=false;p:LoadForReroll(saved)
assert(p.age==123 and p.components.nw_firstboss.claimed)
local n=0
assert(Bonus.choose(function(max) n=n+1;return max and 1 or .05 end)=="spark_hit" and n==2)
print("first boss: per-player 12-unit inclusion, ghosts, no last-hit credit, once-only save/reroll, spawn failure and 5% modifier")
