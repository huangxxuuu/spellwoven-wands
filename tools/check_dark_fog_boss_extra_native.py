"""Execute the new boss SGs from scripts.zip; compare native and fog-marked runs.

Reuses the existing engine double, without executing its separate 176-case suite.
This is native Lua coverage, not a replacement for dedicated-server physics.
"""
import ast
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
base = ast.parse((ROOT / 'tools/check_dark_fog_boss_native.py').read_text(encoding='utf-8'))
fixtures = {node.targets[0].id: ast.literal_eval(node.value) for node in base.body
            if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id in ('INIT', 'FIXTURE')}
parser=argparse.ArgumentParser()
parser.add_argument('--game',type=Path,default=Path("E:/SteamLibrary/steamapps/common/Don't Starve Together"))
args=parser.parse_args()
archive = args.game/'data/databundles/scripts.zip'
graphs = ('spat','beequeen','klaus','Leif','spiderqueen','warg','deerclops','bearger','daywalker2','alterguardian_phase4_lunarrift')
paths = [f'scripts/stategraphs/SG{name}.lua' for name in graphs] + [
    'scripts/components/combat.lua','scripts/components/groundpounder.lua','scripts/stategraphs/commonstates.lua',
    'scripts/prefabs/alterguardian_lunar_fissures.lua']
with zipfile.ZipFile(archive) as bundle:
    sources = {name:bundle.read(name).decode('utf-8') for name in paths}

SUPPORT = r'''
RADIANS=180/math.pi
function math.clamp(v,a,b) return math.max(a,math.min(b,v)) end
function ReduceAngle(a) return (a+180)%360-180 end
function GetRandomItem(t) return t[1] end
function distsq(x,z,a,b) return (x-a)^2+(z-b)^2 end
function GetClosestInstWithTag() end
local base_spawn=SpawnPrefab
function SpawnPrefab(name)
    if name=='deerclops_icespike_fx' then return base_spawn(name) end
    return {prefab=name,Transform=setmetatable({},{__index=function() return noop end}),AnimState=setmetatable({},{__index=function() return noop end}),
        entity={SetParent=noop},SetOwner=noop,Remove=noop,ListenForEvent=noop,DoTaskInTime=Schedule,
        SetAnim=noop,SetScale=noop,SetFXOwner=noop,RestartFX=noop,KillFX=noop,Reverse=noop,Kill=noop,IsValid=function() return true end}
end
package.preload['stategraphs/SGdaywalker_common']=function() return setmetatable({}, {__index=function() return noop end}) end
package.preload['prefabs/wagboss_util']=function() return {DespawnFissure=noop} end
package.preload.easing=function() return {inQuad=function(t,b,c,d) return c*(t/d)^2+b end} end
TheWorld.Map.IsPointInWagPunkArena=function() return false end
TheSim.RegisterFindTags=function() return 1 end
TheSim.FindEntities_Registered=function(self,x,y,z,r) return self:FindEntities(x,y,z,r) end
function TossLaunch() end
function LaunchAt() end
function ToggleOffCharacterCollisions() end
function ToggleOnCharacterCollisions() end
function DeactivateInventoryItemBeforeLaunch() end
package.loaded['nw/dark_fog'].disperse_arc=function(_,x,z,r,rotation,arc)
    NOTICES[#NOTICES+1]={x=x,z=z,r=r,rotation=rotation,arc=arc,kind='arc'}
end
package.loaded['nw/dark_fog'].disperse_box=function(_,x,z,w,h)
    NOTICES[#NOTICES+1]={x=x,z=z,w=w,h=h,kind='box'}
end
'''

