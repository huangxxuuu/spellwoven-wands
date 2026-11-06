local A=require("nw/cast_action")
EQUIPSLOTS={HANDS="hands"};ACTIONS={NW_CAST={}}
local now=0;GetTime=function() return now end
TheWorld={ismastersim=true,Map={IsPassableAtPoint=function(_,x,y,z,water) return water and x~=5 end}}
local ready,combatcool,casts=true,false,0
local plan={}
local wand={components={nw_wand={}},_nw_ready={value=function() return true end},_nw_cancast={value=function() return ready end}}
function wand:HasTag(tag) return tag=="nw_wand" end
local cmp=wand.components.nw_wand
function cmp:CanCast(_,prepared) return ready and (prepared==nil or prepared==plan),nil,plan end
function cmp:Cast(_,pos,prepared) assert(prepared==plan and pos.x==4);casts=casts+1;return true end
local inv={GetEquippedItem=function() return wand end}
local combat={InCooldown=function() return combatcool end}
local player={components={inventory=inv,combat=combat},replica={inventory=inv,combat=combat},
    Transform={GetWorldPosition=function() return 0,0,0 end},HasTag=function() return false end}
local pos={x=4,z=0}
local function action(target)
    local a={doer=player,invobject=wand,target=target,point=not target and pos or nil,action=ACTIONS.NW_CAST}
    function a:GetActionPoint() return self.point end
    function a:SetActionPoint(p) self.point=p end
    return a
end
local options={};A.point(wand,player,pos,options,true);assert(options[1]==ACTIONS.NW_CAST)
options={};A.point(wand,player,{x=5,z=0},options,true);assert(#options==0)
options={};A.point(wand,player,pos,options,false);assert(#options==0)
ready=false;A.point(wand,player,pos,options,true);assert(#options==0)
local rejected=action();A.prepare(rejected);assert(not A.valid(rejected))
ready=true;now=10;assert(not A.valid(rejected) and not A.perform(rejected) and casts==0)
combatcool=true;assert(not A.available(wand,player,pos));combatcool=false
assert(A.available(wand,player,{x=30,z=0}))
assert(not A.available(wand,player,{x=0/0,z=0}) and not A.available(wand,player,{x=30.01,z=0}))
local target={IsValid=function() return true end,GetPosition=function() return pos end}
local act=action(target)
act.point={x=4,z=-2} -- cursor ray hits the ground behind the selected sprite
A.prepare(act);assert(act.target==nil and act:GetActionPoint()==pos)
assert(A.server_state(player,act)=="attack")
assert(A.perform(act) and casts==1);assert(not A.perform(act) and casts==1)
act=action();A.prepare(act);player._nw_edit_until=now+1;assert(not A.valid(act));player._nw_edit_until=0
TheWorld.ismastersim=false
assert(A.client_state(player,action())=="attack")
ready=false;assert(A.client_state(player,action())==nil)
ready=true;player._nw_editing=true;assert(A.client_state(player,action())==nil);player._nw_editing=false
local cancelled=0
player.GetBufferedAction=function() return action() end
player.ClearBufferedAction=function() cancelled=cancelled+1 end
A.stop(player);assert(cancelled==1)
player.GetBufferedAction=function() return {action={}} end
A.stop(player);assert(cancelled==1)
print("native action: native attack handler on both peers, silent rejection remains rejected, no replay, point targeting and edit cancellation")
