local M=require("nw/dummy_trials")
local now=0
GetTime=function() return now end
EQUIPSLOTS={HANDS="hands"}
local function player()
    return {components={},IsValid=function(self) return not self.removed end,
        HasTag=function(self) return self.ghost end,IsNear=function() return true end,
        GetDistanceSqToInst=function(self) return (self.distance or 0)^2 end,
        GetDisplayName=function() return "Tester" end}
end
local p,q=player(),player()
local s=M.new(10,p)
assert(not M.damage(s,q,100,1) and not s.started)
assert(not M.damage(s,p,0,1) and not M.damage(s,p,0/0,1) and not M.damage(s,p,math.huge,1))
assert(M.damage(s,p,25,4) and s.started==4 and s.damage==25)
M.advance(s,5)
M.advance(s,7)
assert(not s.finished)
assert(M.damage(s,p,75,13.999))
assert(not M.damage(s,p,500,14) and not M.damage(s,q,900,6))
M.advance(s,19)
assert(s.finished and s.damage==100 and s.dps==10)
M.advance(s,30);assert(s.finished and s.damage==100)
local thirty=M.new(30,p);M.damage(thirty,p,300,1);M.advance(thirty,40)
assert(thirty.finished and thirty.damage==300 and thirty.dps==10)
-- Cumulative damage / elapsed since first hit, with a one-second minimum.
local realtime=M.new(10,p)
assert(M.damage(realtime,p,10,1) and realtime.dps==10)
assert(M.damage(realtime,p,20,1.25) and realtime.dps==30)
assert(M.damage(realtime,p,5,1.25) and realtime.dps==35)
assert(not M.damage(realtime,q,900,1.5) and realtime.dps==35)
M.advance(realtime,2);assert(realtime.dps==35)
assert(M.damage(realtime,p,40,2) and realtime.dps==75)
M.advance(realtime,2.25);assert(realtime.dps==60 and realtime.damage==75)
M.advance(realtime,3);assert(realtime.dps==37.5)
M.damage(realtime,p,7,10.75);M.advance(realtime,11)
assert(realtime.finished and realtime.dps==8.2 and realtime.damage==82)
assert(not M.damage(realtime,p,999,11))
M.advance(realtime,40);assert(realtime.dps==8.2 and realtime.damage==82)
local function net() return {v=0,set=function(self,v) self.v=v end,value=function(self) return self.v end} end
local function bag()
    local b={components={},_nw_trial_mode=net(),_nw_trial_text=net(),listeners={},
        HasTag=function(self) return self.burnt end}
    function b:ListenForEvent(event,fn) self.listeners[event]=fn end
    function b:DoPeriodicTask(_,fn) self.tick=fn end
    b.components.health={DoDelta=function(_,amount) M.hit(b,b._nw_health_owner,-amount) end}
    b.components.combat={GetAttacked=function(_,attacker,damage)
        b.components.health:DoDelta(-damage,nil,nil,nil,attacker)
    end}
    M.setup(b)
    return b
end
local b,c=bag(),bag()
assert(M.select(b,p) and b._nw_trial.duration==10 and b._nw_trial_mode.v==1)
assert(not M.select(b,q) and not M.select(c,p),"tester and mana cannot belong to two bags")
M.cast(p,40,now);assert(b._nw_trial.mana==40 and b._nw_trial.casts==1,"first launch counts before damage")
now=1;M.cast(p,5,now);b.tick()
assert(b._nw_trial.mana==45 and b._nw_trial.casts==2 and not b._nw_trial.started,
    "prepared misses count without starting the damage clock")