SCENARIO = r'''
function ExtraBoss(prefab)
    local graphname=({leif='Leif',leif_sparse='Leif',mutatedwarg='warg',mutatedbearger='bearger',mutateddeerclops='deerclops'})[prefab] or prefab
    local e=MakeBoss(prefab,NativeGraphs[graphname]);e.fog_inside=true
    e.Physics=setmetatable(e.Physics,{__index=function() return noop end})
    e.SoundEmitter.PlayingSound=function() return false end
    e.ForceFacePoint=noop;e.GetPhysicsRadius=function() return 1 end
    e.GetDistanceSqToPoint=function(_,x,y,z) return x*x+z*z end
    e.GetAngleToPoint=function(_,x,y,z) if type(x)=='table' then z=x.z;x=x.x end;return -math.atan2(z,x)*RADIANS end
    e.IsNear=function(_,target,r) return target:GetDistanceSqToPoint(0,0,0)<=r*r end
    e.components.combat.TargetIs=function(c,t) return c.target==t end
    e.components.combat.GetHitRange=function() return 8 end
    e.components.combat.battlecryenabled=false
    e.components.health.SetMinHealth=noop;e.components.health.currenthealth=100
    e.sg.SetTimeout=noop;e.AnimState.GetCurrentAnimationLength=function() return .4 end
    e.SetStalking=noop;e.StartAttackCooldown=noop;e.components.stuckdetection={Reset=noop}
    e.DoFoleySounds=noop;e.DoSwipeSound=noop;e.PerformBufferedAction=noop
    function e:RemoveEventCallback(n,fn) if self.events[n]==fn then self.events[n]=nil end end
    function e:DoPeriodicTask(_,fn) self.waittask={fn=fn,Cancel=function(t) t.cancelled=true end};return self.waittask end
    e.OnItemUsed=function() e.used=(e.used or 0)+1;return true end;e.DropItem=function() error('unexpected equipment drop') end
    e.canswing=true;e.hostile=true;e.slamcombo=1;e.dashcombo=1;e.dashcount=0;e.slamcount=0
    e.StartDashFx=noop;e.StopDashFx=noop;e.StartButtRecovery=noop;e.IsButtRecovering=function() return true end
    e.components.talker={Chatter=noop};e.chatter={}
    e.sounds.attack='attack';e.sounds.step='step';e.sounds.idle='idle'
    if prefab=='spat' then
        local equipped=false
        local weapon={IsValid=function() return true end,components={weapon={attackrange=.5},
            equippable={IsEquipped=function() return equipped end}}}
        e.weaponitems={meleeweapon=weapon};e.components.combat.attackrange=3
        e.components.inventory={Equip=function(_,w) assert(w==weapon);equipped=true end}
        e.components.combat.GetWeapon=function() return equipped and weapon or nil end
    end
    if prefab=='mutatedbearger' then e.cancombo=true;e.canbutt=true end
    if prefab=='mutateddeerclops' then e.hasiceaura=true;e.hasknockback=true;e.hasicelance=true;e.hasfrenzy=true end
    return e
end
function RunExtra(prefab,mode,variant)
    math.randomseed(431);NOW=0;QUEUE={};NOTICES={};TARGETS={};DISPATCH={};FX={}
    local e=ExtraBoss(prefab)
    local target=MakeTarget(1.5,0);target.physicsradius=.5
    target.components.inventory.ArmorHasTag=function() return false end
    TARGETS={target};e.components.combat.target=target
    if variant=='fallback' then e.timers.GroundPound=30 end
    if variant=='dash' then e.slamcombo=nil end
    local first=({daywalker2='attack_swing',alterguardian_phase4_lunarrift=variant=='dash' and 'dash_pre' or 'slam',mutatedbearger=variant=='fallback' and 'attack' or 'pound'})[prefab] or 'attack'
    e.fog_inside=mode~='ordinary'
    if Boss then assert(Boss.supports(e),prefab..' unsupported') end
    if Boss and mode~='ordinary' and mode~='native' then assert(Boss.update(e,0,true),prefab..' no selection')
    else e.sg:GoToState(first,target) end
    if Boss and mode=='native' then assert(e._nw_fog_boss_cast and e.stops==0,'native adoption') end
    if mode=='interrupt' then Advance(.01);e.sg:GoToState('test_interrupt') end
    if mode=='leave' then e.fog_inside=false;if Boss then Boss.leave(e) end end
    if variant=='dash' and mode~='interrupt' then
        Advance(2.11);e:AnimOver()
        for n=1,2 do e.sg.currentstate.onupdate(e);e.sg.currentstate.ontimeout(e) end
        e.sg.currentstate.onupdate(e,FRAMES)
    end
    Advance(variant=='fallback' and 5.1 or 4.5)
    if mode=='interrupt_four' then e.sg:GoToState('test_interrupt') end
    if mode~='interrupt' and mode~='interrupt_four' then
        e.sg.sg.states.idle={name='idle',tags={idle=true}}
        e:AnimOver((e.prefab=='spat' or e.prefab=='mutatedbearger' and variant=='fallback') and 'animqueueover' or 'animover')
        if e.sg.currentstate.name=='attack_swing_pst' then Advance(NOW+.4);e:AnimOver() end
    end
    if Boss then assert(not e._nw_fog_boss_cast,'token leaked '..e.sg.currentstate.name) end
    return {notices=NOTICES,dispatch=DISPATCH,used=e.used or 0,hits=target.hits,work=target.work,stops=e.stops,restarts=e.restarts}
end
'''

