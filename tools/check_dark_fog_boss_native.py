"""Offline Lua 5.1 execution of packaged DST SGs/groundpounder, never data/scripts.

Engine entities/physics and combat dispatch are doubles. The actual native SG
timelines, ice generation/AOE, groundpound scheduling/destruction are executed.
Compare unmodified native runs against hooked runs using identical random seeds.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from lupa.lua51 import LuaRuntime
from native_animation import read_animation

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--game", type=Path, default=Path("E:/SteamLibrary/steamapps/common/Don't Starve Together"))
args = parser.parse_args()
archive = args.game / "data/databundles/scripts.zip"
GRAPH_NAMES = ("deerclops", "bearger", "dragonfly", "toadstool", "minotaur", "alterguardian_phase1", "alterguardian_phase3", "eyeofterror", "moose")
PREFABS = GRAPH_NAMES + ("toadstool_dark", "twinofterror1", "twinofterror2")
paths = ["scripts/components/groundpounder.lua", "scripts/components/combat.lua"] + [
    f"scripts/stategraphs/SG{p}.lua" for p in GRAPH_NAMES
] + ["scripts/prefabs/deerclops.lua", "scripts/stategraphs/commonstates.lua", "scripts/prefabs/toadstool.lua", "scripts/prefabs/mushroombomb.lua"]
with zipfile.ZipFile(archive) as bundle:
    sources = {p: bundle.read(p).decode("utf-8") for p in paths}
with zipfile.ZipFile(args.game / "data/anim/mushroombomb.zip") as art:
    mushroom_anim=art.read("anim.bin")
    mushroom_durations={clip["name"]:len(clip["frames"])/clip["fps"] for clip in read_animation(mushroom_anim)}

INIT = r'''
FRAMES=1/30; PI=math.pi; TWOPI=2*PI; DEGREES=PI/180
function noop() end
function Class(ctor)
    local c={};c.__index=c
    return setmetatable(c,{__call=function(_,...) local o=setmetatable({},c);ctor(o,...);return o end})
end
function State(s) local tags={};for _,v in ipairs(s.tags or {}) do tags[v]=true end;s.tags=tags;return s end
function StateGraph(name, states, events, initial, actions)
    local t={name=name,states={},events=events};for _,s in ipairs(states) do t.states[s.name]=s end;return t
end
function TimeEvent(t,fn) return {time=t,fn=fn} end
function FrameEvent(n,fn) return TimeEvent(n*FRAMES,fn) end
function SoundFrameEvent(n,...) return FrameEvent(n,noop) end
function SoundTimeEvent(n,...) return TimeEvent(n,noop) end
function EventHandler(n,fn) return {name=n,fn=fn} end
function ActionHandler(...) return {} end
CommonStates=setmetatable({}, {__index=function() return noop end})
CommonHandlers=setmetatable({}, {__index=function() return function() return {} end end})
CommonHandlers.OnNoSleepTimeEvent=TimeEvent
package.preload['stategraphs/commonstates']=function() return true end
package.preload.easing=function() return {} end
package.preload['util/sourcemodifierlist']=function() return {} end
package.preload['components/spdamageutil']=function() return {} end
function shallowcopy(t) local out={};for k,v in pairs(t) do out[k]=v end;return out end
function GetRandomMinMax(a,b) return a+math.random()*(b-a) end
function RoundBiasedUp(v) return math.floor(v+.5) end
function DiffAngleRad(a,b) return math.abs((a-b+math.pi)%(2*math.pi)-math.pi) end
function DiffAngle(a,b) return math.abs((a-b+180)%360-180) end
function Remap(v,a,b,c,d) return c+(v-a)/(b-a)*(d-c) end
ACTIONS=setmetatable({}, {__index=function(t,k) rawset(t,k,{id=k});return t[k] end})
TUNING=setmetatable({DEERCLOPS_ATTACK_RANGE=6,DEERCLOPS_ATTACK_PERIOD=3,
    MAX_WALKABLE_PLATFORM_RADIUS=10,BEARGER_NORMAL_GROUNDPOUND_COOLDOWN=10,BEARGER_MELEE_RANGE=6,DRAGONFLY_POUND_CD=20,
    ALTERGUARDIAN_PHASE1_AOERANGE=4,EYEOFTERROR_AOERANGE=3,TOADSTOOL_MUSHROOMBOMB_RADIUS=3.5},
    {__index=function() return 1 end})
CAMERASHAKE={FULL=1,SIDE=2,VERTICAL=3}; COLLISION={}; EQUIPSLOTS={HANDS='hands'}
local vector={};vector.__index=vector
function vector:Get() return self.x,self.y,self.z end
function vector:GetNormalized()
    local n=math.sqrt(self.x*self.x+self.y*self.y+self.z*self.z)
    return Vector3(self.x/n,self.y/n,self.z/n)
end
function vector.__sub(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
function Vector3(x,y,z) return setmetatable({x=x,y=y,z=z},vector) end
Point=Vector3
function ShakeAllCameras(...) end
function PlayFootstep(...) end
function Launch(...) end
function GetEntityTemperature(t) return t.temperature end
function DoDeltaTemperatureToEntity(t,delta) t.temperature=t.temperature+delta end
function GetTime() return NOW end
function checkbit(a,b) return false end
NOW=0; QUEUE={}; SEQ=0; NOTICES={}; TARGETS={}; DISPATCH={}; FX={}
function Schedule(inst,delay,fn,...)
    SEQ=SEQ+1;local t={time=NOW+delay,seq=SEQ,inst=inst,fn=fn,args={...},Cancel=function(s) s.cancelled=true end}
    QUEUE[#QUEUE+1]=t;return t
end
function Advance(untiltime)
    while true do
        table.sort(QUEUE,function(a,b) return a.time==b.time and a.seq<b.seq or a.time<b.time end)
        if #QUEUE==0 or QUEUE[1].time>untiltime then break end
        local t=table.remove(QUEUE,1);NOW=t.time
        if not t.cancelled then t.fn(t.inst,unpack(t.args)) end
    end
    NOW=untiltime
end
local function null_methods() return setmetatable({}, {__index=function() return noop end}) end
function SpawnPrefab(name)
    local f={name=name,Transform=null_methods(),SoundEmitter=null_methods(),SetFXOwner=noop,RestartFX=noop,FastForward=noop,
        IsValid=function() return true end,PushEvent=noop,components={timer={StartTimer=noop}}}
    function f.Transform:SetPosition(x,y,z) f.x,f.z=x,z end
    FX[#FX+1]=f;return f
end
TheWorld={ismastersim=true,PushEvent=noop,Map={IsLandTileAtPoint=function() return true end,IsDockAtPoint=function() return false end,
    IsVisualGroundAtPoint=function() return true end,GetPlatformAtPoint=function() return nil end}}
TheNet={IsDedicated=function() return true end}
TheSim={FindEntities=function(_,x,y,z,r,must,no)
    if must and (must[1]=='walkableplatform' or must[1]=='_inventoryitem') then return {} end
    local out={}
    for _,v in ipairs(TARGETS) do
        if v:GetDistanceSqToPoint(x,y,z)<=r*r then out[#out+1]=v end
    end
    table.sort(out,function(a,b) return a:GetDistanceSqToPoint(x,y,z)<b:GetDistanceSqToPoint(x,y,z) end)
    return out
end}
package.loaded['nw/dark_fog']={disperse_circle=function(world,x,z,r,inner)
    NOTICES[#NOTICES+1]={time=NOW,x=x,z=z,r=r,inner=inner or 0}
end,contains=function(_,inst) return inst.fog_inside==true end,
disperse_sector=function(world,x,z,r,rotation,arc)
    NOTICES[#NOTICES+1]={time=NOW,x=x,z=z,r=r,rotation=rotation,arc=arc}
end}
'''

FIXTURE = r'''
function MakeTarget(x,z)
    local t={x=x,z=z,temperature=20,components={},hits=0,cold=0,burns=0,work=0,damage=0,drops=0}
    function t:IsValid() return true end
    function t:IsInLimbo() return false end
    function t:HasTag() return false end
    function t:GetPosition() return Vector3(self.x,0,self.z) end
    t.Transform={GetWorldPosition=function() return t.x,0,t.z end}
    function t:GetPhysicsRadius() return self.physicsradius or 0 end
    function t:GetDistanceSqToPoint(a,b,c)
        if type(a)=='table' then c=a.z;a=a.x end
        return (self.x-a)^2+(self.z-c)^2
    end
    function t:PushEvent() end
    t.components.health={IsDead=function() return false end}
    t.components.combat={GetAttacked_Internal=function(_,attacker,damage)
        t.hits=t.hits+1;t.damage=t.damage+damage
        DISPATCH[#DISPATCH+1]={time=NOW,x=t.x,z=t.z,mult=.8}
    end}
    t.components.combat.GetAttacked=t.components.combat.GetAttacked_Internal
    t.components.combat.ShouldRecoil=function() return false end
    t.components.freezable={IsFrozen=function() return false end,
        AddColdness=function(_,v) t.cold=t.cold+v end,SpawnShatterFX=noop}
    t.components.burnable={IsBurning=function() return t.burns>0 end,Ignite=function() t.burns=t.burns+1 end}
    t.components.workable={CanBeWorked=function() return true end,action=ACTIONS.CHOP,GetWorkAction=function() return ACTIONS.CHOP end,
        Destroy=function() t.work=t.work+1 end}
    local item={Physics={Teleport=function(_,a,b,c) t.drop_position={a,b,c} end,
        SetVel=function(_,a,b,c) t.drop_velocity={a,b,c} end},HasTag=function() return false end,
        GetPosition=function() return t:GetPosition() end}
    t.components.inventory={GetEquippedItem=function() return item end,
        DropItem=function(_,dropped) assert(dropped==item);t.drops=t.drops+1 end}
    return t
end
function MakeBoss(prefab,graph)
    local e={prefab=prefab,components={},events={},timers={},icespike_pool={},stand='bi',sounds={},stops=0,restarts=0,
        pound_speed=0,pound_cd=10,_soundpath='test/'}
    function e:IsValid() return true end
    function e:IsInLimbo() return false end
    function e:IsAsleep() return false end
    function e:HasTag() return false end
    e.AddTag=noop;e.RemoveTag=noop
    function e:ListenForEvent(n,fn) self.events[n]=fn end
    function e:PushEvent(n,data) if self.events[n] then self.events[n](self,data) end end
    function e:DoTaskInTime(...) return Schedule(self,...) end
    function e:GetPosition() return Vector3(0,0,0) end
    function e:GetAngleToPoint(x,y,z) return -math.atan2(z,x)*180/math.pi end
    function e:SwitchToEightFaced() end
    function e:SwitchToFourFaced() end
    function e:IsStandState(s) return self.stand==s end
    function e:SetStandState(s) self.stand=s end
    function e:StopBrain(reason)
        self.stops=self.stops+1;self._brainstopped=self._brainstopped or {};self._brainstopped[reason]=true
    end
    function e:RestartBrain(reason)
        if self._brainstopped and self._brainstopped[reason] then
            self.restarts=self.restarts+1;self._brainstopped[reason]=nil
            if next(self._brainstopped)==nil then self._brainstopped=nil end
        end
    end
    function e:ClearBufferedAction() self.bufferedaction=nil end
    e.Transform={GetWorldPosition=function() return 0,0,0 end,GetRotation=function() return 0 end,SetRotation=noop}
    e.AnimState=setmetatable({AnimDone=function() return true end},{__index=function() return noop end})
    e.SoundEmitter={PlaySound=noop,KillSound=noop};e.Physics={Stop=noop}
    e.components.health={IsDead=function() return false end}
    e.components.locomotor={StopMoving=noop,Stop=noop}
    e.components.timer={TimerExists=function(_,n) return e.timers[n]~=nil end,
        StopTimer=function(_,n) e.timers[n]=nil end,StartTimer=function(_,n,t) e.timers[n]=t end}
    e.components.combat={DropTarget=function(c) c.target=nil end,
        InCooldown=function() return e.cooldown==true end,CanTarget=function() return true end,
        CanAttack=function(_,target) return target~=nil and not e.cooldown end,CalcAttackRangeSq=function() return 100 end,
        EnableAreaDamage=noop,StartAttack=noop,RestartCooldown=noop,
        SetDefaultDamage=function(self,v) self.defaultdamage=v end,
        DoAttack=function(component,target,a,b,c,mult)
            target=target or component.target
            if not target or e.miss then return end
            e:PushEvent('onattackother',{target=target})
            target.hits=target.hits+1;DISPATCH[#DISPATCH+1]={time=NOW,x=target.x,z=target.z,mult=mult or 1}
            if prefab=='deerclops' then NativeDeerOnHit(e,{target=target}) end
        end}
    if prefab=='alterguardian_phase3' then
        local c=e.components.combat;c.inst=e;c.areahitrange=3;c.areahitdamagepercent=.8
        c.GetWeapon=function() return nil end;c.CanHitTarget=function() return false end
        c.IsValidTarget=function(_,target) return target~=e end
        c.CalcDamage=function() return 80,nil end
        c.ClearAttackTemps=NativeCombat.ClearAttackTemps
        c.DoAttack=NativeCombat.DoAttack;c.DoAreaAttack=NativeCombat.DoAreaAttack
    elseif prefab=='dragonfly' or prefab=='minotaur' then
        local c=e.components.combat
        c.GetWeapon=function() return nil end
        c.CanHitTarget=function(_,target) return target~=nil and not e.miss end
        c.CalcDamage=function() return e.zero_damage and 0 or 80,nil end
        c.CalcReflectedDamage=function() return 0,nil end
        c.ClearAttackTemps=NativeCombat.ClearAttackTemps;c.DoAttack=NativeCombat.DoAttack
    end
    e.components.combat.inst=e
    e.components.combat.defaultdamage=80
    if HookCombat then HookCombat(e.components.combat) end
    local gp=NativeGround(e);e.components.groundpounder=gp;gp:UseRingMode()
    gp.numRings=3;gp.radiusStepDistance=2
    if prefab=='bearger' then gp.ringWidth=1.5;gp.damageRings=3;gp.destroyer=true
    elseif prefab=='minotaur' then gp.numRings=2;gp.damageRings=2;gp.destructionRings=2;gp.ringWidth=1.65
    elseif prefab=='toadstool' or prefab=='toadstool_dark' then gp.radiusStepDistance=2.5;gp.ringWidth=1.5;gp.damageRings=3
    else gp.initialRadius=1.5;gp.ringWidth=2;gp.damageRings=2;gp.burner=true;gp.groundpounddamagemult=.5 end
    if HookGround then HookGround(gp) end
    -- Native states under test, a minimal idle for controlled completion only.
    graph.states.test_idle={name='idle',tags={idle=true}}
    graph.states.test_interrupt={name='test_interrupt',tags={busy=true}}
    e.sg={sg=graph,currentstate=graph.states.test_idle,statemem={},mem={},generation=0}
    if prefab=='eyeofterror' or prefab=='twinofterror1' or prefab=='twinofterror2' then e.sg.mem.transformed=true end
    function e.sg:HasStateTag(t) return self.currentstate.tags[t]==true end
    function e.sg:HasAnyStateTag(...)
        for _,t in ipairs({...}) do if self:HasStateTag(t) then return true end end;return false
    end
    function e.sg:AddStateTag(t) self.currentstate.tags[t]=true end
    function e.sg:RemoveStateTag(t) self.currentstate.tags[t]=nil end
    function e.sg:GoToState(name,params)
        local old=self.currentstate;if old.onexit then old.onexit(e,name) end
        self.currentstate=assert(graph.states[name],name);self.statemem={};self.generation=self.generation+1
        local generation=self.generation
        if self.currentstate.onenter then self.currentstate.onenter(e,params) end
        if self.generation~=generation then return end
        for _,event in ipairs(self.currentstate.timeline or {}) do
            Schedule(e,event.time,function(owner) if owner.sg.generation==generation then event.fn(owner) end end)
        end
    end
    function e:AnimOver(eventname)
        for _,event in ipairs(self.sg.currentstate.events or {}) do
            if event.name==(eventname or 'animover') then event.fn(self);return end
        end
    end
    if prefab=='toadstool' or prefab=='toadstool_dark' then
        e.DoMushroomBomb=NativeToadBomb;e.mushroombomb_prefab=prefab=='toadstool' and 'mushroombomb_projectile' or 'mushroombomb_dark_projectile'
        e.mushroombomb_maxchain=1;e.mushroombomb_cd=5
        if PrefabHooks and PrefabHooks[prefab] then PrefabHooks[prefab](e) end
    end
    return e
end
function RunScenario(prefab,with_target,mode)
    math.randomseed(431); NOW=0;QUEUE={};SEQ=0;NOTICES={};TARGETS={};DISPATCH={};FX={}
    if with_target then TARGETS={MakeTarget(1,0),MakeTarget(4,0)} end
    local e=MakeBoss(prefab,NativeGraphs[prefab])
    local native_entry=string.find(mode,'native_',1,true)==1
    local fallback=string.find(mode,'fallback',1,true)==1
    e.fog_inside=mode~='ordinary'
    if prefab=='moose' then e.components.combat.target=TARGETS[1];e.CanDisarm=true end
    if fallback then
        e.timers[({bearger='GroundPound',dragonfly='groundpound_cd',minotaur='stomptimer',toadstool='pound_cd',toadstool_dark='pound_cd'})[prefab]]=30
        e.components.combat.target=TARGETS[1]
        if TARGETS[1] then TARGETS[1].physicsradius=.5 end
    end
    if Boss then assert(Boss.supports(e),prefab..' real SG failed guard') end
    local first=({deerclops='attack',bearger='pound',dragonfly='pound_pre',toadstool='pound_pre',toadstool_dark='pound_pre',
        minotaur='stomp',alterguardian_phase1='tantrum_pre',alterguardian_phase3='atk_stab',eyeofterror='chomp',
        twinofterror1='chomp',twinofterror2='chomp',moose='disarm'})[prefab]
    if fallback then first=(prefab=='toadstool' or prefab=='toadstool_dark') and 'mushroombomb' or 'attack' end
    if mode=='fallback_native' then native_entry=true end
    if Boss and mode~='ordinary' and not native_entry then assert(Boss.update(e,0,true))
    else e.sg:GoToState(first,e.components.combat.target) end
    if Boss and native_entry then
        assert(e._nw_fog_boss_cast and not e._nw_fog_boss_cast.brain_owned and e.stops==0)
        assert(not Boss.update(e,0,true) and e._nw_fog_boss_cast)
    end
    if prefab=='dragonfly' and not fallback then e:AnimOver() end -- native pre transitions to pound
    if prefab=='alterguardian_phase1' then e:AnimOver() end
    if mode=='leave' or mode=='native_leave' then e.fog_inside=false;if Boss then Boss.leave(e) end end
    if mode=='interrupt_before' or mode=='fallback_interrupt_before' then Advance(.01);e.sg:GoToState('test_interrupt')
    elseif mode=='interrupt_after' or mode=='fallback_interrupt_after' then
        local frame=({deerclops=31,bearger=20,dragonfly=2,toadstool=36,toadstool_dark=36,minotaur=58,
            alterguardian_phase1=8,alterguardian_phase3=29,eyeofterror=25,twinofterror1=25,twinofterror2=25,moose=15})[prefab]
        if fallback then frame=14 end
        Advance(frame*FRAMES+.001)
        e.sg:GoToState('test_interrupt')
    end
    if mode~='interrupt_before' and mode~='interrupt_after' then
        if (prefab=='toadstool' or prefab=='toadstool_dark') and not fallback then
            Advance(1.4);e:AnimOver();Advance(1.8);e:AnimOver()
        elseif prefab=='alterguardian_phase1' then
            while e.sg.currentstate.name=='tantrum' do Advance(NOW+.4);e:AnimOver() end
        end
    end
    Advance(fallback and (prefab=='toadstool' or prefab=='toadstool_dark') and 6 or 3)
    if mode=='complete' or native_entry then
        -- Execute real outgoing animation handlers/onexit; the destination's
        -- unrelated idle/taunt AI is outside this targeted scheduler fixture.
        e.sg.sg.states.idle={name='idle',tags={idle=true}}
        e.sg.sg.states.taunt={name='taunt',tags={busy=true}}
        e:AnimOver((prefab=='minotaur' and not fallback or prefab=='moose') and 'animqueueover' or 'animover')
        if prefab=='dragonfly' and not fallback then Advance(NOW+.2);e:AnimOver() end
        assert(e.sg.currentstate.name=='idle' or e.sg.currentstate.name=='taunt',prefab..' did not finish naturally')
        if Boss then
            assert(e._nw_fog_boss_cast==nil and e._brainstopped==nil, 'cast/brain reason leaked')
            assert(e.restarts==(native_entry and 0 or 1), 'resume only a brain we stopped')
            -- Reactions may repeat under continuous coverage; this fixture
            -- compares one native move only. Separate tests exercise reentry.
        end
    end
    local target_stats={}
    for i,t in ipairs(TARGETS) do target_stats[i]={hits=t.hits,cold=t.cold,temp=t.temperature,burns=t.burns,work=t.work,damage=t.damage,
        drops=t.drops,drop_position=t.drop_position,drop_velocity=t.drop_velocity} end
    return {notices=NOTICES,dispatch=DISPATCH,targets=target_stats,stops=e.stops,restarts=e.restarts,can_disarm=e.CanDisarm}
end
'''

BOMB_FIXTURE = r'''
local original_spawn=SpawnPrefab
SpawnPrefab=function(name)
    if not string.find(name,'mushroombomb',1,true) then return original_spawn(name) end
    local projectile=string.find(name,'projectile',1,true)~=nil
    local e={prefab=name,x=0,z=0,components={},SoundEmitter={PlaySound=noop},_explode={push=noop}}
    function e:IsValid() return not self.removed end
    function e:Remove() self.removed=true end
    function e:DoTaskInTime(...) return Schedule(self,...) end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end,SetPosition=function(_,x,y,z) e.x,e.z=x,z end}
    e.AnimState={animation='land',PlayAnimation=function(self,name) self.animation=name end,
        GetCurrentAnimationLength=function(self) return NativeBombDurations[self.animation] end}
    local tracked={}
    e.components.entitytracker={TrackEntity=function(_,key,value) tracked[key]=value end,GetEntity=function(_,key) return tracked[key] end}
    if projectile then
        local cp={SetHorizontalSpeed=noop,onhitfn=name=='mushroombomb_projectile' and NativeBombHit or NativeDarkBombHit}
        cp.Launch=function(component,pos,attacker)
            Schedule(e,.1,function() e.x,e.z=pos.x,pos.z;component.onhitfn(e,attacker) end)
        end
        e.components.complexprojectile=cp
    else
        e.OnLoad=NativeBomb.OnLoad
        e._growtask=Schedule(e,NativeBombDurations.land,NativeBomb.Grow,1)
    end
    if PrefabHooks and PrefabHooks[name] then PrefabHooks[name](e) end
    return e
end
'''


def to_python(value):
    if hasattr(value, "items"):
        items = dict(value.items())
        if not items:
            return []
        if all(isinstance(k, int) for k in items):
            return [to_python(items[i]) for i in range(1, len(items) + 1)]
        return {k: to_python(v) for k, v in items.items()}
    return value


def runtime(hooked):
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + vm.globals().package.path
    vm.execute(INIT)
    vm.globals().NativeBombDurations=vm.table_from(mushroom_durations)
    common = sources['scripts/stategraphs/commonstates.lua']
    start = common.index('CommonHandlers.OnNoSleepAnimOver = function(')
    end = common.index('CommonHandlers.OnNoSleepAnimQueueOver = function(', start)
    vm.execute(common[start:end], name='@scripts/stategraphs/commonstates.lua')
    vm.globals().NativeGround = vm.execute(sources[paths[0]], name="@" + paths[0])
    vm.globals().NativeCombat = vm.execute(sources[paths[1]], name="@" + paths[1])
    vm.execute("NativeGraphs={}")
    for prefab in GRAPH_NAMES:
        path = f"scripts/stategraphs/SG{prefab}.lua"
        vm.globals().NativeGraphs[prefab] = vm.execute(sources[path], name="@" + path)
    vm.execute("NativeGraphs.toadstool_dark=NativeGraphs.toadstool;NativeGraphs.twinofterror1=NativeGraphs.eyeofterror;NativeGraphs.twinofterror2=NativeGraphs.eyeofterror")
    # Execute the exact native OnHitOther for freezing/temperature side effects.
    src = sources["scripts/prefabs/deerclops.lua"]
    block = src[src.index("local function OnHitOther("):src.index("local function OnRemove(")]
    vm.globals().NativeDeerOnHit = vm.execute(block + "\nreturn OnHitOther", name="@scripts/prefabs/deerclops.lua")
    toad = sources["scripts/prefabs/toadstool.lua"]
    block = toad[toad.index("local function SpawnMushroomBombProjectile("):toad.index("local function FindMushroomSproutAngles(")]
    vm.globals().NativeToadBomb = vm.execute('''
        local easing={linear=function(t,b,c,d) return c*t/d+b end}
        local function FindMushroomBombTargets() return {{x=3,z=0},{x=6,z=0}} end
        ''' + block + '\nreturn DoMushroomBomb', name='@scripts/prefabs/toadstool.lua')
    bomb = sources["scripts/prefabs/mushroombomb.lua"]
    block = bomb[bomb.index("local function Explode("):bomb.index("local function PlayGrowSound(")]
    block += bomb[bomb.index("local function Grow("):bomb.index("local function OnSave(")]
    block += bomb[bomb.index("local function OnLoad("):bomb.index("local function MakeBomb(")]
    vm.globals().NativeBomb = vm.execute('''
        local FADE_FRAMES=5
        local EXPLODETARGET_MUST_TAGS={'_health','_combat'}
        local EXPLODETARGET_CANT_TAGS={'INLIMBO','toadstool'}
        local FadeOut,CancelGrowSound,QueueGrowSound=noop,noop,noop
        ''' + block + '\nreturn {Grow=Grow,OnLoad=OnLoad}',name='@scripts/prefabs/mushroombomb.lua')
    block = bomb[bomb.index('    local function OnProjectileHit('):bomb.index('    local function fn()',bomb.index('    local function OnProjectileHit('))]
    for prefix,name in (("NativeBombHit","mushroombomb"),("NativeDarkBombHit","mushroombomb_dark")):
        vm.globals()[prefix] = vm.execute(f"local bombname='{name}'\n"+block+'\nreturn OnProjectileHit',name='@scripts/prefabs/mushroombomb.lua')
    vm.execute(BOMB_FIXTURE)
    vm.execute(FIXTURE)
    if hooked:
        vm.execute('''
        Boss=require('nw/dark_fog_boss')
        PrefabHooks={}
        Boss.install(function(name,fn) if name=='groundpounder' then HookGround=fn else assert(name=='combat');HookCombat=fn end end,
            function(name,fn) fn(NativeGraphs[name]) end,function(name,fn) PrefabHooks[name]=fn end)
        ''')
    return vm


checks = []
for prefab in PREFABS:
    for target in (False, True):
        modes = ("cast", "ordinary", "leave", "interrupt_before", "interrupt_after", "complete")
        if prefab in ("bearger", "moose"):
            modes += ("native_entry", "native_leave")
        if prefab in ("bearger", "toadstool", "toadstool_dark") or target and prefab in ("dragonfly", "minotaur"):
            modes += ("fallback", "fallback_native")
        if prefab in ("toadstool","toadstool_dark"):
            modes += ("fallback_interrupt_before", "fallback_interrupt_after")
        for mode in modes:
            baseline = to_python(runtime(False).globals().RunScenario(prefab, target, mode))
            hooked = to_python(runtime(True).globals().RunScenario(prefab, target, mode))
            assert baseline["dispatch"] == hooked["dispatch"], (prefab, target, mode, "damage changed")
            assert baseline["targets"] == hooked["targets"], (prefab, target, mode, "native effects changed")
            assert baseline.get("can_disarm") == hooked.get("can_disarm"), (prefab, target, mode, "native disarm availability changed")
            notices = hooked["notices"]
            if mode in ("ordinary", "interrupt_before", "fallback_interrupt_before"):
                assert not notices, (prefab, mode, "false fog hit")
            else:
                assert notices, (prefab, mode, "missing fog hit")
                # Native DoSpawnIceSpike executes immediately when hitdelay <
                # one frame; its first impact can therefore precede frame 34.
                earliest = {"deerclops":33,"bearger":20,"dragonfly":2,"toadstool":36,"toadstool_dark":36,
                            "minotaur":58,"alterguardian_phase1":8,"alterguardian_phase3":29,
                            "eyeofterror":25,"twinofterror1":25,"twinofterror2":25,"moose":15}[prefab] / 30
                if mode.startswith("fallback"):
                    earliest = {"bearger":32,"dragonfly":15,"minotaur":16,"toadstool":14,"toadstool_dark":14}[prefab] / 30
                assert min(n["time"] for n in notices) >= earliest - 1e-8
                if mode.startswith("fallback"):
                    if prefab == "bearger":
                        assert len(notices) == 2 and all(n["arc"] == 180 and n["x"] == 1 for n in notices)
                    elif prefab in ("toadstool","toadstool_dark"):
                        assert len(notices) == 2 and all(n["r"] == 3.5 for n in notices)
                        assert sorted(n["x"] for n in notices) == [3,6]
                    else:
                        assert len(notices) == 1 and notices[0]["x"] == 1 and notices[0]["r"] == .5
                elif prefab == "bearger":
                    assert [n["r"] for n in notices] == [2.5, 4.5, 6.5]
                    assert [n["inner"] for n in notices] == [0, 1.5, 3.5]
                if prefab == "dragonfly" and not mode.startswith("fallback"):
                    assert len(notices) == (2 if mode == "interrupt_after" else 6)
                if prefab == "moose":
                    assert len(notices) == 1 and notices[0]["r"] == 5.5 and not hooked["dispatch"]
                    assert hooked["targets"][0]["drops"] == 1 if target else not hooked["targets"]
            checks.append({"prefab": prefab, "targets": target, "mode": mode,
                           "native_damage_dispatches": len(hooked["dispatch"]), "fog_region_hits": len(notices)})

guard_checks = []
INSTALL = '''
Boss=require('nw/dark_fog_boss')
Boss.install(function(name,fn) if name=='groundpounder' then HookGround=fn else HookCombat=fn end end,
    function(name,fn) fn(NativeGraphs[name]) end)
'''
FIND_UPVALUE = '''
function FindUp(fn,wanted)
    for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then return end;if n==wanted then return v,i end end
end
function IceChain()
    for _,ev in ipairs(NativeGraphs.deerclops.states.attack.timeline) do
        local spawn=FindUp(ev.fn,'SpawnIceFx')
        if spawn then local spike=FindUp(spawn,'DoSpawnIceSpike');return spawn,spike,FindUp(spike,'DoIceSpikeAOE') end
    end
end
'''
for kind in ('debug_unavailable', 'ice_radius_changed', 'circle_missing', 'disarm_missing', 'missing_state'):
    vm = runtime(False)
    vm.execute(FIND_UPVALUE)
    vm.execute("WARNINGS={};print=function(s) WARNINGS[#WARNINGS+1]=s end")
    if kind == 'debug_unavailable':
        vm.execute('debug=nil')
        rejected = 'deerclops'
    elif kind == 'ice_radius_changed':
        vm.execute("local _,_,aoe=IceChain();local _,i=FindUp(aoe,'ICESPIKE_RADIUS');debug.setupvalue(aoe,i,2)")
        rejected = 'deerclops'
    elif kind == 'circle_missing':
        vm.execute('NativeGraphs.eyeofterror.states.chomp.timeline={}')
        rejected = 'eyeofterror'
    elif kind == 'disarm_missing':
        vm.execute('NativeGraphs.moose.states.disarm.timeline={}')
        rejected = 'moose'
    else:
        vm.execute('NativeGraphs.bearger.states.bi=nil')
        rejected = 'bearger'
    vm.execute(INSTALL)
    vm.execute(f"assert(not Boss.supports(MakeBoss('{rejected}',NativeGraphs['{rejected}'])));assert(#WARNINGS>0)")
    guard_checks.append(kind)

vm = runtime(False)
vm.execute(FIND_UPVALUE)
vm.execute('OriginalSpawn,OriginalSpike=IceChain()')
vm.execute(INSTALL)
vm.execute('''
local e=MakeBoss('deerclops',NativeGraphs.deerclops)
assert(Boss.update(e,0,true))
local scheduler=e.DoTaskInTime
e.DoTaskInTime=function() error('injected native scheduling error') end
local ok,err=pcall(Advance,31*FRAMES)
assert(not ok and string.find(err,'injected native scheduling error',1,true))
assert(FindUp(OriginalSpawn,'DoSpawnIceSpike')==OriginalSpike,'shared native closure was not restored on error')
e.DoTaskInTime=scheduler;e.sg:GoToState('test_interrupt')
assert(e._nw_fog_boss_cast==nil and e.restarts==1)
NOTICES={};QUEUE={};e.sg:GoToState('attack');Advance(NOW+3)
assert(#NOTICES==0,'ordinary follow-up inherited the failed cast token')
''')
guard_checks.append('ice_schedule_error_restores_shared_upvalue')

for prefab,timer in (("dragonfly","groundpound_cd"),("minotaur","stomptimer")):
    for miss in (False,True):
        vm=runtime(True)
        vm.execute(f'''
        local e=MakeBoss('{prefab}',NativeGraphs['{prefab}'])
        local target=MakeTarget(1,0);target.physicsradius=.5
        TARGETS={{target}};e.components.combat.target=target;e.timers['{timer}']=30
        e.zero_damage=true;e.miss={'true' if miss else 'false'}
        assert(Boss.update(e,0,true));Advance(1)
        assert(#NOTICES=={0 if miss else 1} and target.damage==0,
            'native contact, not positive damage or mere animation, decides fog clearing')
        ''')
        guard_checks.append(f"{prefab}_{'miss_no_clear' if miss else 'zero_damage_contact_clears'}")
    vm=runtime(True)
    vm.execute(f'''
    local e=MakeBoss('{prefab}',NativeGraphs['{prefab}']);e.timers['{timer}']=30
    assert(Boss.select(e)==nil,'single-target fallback cannot fabricate a target')
    e.components.combat.target=MakeTarget(1,0);e.cooldown=true
    assert(Boss.select(e)==nil,'ordinary attack cooldown is preserved')
    e.cooldown=false;e.components.combat.CanAttack=function() return false end
    assert(Boss.select(e)==nil,'native target/range rejection is preserved')
    ''')
    guard_checks.append(f"{prefab}_fallback_target_and_cooldown")

for failure in ("schedule","launch"):
    vm=runtime(True);vm.execute(FIND_UPVALUE)
    vm.execute(f'''
    local e=MakeBoss('toadstool',NativeGraphs.toadstool);e.timers.pound_cd=30
    local original=FindUp(NativeToadBomb,'SpawnMushroomBombProjectile')
    assert(Boss.update(e,0,true))
    local schedule,spawn=e.DoTaskInTime,SpawnPrefab
    if '{failure}'=='schedule' then e.DoTaskInTime=function() error('injected mushroom error') end
    else SpawnPrefab=function(name,...) if name=='mushroombomb_projectile' then error('injected mushroom error') end;return spawn(name,...) end end
    local ok,err=pcall(Advance,.7)
    assert(not ok and string.find(err,'injected mushroom error',1,true))
    assert(FindUp(NativeToadBomb,'SpawnMushroomBombProjectile')==original,'mushroom shared callback was not restored')
    e.DoTaskInTime=schedule;SpawnPrefab=spawn;e.fog_inside=false;e.sg:GoToState('test_interrupt')
    QUEUE={{}};NOTICES={{}};e.DoMushroomBomb(e);Advance(NOW+6)
    assert(#NOTICES==0,'ordinary mushroom launch inherited a failed fog token')
    ''')
    guard_checks.append(f"mushroom_{failure}_error_restores_scope")

# Native attacks dispatched outside fog may hit only after entry. Their
# verified delayed batch must work after the source SG has already exited.
vm=runtime(True)
vm.execute(r'''
local e=MakeBoss('bearger',NativeGraphs.bearger);e.fog_inside=false
 e.sg:GoToState('pound');Advance(20*FRAMES+.001)
assert(#NOTICES==0,'outside first ring must not clear fog')
e.fog_inside=true;e.sg:GoToState('test_interrupt')
Advance(20*FRAMES+e.components.groundpounder.ringDelay+.001)
assert(#NOTICES==1,'late entry must activate the actual delayed ring')
e.fog_inside=false;Advance(3)
assert(#NOTICES==2,'activated delayed batch retains its final ring after exit')
''')
guard_checks.append('bearger_late_coverage_after_native_dispatch')
vm=runtime(True)
vm.execute(r'''
local e=MakeBoss('deerclops',NativeGraphs.deerclops);e.fog_inside=false
 e.sg:GoToState('attack');Advance(31*FRAMES+.001)
assert(#NOTICES==0,'outside ice dispatch must not clear fog')
e.fog_inside=true;e.sg:GoToState('test_interrupt')
Advance(3)
assert(#NOTICES>0,'late coverage must activate original scheduled ice impacts')
''')
guard_checks.append('deerclops_late_coverage_after_native_dispatch')
for prefab in ('eyeofterror','twinofterror1','twinofterror2'):
    vm=runtime(True)
    vm.execute(f'''
    local e=MakeBoss('{prefab}',NativeGraphs.eyeofterror)
    e.sg.mem.transformed=false
    assert(not Boss.select(e),'hidden mouth phase must never force chomp')
    e.sg.mem.transformed=true
    assert(Boss.select(e).first=='chomp','native transformed phase may chomp')
    ''')
    guard_checks.append(prefab+'_native_transform_gate')

# Preserve the entire native recovery, even after attack/busy disappear.
for prefab, state, until in (("deerclops", "attack", 57), ("eyeofterror", "chomp", 62)):
    vm=runtime(True)
    vm.execute(f'''
    local e=MakeBoss('{prefab}',NativeGraphs['{prefab}']);e.fog_inside=false
    e.sg:GoToState('{state}');Advance({until}*FRAMES)
    assert(not e.sg:HasStateTag('busy') and not e.sg:HasStateTag('attack'))
    e.fog_inside=true
    assert(not Boss.update(e,NOW,true) and e.stops==0 and e.sg.currentstate.name=='{state}',
        'do not interrupt native recovery after tags clear')
    e.sg.sg.states.idle={{name='idle',tags={{idle=true}}}}
    e:AnimOver()
    if '{prefab}'=='eyeofterror' then
        assert(e.sg.currentstate.name=='taunt' and not Boss.update(e,NOW,true),
            'chomp must also finish its native taunt before fog takeover')
        e:AnimOver()
    end
    assert(e.sg.currentstate.name=='idle' and Boss.update(e,NOW,true),
        'fog must acquire the boss on the first scan after full recovery')
    assert(e._brainstopped.nw_fog_boss and e._nw_fog_boss_cast)
    ''')
    guard_checks.append(f"{prefab}_untagged_attack_recovery_and_takeover")
vm=runtime(True)
vm.execute(r'''
local e=MakeBoss('minotaur',NativeGraphs.minotaur);e.fog_inside=true
for _,name in ipairs({'run_start','run','run_stop'}) do
    e.sg.currentstate=assert(NativeGraphs.minotaur.states[name])
    assert(not Boss.update(e,0,true) and e.stops==0,'native charge must finish before fog takeover')
end
''')
guard_checks.append("minotaur_entire_charge_chain")

# Execute the real honk/drop callback with targets at, beyond, and moving
# across the native combat range. Only fog-triggered honks gain the guard.
for distance, escape, covered in ((1, False, True), (10, False, True), (11, False, True),
                                  (100, False, True), (1, True, True), (100, False, False)):
    vm=runtime(True)
    vm.globals().RangeDistance=distance;vm.globals().RangeEscape=escape;vm.globals().RangeCovered=covered
    vm.execute(r'''
    NOW=0;NOTICES={};QUEUE={};TARGETS={MakeTarget(RangeDistance,0)}
    local e=MakeBoss('moose',NativeGraphs.moose);e.fog_inside=RangeCovered
    e.components.combat.target=TARGETS[1];e.CanDisarm=true
    if RangeCovered then assert(Boss.update(e,0,true)) else e.sg:GoToState('disarm') end
    if RangeEscape then TARGETS[1].x=11 end
    Advance(.6)
    local expected=(not RangeCovered or not RangeEscape and RangeDistance<=10) and 1 or 0
    assert(TARGETS[1].drops==expected,'honk disarm escaped native combat range')
    assert(e.CanDisarm==false,'empty honk still consumes native disarm availability')
    assert(#NOTICES==(RangeCovered and 1 or 0),'out-of-range honk still disperses nearby fog')
    ''')
    guard_checks.append(f"moose_range_{distance}_escape_{escape}_covered_{covered}")

report = {"passed": True, "archive": str(archive), "runtime": "Lua 5.1 (lupa)", "cases": checks,
          "mushroom_animation_sha256":hashlib.sha256(mushroom_anim).hexdigest(),"mushroom_animation_durations":mushroom_durations,
          "guard_checks": guard_checks,
          "sources": {p: hashlib.sha256(s.encode()).hexdigest() for p, s in sources.items()},
          "verified": "Native SG timing/completion, brain release, covered native-entry adoption, cooldown fallbacks, exact bear arc callbacks, native combat zero-damage contact/miss, mushroom launch/landing/grow/explosion provenance and error restoration, ice/disarm guards, native damage/effects unchanged, no uncovered ordinary attack clearing",
          "not_verified": "Live DST renderer, replication, native engine physics, animation timing delivery, other mods"}
dest = ROOT / "test_reports/dark_fog_boss_native.json"
dest.parent.mkdir(exist_ok=True)
dest.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"PASS {len(checks)} native/baseline comparison cases + {len(guard_checks)} guards; {dest}")
