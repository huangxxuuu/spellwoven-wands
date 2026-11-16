Class=function(ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...) local o=setmetatable({},cls);ctor(o,...);return o end})
end
TheNet={GetSessionIdentifier=function() return "emission-test" end}
TheShard={GetShardId=function() return "1" end}
local Identity=require("components/nw_identity")
local Emissions=require("nw/cast_emissions")
TheWorld={components={nw_identity=Identity({})}}
local a=Emissions.new();a.permanent_spawned=7
local early=Emissions.save(a)
a.permanent_spawned=19
local later=Emissions.save(a)
assert(early.id==later.id and early.permanent_spawned==7)
assert(not Emissions.new().id,"ordinary casts need no saved identity")
TheWorld={components={nw_identity=Identity({})}}
local restored=Emissions.restore(later)
assert(Emissions.restore(early)==restored and restored.permanent_spawned==19,
    "load order must not lower the shared cumulative counter")
assert(TheWorld.components.nw_identity.sequence==1)
assert(Emissions.save(Emissions.new()).id~=later.id,"observed saved IDs cannot be reissued")
local b=Emissions.restore({id="nw:emission-test:1:100",permanent_spawned=4})
assert(b~=restored and TheWorld.components.nw_identity.sequence==100)
assert(getmetatable(TheWorld._nw_cast_emissions).__mode=="v","the registry must not retain finished casts")
assert(Emissions.restore(nil).permanent_spawned==0)
assert(Emissions.restore({id="bad",permanent_spawned=math.huge}).permanent_spawned==0)
print("cast emissions: compact snapshots, shared restore, monotonic counters, identity observation, independent groups and weak registry")