def runtime(hooked):
    vm=LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path=(ROOT/'mod/scripts/?.lua').as_posix()+';'+vm.globals().package.path
    vm.execute(fixtures['INIT']);vm.execute(SUPPORT)
    common=sources['scripts/stategraphs/commonstates.lua']
    start=common.index('CommonHandlers.OnNoSleepAnimOver = function(')
    end=common.index('CommonHandlers.OnNoSleepAnimQueueOver = function(',start)
    vm.execute(common[start:end],name='@scripts/stategraphs/commonstates.lua')
    for key,name in [('NativeGround','groundpounder'),('NativeCombat','combat')]:
        path=f'scripts/components/{name}.lua';vm.globals()[key]=vm.execute(sources[path],name='@'+path)
    vm.execute('NativeGraphs={}')
    for graph in graphs:
        path=f'scripts/stategraphs/SG{graph}.lua'
        vm.globals().NativeGraphs[graph]=vm.execute(sources[path],name='@'+path)
    fixture=fixtures['FIXTURE'].replace("elseif prefab=='dragonfly' or prefab=='minotaur' then",
        "elseif prefab=='dragonfly' or prefab=='minotaur' or prefab=='beequeen' or prefab=='klaus' or prefab=='warg' or prefab=='mutatedwarg' or prefab=='leif' or prefab=='leif_sparse' or prefab=='spiderqueen' then")
    vm.execute(fixture);vm.execute(SCENARIO)
    if hooked:
        vm.execute('''Boss=require('nw/dark_fog_boss');PrefabHooks={}
        Boss.install(function(name,fn) if name=='groundpounder' then HookGround=fn else HookCombat=fn end end,
        function(name,fn)
            for _,graph in pairs(NativeGraphs) do
                if graph.name==name then fn(graph) end
            end
        end,
        function(name,fn) PrefabHooks[name]=fn end)''')
        vm.execute("assert(NativeGraphs.Leif.name=='leif');assert(Boss.supports(ExtraBoss('leif')) and Boss.supports(ExtraBoss('leif_sparse')),'native graph-name PostInit dispatch failed')")
    return vm

def plain(value):
    if hasattr(value,'items'):
        data={k:plain(v) for k,v in value.items()}
        return [data[k] for k in range(1,len(data)+1)] if data and set(data)==set(range(1,len(data)+1)) else data
    return value

