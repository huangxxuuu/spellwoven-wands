local G=require("nw/generator")
local C=require("nw/compiler")
local E=require("nw/executor")
local w=G.starter()
w.cards={{card_uid="1",spell_id="double"},{card_uid="2",spell_id="spark"},{card_uid="3",spell_id="arrow"},false}
w.runtime=C.initial(w.cards,w.stats,1)
DEGREES=math.pi/180
local count=0
local live={}
SpawnPrefab=function()
    count=count+1
    if count==2 then return nil end
    local obj={removed=false,Remove=function(self) self.removed=true end}
    live[#live+1]=obj
    return obj
end
local owner={GUID=1}
local p=assert(C.compile(w))
local ok,err=E.execute(p,owner,0,0,1,0)
assert(not ok and err=="SPAWN_FAILED")
assert(live[1].removed and E.stats()==0)
SpawnPrefab=function()
    local obj={}
    function obj:Launch(owner,desc,x,z,dx,dz,cleanup,height)
        assert(math.abs(dx*dx+dz*dz-1)<1e-9)
        assert(height==1.75,"muzzle height lost by executor")
        self.cleanup=cleanup
    end
    live[#live+1]=obj
    return obj
end
assert(E.execute(p,owner,0,0,1,0,1.75))
assert(E.stats()==2)
live[2].cleanup();live[3].cleanup();assert(E.stats()==0)
print("executor: spawn failure cleanup, normalized spread, real allocation/release")
-- Point-targeted tornado travel must not overwrite the lifetime modifier.
local tornado
SpawnPrefab=function()
    local obj={}
    function obj:Launch(_,desc,_,_,_,_,cleanup)
        self.cleanup=cleanup
        self._shot={p=desc,speed=desc.speed,remaining=desc.lifetime}
        tornado=self
    end
    return obj
end
w.cards={{card_uid="1",spell_id="short_life"},{card_uid="2",spell_id="edge_staff_tornado"}}
w.stats.mana_max=600;w.runtime=C.initial(w.cards,w.stats,1)
p=assert(C.compile(w))
assert(E.execute(p,owner,0,0,1,0,1.75,{x=30,z=0}))
assert(tornado._shot.aim_distance==30 and tornado._shot.remaining==1.5)
tornado.cleanup();assert(E.stats()==0)
