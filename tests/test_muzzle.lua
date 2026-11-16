local M=require("nw/muzzle")
local owner={components={},Transform={GetWorldPosition=function() return 10,0,20 end},AnimState={}}
local found=true
local tip_height,hand_height=2.6,1.2
function owner.AnimState:GetSymbolPosition(symbol,x,y,z)
    assert(symbol=="swap_object" and x==0 and z==0)
    local v=require("nw/visual")
    assert(y==0 or y==80*v.scale.short*1.2 or y==94*v.scale.medium*1.2 or y==110*v.scale.long*1.2,
        "ordinary casts must keep positive symbol offsets")
    return 10.4,y==0 and hand_height or tip_height,20.2,found
end
for _,capacity in ipairs({4,8,12}) do
    local x,y,z,source=M.origin(owner,capacity,1,0)
    assert(source=="hand" and x==10+(capacity==4 and 1 or capacity==8 and 1.2 or 1.4) and y==hand_height and z==20)
end
tip_height=.35
for _,capacity in ipairs({4,8,12}) do
    local _,height,_,source=M.origin(owner,capacity,1,0)
    assert(height==hand_height and source=="hand","wand tip must not set the flight height")
end
hand_height=2.8;tip_height=2.7
local _,athand=M.origin(owner,4,1,0)
assert(math.abs(athand-hand_height)<.000001,"projectile must leave at the hand, without extra lift")
hand_height=.65
assert(select(2,M.origin(owner,12,1,0))==hand_height,"old wand-height floor must not lift a low hand pose")
hand_height=1.2;tip_height=2.6
found=false
local x,y,z,source=M.origin(owner,4,1,0)
assert(source=="fallback" and x==11 and y==M.default_height and z==20)
local _,long=M.origin(owner,12,1,0);assert(long==y,"fallback height must not depend on wand length")
owner.components.rider={IsRiding=function() return true end}
local _,mounted=M.origin(owner,4,1,0);assert(mounted==M.default_height+1)
found=true;hand_height=2.4
assert(select(2,M.origin(owner,4,1,0))==hand_height,"riding lift must not be added twice to a valid hand")
owner.Transform.GetWorldPosition=function() return 10,1,20 end
hand_height=2.7
assert(select(2,M.origin(owner,4,1,0))==hand_height,"hand world height must not include the owner's height twice")
owner.Transform.GetWorldPosition=function() return 10,0,20 end
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
local held={components={},_nw_pose_hold={},sg={currentstate={name="nw_hold_pose"}},
    Transform={GetWorldPosition=function() return 10,0,20 end},AnimState={}}
local sx,sy,sz,tip_found=10.25,2.6,20.4,true
local offsets={}
function held.AnimState:GetSymbolPosition(symbol,x,y,z)
    assert(symbol=="swap_object" and x==0 and z==0)
    if y==0 then return 10.1,1.1,20.1,true end
    local pose=held._nw_pose_hold and held.sg.currentstate.name=="nw_hold_pose" and not held.components.rider
    assert(pose and y<0 or not pose and y>0,"only custom held poses must sample negative local Y")
    offsets[#offsets+1]=y
    return sx,sy,sz,tip_found
end
local function close(actual,expected,message)
    assert(math.abs(actual-expected)<1e-8,message)
end
for _,capacity in ipairs({4,8,12}) do
    local px,py,pz,kind=M.origin(held,capacity,1,0)
    close(px,10.25,"held tip must retain recoil behind the old forward minimum")
    close(py,2.6,"held projectile must use the actual tip height")
    close(pz,20.4,"held tip must retain its side displacement")
    assert(kind=="tip")
end
local visual=require("nw/visual")
close(offsets[1],-80*visual.scale.short*1.2,"short held staff tip offset")
close(offsets[2],-94*visual.scale.medium*1.2,"medium held staff tip offset")
close(offsets[3],-110*visual.scale.long*1.2,"long held staff tip offset")
sx,sy,sz=9.85,1.7,19.7
x,y,z=M.origin(held,4,1,0)
close(x,9.85,"recoil may move the tip behind the player")
close(y,1.7,"recoil must retain the sampled height")
close(z,19.7,"recoil must retain the sampled side offset")
sx,sy,sz=10.25,2.6,20.4
held._nw_pose_hold=nil
assert(select(4,M.origin(held,4,1,0))=="hand","state alone must not enable held muzzle")
held._nw_pose_hold={};held.sg.currentstate.name="idle"
assert(select(4,M.origin(held,4,1,0))=="hand","hold bookkeeping alone must not enable held muzzle")
held.sg.currentstate.name="nw_hold_pose"
held.components.rider={IsRiding=function() return true end}
assert(select(4,M.origin(held,4,1,0))=="hand","mounted casts must keep the old muzzle")
held.components.rider=nil
sx,sy,sz=10.25,.1,20.4
x,y,z,source=M.origin(held,12,1,0)
assert(source=="tip" and y==.1,"low front-facing staff must retain its actual tip")
for _,invalid in ipairs({{0/0,2.6,20.4,true},{10.25,.02,20.4,true},{10.25,-.1,20.4,true},
    {10.25,5,20.4,true},{15,2.6,20.4,true},{10.25,2.6,20.4,false}}) do
    sx,sy,sz,tip_found=unpack(invalid)
    x,y,z,source=M.origin(held,4,1,0)
    assert(x==11 and y==1.1 and z==20 and source=="hand","invalid tip must fall back to valid hand path")
end
sx,sy,sz,tip_found=12,2.6,22,true
TheSim.FindEntities=function() return {} end
x,y,z=M.origin(held,4,1,0,.5)
close(x,10+.4/math.sqrt(2),"near aim must shorten the actual tip segment")
close(z,20+.4/math.sqrt(2),"near aim must preserve the tip segment direction")
close(y,2.6,"clearance must preserve flight height")
wall.Transform.GetWorldPosition=function() return 11,0,21 end
TheSim.FindEntities=function() return {held,wall} end
x,y,z=M.origin(held,4,1,0,8)
local boundary=1-.62/math.sqrt(2)
close(x,10+boundary,"held muzzle crossed a nearby target on its diagonal segment")
close(z,20+boundary,"target clearance must follow the actual tip side offset")
TheSim.FindEntities=function() return {} end
TheWorld.Map.IsPassableAtPoint=function(_,px,py,pz)
    close(px-10,pz-20,"terrain samples must follow the tip segment")
    return px<=11
end
x,y,z=M.origin(held,4,1,0,8)
close(x,10+2/3,"held muzzle crossed impassable terrain")
close(z,20+2/3,"terrain clearance must retain the tip segment direction")
print("muzzle: legacy hand/fallback clearance; held tip height, side/recoil, all lengths, fallback and segment clearance")
