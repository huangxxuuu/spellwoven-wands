local Wait=require("nw/dark_fog_boss_wait")
local time,paths=0,{}
GetTime=function() return time end
math.random=function() return .5 end
TheWorld={ismastersim=true}
FindWalkableOffset=function() return {x=1,z=0},0 end
FindSwimmableOffset=FindWalkableOffset
local current
package.loaded["nw/dark_fog"]={contains=function(_,e) return e.inside end,
    disperse_path=function(_,ax,az,bx,bz,r)
        paths[#paths+1]={ax,az,bx,bz,r}
        current.inside=false;Wait.leave(current)
    end}
local function entity()
    local e={x=0,z=0,inside=true,events={},listeners={},tasks={},components={},walks=0,restarts=0}
    function e:IsValid() return not self.removed end
    function e:IsInLimbo() return false end
    function e:IsAsleep() return self.sleeping end
    function e:GetPosition() return {x=self.x,y=0,z=self.z} end
    function e:GetPhysicsRadius() return 1.5 end
    function e:ListenForEvent(event,fn)
        self.listeners[event]=self.listeners[event] or {};self.listeners[event][fn]=true
        self.events[event]=function() local copy={};for f in pairs(self.listeners[event] or {}) do copy[#copy+1]=f end;for _,f in ipairs(copy) do f() end end
    end
    function e:RemoveEventCallback(event,fn)
        local list=self.listeners[event];if list then list[fn]=nil;if not next(list) then self.events[event]=nil end end
    end
    function e:StopBrain(reason) self._brainstopped=self._brainstopped or {};self._brainstopped[reason]=true end
    function e:RestartBrain(reason)
        self._brainstopped[reason]=nil
        if next(self._brainstopped)==nil then self._brainstopped=nil;self.restarts=self.restarts+1 end
    end
    function e:DoPeriodicTask(interval,fn)
        assert(interval==.1);local task={fn=fn,Cancel=function(t) t.cancelled=true end}
        self.tasks[#self.tasks+1]=task;self.task=self.task or task;return task
    end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end}
    e.components.health={IsDead=function() return e.dead end}
    e.components.locomotor={Stop=function() e.stopped=true end,GetWalkSpeed=function() return 6 end,
        WalkInDirection=function() e.walks=e.walks+1 end}
    e.sg={currentstate={name="idle"},HasStateTag=function(_,tag) return e.tags and e.tags[tag] end}
    time=0;current=e;return e
end
local function tick(e,t,x)
    time=t;if x then e.x=x end
    local count=#e.tasks
    for i=1,count do if not e.tasks[i].cancelled then e.tasks[i].fn() end end
end
local function no_move() return false end
local e=entity();assert(Wait.start(e,0,no_move) and e.walks==1 and e._brainstopped[Wait.reason])
tick(e,.7,1);assert(#paths==0 and e._nw_fog_boss_wait)
tick(e,1.1,2);assert(#paths==0,"no body clearing before two seconds")
tick(e,2.1,3)
assert(#paths==1 and paths[1][1]==2 and paths[1][3]==3 and paths[1][5]==1.5,
    "body sweep starts after two seconds without replaying earlier movement")
assert(not e._nw_fog_boss_wait and not e.inside and e.restarts==1 and e.task.cancelled,
    "coverage loss immediately releases panic")
assert(e._nw_fog_boss_body,"first clearing must not cancel its independent body window")
tick(e,2.6,4);assert(#paths==2 and paths[2][1]==3 and paths[2][3]==4,"leaving still sweeps later actual movement")
tick(e,4.5,5);assert(#paths==3 and e._nw_fog_boss_body)
tick(e,4.6,6);assert(#paths==3 and not e._nw_fog_boss_body,"body clearing ends 2.5 seconds after activation")
assert(next(e.events)==nil,"all temporary callbacks are released after both lifetimes")

e=entity();local ready=false
assert(Wait.start(e,0,function(inst)
    if ready then inst:StopBrain("cast");Wait.stop(inst);return true end
end))
ready=true;tick(e,.4,1)
assert(not e._nw_fog_boss_wait and e._brainstopped.cast and not e._brainstopped[Wait.reason] and e.restarts==0,
    "ready skill takes ownership before releasing waiting brain reason")

e=entity();Wait.start(e,0,no_move);e.inside=false;Wait.leave(e)
assert(not e._nw_fog_boss_wait and e.restarts==1)
e=entity();Wait.start(e,0,no_move);tick(e,1.8)
assert(e._nw_fog_boss_wait,"ordinary panic remains coverage driven")
e.inside=false;Wait.leave(e);assert(not e._nw_fog_boss_wait)
e.inside=true;assert(Wait.start(e,3.3,no_move),"reentry may start waiting again");Wait.stop(e)

e=entity();Wait.start(e,0,no_move);local count=#paths;tick(e,2.1,100)
assert(#paths==count+1 and paths[#paths][1]==100 and paths[#paths][3]==100,"teleport never sweeps intervening world")
Wait.stop(e)
for _,event in ipairs({"entitysleep","death","onremove"}) do
    e=entity();Wait.start(e,0,no_move)
    if event=="death" then e.dead=true elseif event=="onremove" then e.removed=true end
    e.events[event]()
    assert(not e._nw_fog_boss_wait and e.task.cancelled and not e._brainstopped)
    assert(e.restarts==(event=="entitysleep" and 1 or 0),"death/removal never reinsert brains")
end
e=entity();Wait.start(e,0,no_move);e:StopBrain("other_mod");local walks=e.walks;tick(e,.2,1)
assert(not e._nw_fog_boss_wait and e._brainstopped.other_mod and e.restarts==0 and e.walks==walks)
-- A new non-combat action belongs to the external caller, not panic movement.
e=entity();Wait.start(e,0,no_move);e.stopped=false
local action={};e.bufferedaction=action;local walks=e.walks;tick(e,.6)
assert(not e._nw_fog_boss_wait and e.bufferedaction==action and e.walks==walks and not e.stopped)
-- Locomotor keeps travel actions separately until arriving at the target.
e=entity();Wait.start(e,0,no_move);e.stopped=false
local travel={};e.components.locomotor.bufferedaction=travel;local walks=e.walks;tick(e,.6)
assert(not e._nw_fog_boss_wait and e.components.locomotor.bufferedaction==travel
    and e.walks==walks and not e.stopped,"preserve an external locomotor travel action")
-- Fully committed native actions remain protected even after their tags
-- disappear, including an idle-tagged minotaur charge recovery.
for _,name in ipairs({"attack","chomp","run_stop","hit","talk"}) do
    e=entity();e.prefab="minotaur";Wait.start(e,0,no_move)
    e.sg.currentstate.name=name;e.tags={idle=true};e.stopped=false
    local walks=e.walks;tick(e,.6)
    assert(e.walks==walks,"panic must not interrupt attack/recovery: "..name)
    Wait.leave(e);assert(not e.stopped,"leaving fog must not stop attack/recovery: "..name)
end
FindWalkableOffset=function() return nil end
for _,field in ipairs({"buried","defeated","hostile"}) do
    e=entity();e.prefab="daywalker2";e.hostile=true;Wait.start(e,0,no_move)
    e[field]=field~="hostile";tick(e,.2)
    assert(not e._nw_fog_boss_wait and not e._brainstopped,"phase change releases waiting: "..field)
end
e=entity();Wait.start(e,0,no_move);assert(e.walks==0,"failed navigation never falls back to unsafe movement");Wait.stop(e)
-- Time spent in a committed external/native attack is not panic time.
e=entity();Wait.start(e,0,no_move);tick(e,1,1)
e.sg.currentstate.name="attack";e.tags={busy=true};e._nw_fog_boss_cast={}
tick(e,4,2);assert(not e._nw_fog_boss_body)
e._nw_fog_boss_cast=nil;e.tags=nil;e.sg.currentstate.name="idle"
tick(e,4.1,3);tick(e,6,4);assert(not e._nw_fog_boss_body)
tick(e,6.2,5);assert(e._nw_fog_boss_body,"two seconds of resumed panic starts the body window")

-- Death/sleep/removal also release the independent post-exit body window.
for _,event in ipairs({"entitysleep","death","onremove"}) do
    e=entity();Wait.start(e,0,no_move);tick(e,2.1,1)
    assert(e._nw_fog_boss_body and not e._nw_fog_boss_wait)
    e.events[event]();assert(not e._nw_fog_boss_body)
    for _,task in ipairs(e.tasks) do assert(task.cancelled) end
end
print("boss wait: coverage-bound panic, two-second startup, independent 2.5-second moving sweep, teleport and lifecycle passed")