def check_fissures():
    vm=runtime(True)
    source=sources['scripts/prefabs/alterguardian_lunar_fissures.lua']
    block=source[source.index('local REGISTERED_AOE_TAGS'):source.index('local function fn()')]
    vm.execute('NativeFissure=(function() local easing=require("easing"); local WagBossUtil=require("prefabs/wagboss_util")\n'+block+
               '\nreturn {OnLoad=OnLoad,OnSave=OnSave,StartTrackingBoss=StartTrackingBoss,Activate=OnAnimOver,Kill=KillMe} end)()',
               name='@scripts/prefabs/alterguardian_lunar_fissures.lua')
    vm.execute(r'''
    FISSURES={}
    function NewFissure(x,z)
        local entities={}
        local e={pre=true,variation=1,components={entitytracker={GetEntity=function(_,k) return entities[k] end,
            TrackEntity=function(_,k,v) entities[k]=v end,ForgetEntity=function(_,k) entities[k]=nil end}},
            Transform={GetWorldPosition=function() return x,0,z end},AnimState=setmetatable({},{__index=function() return noop end}),
            OnLoad=NativeFissure.OnLoad,StartTrackingBoss=NativeFissure.StartTrackingBoss,
            _onremoveboss=noop,ListenForEvent=noop,RemoveEventCallback=noop,IsValid=function() return true end}
        function e:IsAsleep() return self.asleep end
        function e:Remove() self.removed=true end
        function e:DoPeriodicTask(_,fn) self.tick=fn;return {Cancel=noop} end
        PrefabHooks.alterguardian_lunar_fissures(e)
        FISSURES[#FISSURES+1]=e
        return e
    end
    local util=require('prefabs/wagboss_util')
    util.TileCoordsToId=function(x,z) return x..','..z end
    util.IdToTileCoords=function(id) local x,z=string.match(id,'([^,]+),([^,]+)');return tonumber(x),tonumber(z) end
    util.HasFissure=function() return false end
    util.SpawnFissureAtXZ=function(x,z) return NewFissure(x,z) end
    TheWorld.Map.IsPointInWagPunkArena=function(_,x,y,z) return x>=-4 and x<=8 and z>=-4 and z<=4 end
    TheWorld.Map.GetTileCoordsAtPoint=function(_,x,y,z) return math.floor(x/4+.5),math.floor(z/4+.5) end
    TheWorld.Map.GetTileCenterPoint=function(_,x,y,z)
        if z then return math.floor(x/4+.5)*4,0,math.floor(z/4+.5)*4 end
        return x*4,0,y*4
    end
    bit={band=function(a,b) return a%2 end}
    local boss=ExtraBoss('alterguardian_phase4_lunarrift')
    boss._temptbl1={};assert(Boss.update(boss,0,true))
    -- Execute the original 59-frame DoFissures closure, which creates and tracks
    -- actual native-shaped fissures before their activation animations finish.
    Advance(60*FRAMES)
    assert(#FISSURES>0)
    for _,f in ipairs(FISSURES) do assert(f._nw_fog_boss_fissure_token==boss._nw_fog_boss_cast) end
    NOTICES={};boss.fog_inside=false;Boss.leave(boss)
    local f1,f2=FISSURES[1],FISSURES[2]
    assert(#NOTICES==0,'fissure creation is not damage activation')
    NativeFissure.Activate(f1)
    assert(#NOTICES==1 and NOTICES[1].kind=='box' and NOTICES[1].w==2 and NOTICES[1].h==2)
    f1.tick(f1);assert(#NOTICES==2,'shared periodic OnUpdate must retain provenance')
    f2.asleep=true;NativeFissure.Activate(f2);assert(#NOTICES==2,'sleeping fissure must not clear early')
    f2.asleep=false;f2.OnEntityWake(f2);f2.tick(f2);assert(#NOTICES==3,'second instance must retain native hook')
    local saved={};NativeFissure.OnSave(f1,saved);assert(saved._nw_fog_boss_fissure_token==nil)
    -- The original SG exit removes not-yet-committed fissures, not our hook.
    boss.sg:GoToState('test_interrupt')
    for _,f in ipairs(FISSURES) do assert(f.removed) end
    local ordinary=NewFissure(4,0);ordinary:StartTrackingBoss(boss)
    assert(not ordinary._nw_fog_boss_fissure_token)
    NativeFissure.Activate(ordinary);assert(#NOTICES==3,'unmarked/native later fissure never inherits a cast')
    ''')
    return 1

