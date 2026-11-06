local M=require("nw/muzzle")
local owner={components={},Transform={GetWorldPosition=function() return 10,0,20 end},AnimState={}}
local found=true
function owner.AnimState:GetSymbolPosition(symbol,x,y,z)
    assert(symbol=="swap_object" and x==0 and z==0)
    local v=require("nw/visual")
    assert(y==80*v.scale.short*1.2 or y==94*v.scale.medium*1.2 or y==110*v.scale.long*1.2)
    return 10.4,1.9,20.2,found
end
for _,capacity in ipairs({4,8,12}) do
    local x,y,z,source=M.origin(owner,capacity,1,0)
    assert(source=="symbol" and x==10+(capacity==4 and 1 or capacity==8 and 1.2 or 1.4) and y==1.9 and z==20)
end
found=false
local x,y,z,source=M.origin(owner,4,1,0)
assert(source=="fallback" and x==11 and y==1.4 and z==20)
local _,long=M.origin(owner,12,1,0);assert(long>y)
owner.components.rider={IsRiding=function() return true end}
local _,mounted=M.origin(owner,4,1,0);assert(mounted==2.4)
owner.AnimState.GetSymbolPosition=function() return 0/0,1000,0,true end
assert(select(4,M.origin(owner,4,1,0))=="fallback")
TheWorld={Map={IsPassableAtPoint=function() return true end}}
local wall={components={health={IsDead=function() return false end}},
    IsValid=function() return true end,GetPhysicsRadius=function() return .5 end,
    Transform={GetWorldPosition=function() return 10,0,21.5 end}}
TheSim={FindEntities=function() return {wall} end}
local ax,_,az=M.origin(owner,12,0,1,8)
assert(ax==10 and math.abs(az-20.88)<1e-8,"forward offset crossed a wall")
ax,_,az=M.origin(owner,12,-1,0,.4)
assert(math.abs(ax-9.68)<1e-8 and az==20,"point-blank cast overshot aim")
print("muzzle: three length-specific symbol offsets, real tip coordinates, missing/invalid-symbol and riding fallback")