assert(b._nw_trial.damage==0 and b._nw_trial.dps==0)
assert(M.display(b._nw_trial_text.v):find("45.0",1,true),"prepared casts replicate immediately")
b.components.combat:GetAttacked(q,800);assert(not b._nw_trial.started)
now=2
b.components.combat:GetAttacked(p,20);assert(b._nw_trial.damage==20)
M.cast(q,100,now);M.cast(p,12.5,now);assert(b._nw_trial.mana==57.5 and b._nw_trial.casts==3)
M.cast(p,0,now);assert(b._nw_trial.casts==4,"successful zero-mana cast counts once")
M.cast(p,0/0,now);M.cast(p,-1,now);M.cast(p,math.huge,now)
assert(b._nw_trial.casts==4,"invalid cast reports must not count")
local continuation={_nw_journal_source={owner=p}}
b.components.combat:GetAttacked(continuation,30)
assert(b._nw_trial.damage==50,"tagged native continuation has original caster")
b.components.health:DoDelta(-10,nil,nil,nil,p)
assert(b._nw_trial.damage==60 and not b._nw_health_owner and not b._nw_damage_owner)
now=12;M.cast(p,100,now);b.components.combat:GetAttacked(p,900);b.tick()
assert(b._nw_trial.finished and b._nw_trial.damage==60 and b._nw_trial.mana==57.5 and b._nw_trial.casts==4)
assert(M.display(b._nw_trial_text.v):find("\n"..string.format(require("nw/locale").t("施法次数 %d"),4),1,true))
M.cast(p,5,now+1);assert(b._nw_trial.casts==4,"completed result remains frozen")
-- Finished results can be claimed by a different tester, but running windows cannot.
assert(M.select(b,q) and b._nw_trial.tester==q and b._nw_trial.casts==0)
q.removed=true;b.tick();q.removed=false
assert(M.select(b,p) and not b._nw_trial.started and b._nw_trial.duration==10)
assert(M.select(b,p) and b._nw_trial.duration==30)
assert(M.select(b,p) and not b._nw_trial and b._nw_trial_mode.v==0)
local L=require("nw/locale")
local raw="10|10.00|100.000|12.500|2|7.000|2|Tester"
L.configure("en");assert(M.display(raw):find("Trial complete") and M.display(raw):find("Window mana 12.5") and not M.display(raw):find("Mana.blocked"))
assert(M.display(raw):find("Damage 100.0\nDPS 7.0",1,true))
assert(M.display(raw):find("\nCasts 2",1,true))
L.configure("zh");assert(M.display(raw):find("测试完成") and M.display(raw):find("窗口耗蓝 12.5") and not M.display(raw):find("缺蓝"))
assert(M.display(raw):find("伤害 100.0\nDPS 7.0",1,true))
assert(M.display(raw):find("\n施法次数 2",1,true))
assert(M.select(c,p));p.removed=true;c.tick();assert(not c._nw_trial)
p.removed=false
-- Trial updates must not inspect or update any wand's readiness.
p.components.inventory={GetEquippedItem=function() error("trial timer queried equipped wand") end}
assert(M.select(c,q))
now=20;c.components.combat:GetAttacked(q,10)
q.components.inventory=p.components.inventory
now=21;c.tick();assert(not c._nw_trial.finished and c._nw_trial.dps==10)
now=22;c.tick();assert(c._nw_trial.dps==5)
assert(M.display(c._nw_trial_text.v):find("\nDPS 5.0\n",1,true),"idle timer must replicate elapsed-time DPS")
now=29.5;c.components.combat:GetAttacked(q,15)
now=30;c.tick();assert(c._nw_trial.finished and c._nw_trial.damage==25 and c._nw_trial.dps==2.5)
now=30.5;c.tick();assert(c._nw_trial.dps==2.5 and c._nw_trial.damage==25)
assert(M.display(c._nw_trial_text.v):find("\nDPS 2.5\n",1,true),"completed trial freezes final average")
p.components.inventory.GetEquippedItem=function() return nil end
-- Leaving >30 units resets every phase and releases the tester for another bag.
for _,phase in ipairs({"prepared","running","finished"}) do
    local tester=player()
    local first,second=bag(),bag()
    assert(M.select(first,tester))
    M.cast(tester,10,now)
    if phase~="prepared" then first.components.combat:GetAttacked(tester,20) end
    if phase=="finished" then now=now+10;first.tick() end
    tester.distance=29.9;first.tick();assert(first._nw_trial)
    tester.distance=30;first.tick();assert(first._nw_trial,"exactly 30 units stays in range")
    tester.distance=30.1;first.tick()
    assert(not first._nw_trial and first._nw_trial_mode.v==0 and first._nw_trial_text.v=="")
    M.cast(tester,99,now);assert(not first._nw_trial)
    tester.distance=0;assert(M.select(second,tester))
    assert(second._nw_trial.casts==0 and second._nw_trial.mana==0)