checks=[]
cases=[(p,'primary') for p in ('spat','beequeen','klaus','alterguardian_phase4_lunarrift','daywalker2','mutateddeerclops','mutatedbearger','mutatedwarg','leif','leif_sparse','spiderqueen','warg')]
cases += [('mutatedbearger','fallback'),('alterguardian_phase4_lunarrift','dash')]
for prefab,variant in cases:
    for mode in (('cast','ordinary','interrupt','leave','native','interrupt_four') if variant=='fallback' else ('cast','ordinary','interrupt','leave','native')):
        baseline=plain(runtime(False).globals().RunExtra(prefab,mode,variant))
        result=plain(runtime(True).globals().RunExtra(prefab,mode,variant))
        for key in ('dispatch','used','hits','work'):
            assert result[key]==baseline[key],(prefab,variant,mode,key,baseline,result)
        assert bool(result['notices'])==(mode not in ('ordinary','interrupt')),(prefab,variant,mode,result)
        if variant=='fallback' and mode not in ('ordinary','interrupt'):
            assert len(result['notices'])>=8,('four original combo swings must keep token',mode,result)
        checks.append({'prefab':prefab,'variant':variant,'mode':mode,'notices':len(result['notices'])})

fissure_checks=check_fissures()
vm=runtime(True)
vm.execute(r'''
for _,change in ipairs({'target','equipment','buried','defeated','hostile'}) do
    NOW=0
    local e=ExtraBoss('daywalker2');e.cooldown=true;e.components.combat.target=MakeTarget(1,0)
    assert(not Boss.update(e,0,true) and e._nw_fog_boss_wait)
    if change=='target' then e.components.combat.target=nil
    elseif change=='equipment' then e.canswing=false
    elseif change=='hostile' then e.hostile=false
    else e[change]=true end
    NOW=.1;e.waittask.fn()
    if change=='target' or change=='equipment' then
        assert(e._nw_fog_boss_wait and e._brainstopped,'no usable attack must keep covered panic')
        e.fog_inside=false;Boss.leave(e)
    end
    assert(not e._nw_fog_boss_wait and not e._brainstopped and e.waittask.cancelled,change..' cleanup must release waiting brain')
end
''')
# A distant target must no longer keep warg running through fog unchecked.
vm=runtime(True)
vm.execute(r'''
for _,prefab in ipairs({'warg','mutatedwarg'}) do
    NOW=0
    local e=ExtraBoss(prefab);e.components.combat.target=MakeTarget(100,0)
    e.sg.currentstate={name='run',tags={moving=true,running=true}}
    local dest={};e.components.locomotor.dest=dest
    e.components.locomotor.Stop=function(c)
        assert(e._brainstopped,'must own brain before stopping chase')
        c.dest=nil
    end
    assert(not Boss.update(e,0,true) and e._nw_fog_boss_wait and e.components.locomotor.dest==nil)
    NOW=.2;e.waittask.fn();assert(e._nw_fog_boss_wait,'distant target must keep covered waiting')
    e.components.combat.target=MakeTarget(1,0)
    NOW=.3;e.waittask.fn()
    assert(e._nw_fog_boss_cast and e._nw_fog_boss_wait and e.sg.currentstate.name=='attack')
    assert(e._brainstopped and e._brainstopped.nw_fog_boss and e._brainstopped.nw_fog_boss_wait,
        'waiting must hold pursuit while the native attack owns its cast reason')
    e.fog_inside=false;Boss.leave(e)
    assert(e._brainstopped.nw_fog_boss and not e._brainstopped.nw_fog_boss_wait)
    e.sg.sg.states.idle={name='idle',tags={idle=true}};e.sg:GoToState('idle')
    assert(not e._brainstopped,'completed attack releases only our reasons')
end
''')
report={'passed':True,'cases':checks,'fissure_chain_checks':fissure_checks,'waiting_invalidated_checks':5,'pursuit_target_checks':2,
        'sources':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in sources.items()}}
destination=ROOT/'test_reports/dark_fog_boss_extra_native.json'
destination.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'PASS {len(checks)} added native/baseline cases + fissure lifecycle; {destination}')