end
print("dummy trials: elapsed-time DPS with one-second floor, prepared cast counting, fixed deadlines, 30-unit reset in all phases, isolated tester and continuation damage")

-- Native AddAction writes its default string; install the dynamic table afterwards.
Action=function(v) return v end
ActionHandler=function(action,state) return {action=action,state=state} end
STRINGS={ACTIONS={}}
local action,collect
M.install({AddAction=function(a) action=a;STRINGS.ACTIONS[a.id]=a.str end,
    AddComponentAction=function(_,_,fn) collect=fn end,AddStategraphActionHandler=function() end})
assert(type(STRINGS.ACTIONS.NW_DUMMY_TRIAL)=="table")
assert(STRINGS.ACTIONS.NW_DUMMY_TRIAL.TEN=="10秒测试")
assert(STRINGS.ACTIONS.NW_DUMMY_TRIAL.THIRTY=="30秒测试")
assert(STRINGS.ACTIONS.NW_DUMMY_TRIAL.COMBO=="连击")
assert(STRINGS.ACTIONS.NW_DUMMY_TRIAL.RESET=="重置")
assert(action.strfn({target=b})=="TEN")
local target={prefab="nw_spell_punchingbag",HasTag=function() return false end}
local actions={};collect(target,p,actions,true);assert(#actions==1)
p.components.inventory.GetEquippedItem=function() return {components={}} end
actions={};collect(target,p,actions,true);assert(#actions==0)
assert(not M.select(b,p),"server also rejects mode changes with occupied hands")

-- Match DST's replacement semantics, not a stub that only keeps the last
-- callback. Both modules must coexist in either registration order.
local Recycle=require("nw/recycle")
for _,order in ipairs({{M,Recycle},{Recycle,M}}) do
    local collectors,registered,handlers={},{},{}
    local env={
        AddAction=function(a) registered[a.id]=a;STRINGS.ACTIONS[a.id]=a.str end,
        AddComponentAction=function(kind,component,fn)
            collectors[kind]=collectors[kind] or {}
            collectors[kind][component]=fn
        end,
        AddStategraphActionHandler=function(sg,handler)
            handlers[sg]=handlers[sg] or {}
            handlers[sg][handler.action.id]=handler.state
        end,
    }
    for _,module in ipairs(order) do module.install(env) end
    local function scene(entity,doer,right)
        local result={}
        for component in pairs(entity.components) do
            local fn=collectors.SCENE[component]
            if fn then fn(entity,doer,result,right) end
        end
        return result
    end
    local tester=player()
    local held=nil
    tester.components.inventory={GetEquippedItem=function() return held end}
    tester.replica={inventory=tester.components.inventory}
    local dummy=bag()
    dummy.prefab="nw_spell_punchingbag";dummy.components.inspectable={}
    local furnace={prefab="nw_disassembler",components={inspectable={},health={}},
        HasTag=function(_,tag) return tag=="nw_disassembler" end}
    local picked=scene(dummy,tester,true)
    assert(#picked==1 and picked[1]==registered.NW_DUMMY_TRIAL,
        "furnace registration must not erase punching bag right-click")
    for _,duration in ipairs({10,30,0}) do
        assert(picked[1].fn({target=dummy,doer=tester}))
        assert((dummy._nw_trial and dummy._nw_trial.duration or 0)==duration)
    end
    local recycle=scene(furnace,tester,true)
    assert(#recycle==1 and recycle[1]==registered.NW_RECYCLE)
    assert(#scene(dummy,tester,false)==0 and #scene(furnace,tester,false)==0)
    assert(#scene({prefab="punchingbag",components=dummy.components,HasTag=dummy.HasTag},tester,true)==0)
    held={};assert(#scene(dummy,tester,true)==0);held=nil
    dummy.burnt=true;assert(#scene(dummy,tester,true)==0)
    for _,sg in ipairs({"wilson","wilson_client"}) do
        assert(handlers[sg].NW_DUMMY_TRIAL=="doshortaction")
        assert(handlers[sg].NW_RECYCLE=="startchanneling")
    end
end
print("dummy trial actions: coexist with furnace, both install orders, mode cycle, hand/burnt filters and both stategraphs")
