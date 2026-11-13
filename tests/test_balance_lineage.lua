local Balance=require("nw/balance")
Balance.configure("balanced")
local E=require("nw/executor")
local D=require("nw/balance_damage")
local U=require("nw/util")
local C=require("nw/compiler")
local count=0
TheWorld={ismastersim=true,components={nw_identity={Next=function() count=count+1;return "root:"..count end}}}
GetTime=function() return 0 end
DEGREES=math.pi/180
local owner={GUID=71,components={},IsValid=function() return true end,
    Transform={GetWorldPosition=function() return 0,0,0 end}}
local shots={}
SpawnPrefab=function()
    local e={valid=true}
    function e:IsValid() return self.valid end
    function e:Remove() if self.valid then self.valid=false;if self.cleanup then self.cleanup() end end end
    function e:Launch(caster,p,x,z,dx,dz,cleanup,height,fire,payload)
        self.p,self.caster,self.cleanup,self.payload,self.fire=p,caster,cleanup,payload,fire
        self._shot={p=p,owner=caster,x=x,z=z,dx=dx,dz=dz,height=height,travelled=3}
    end
    shots[#shots+1]=e;return e
end
local function plan(ids)
    local w=require("nw/generator").starter();w.stats.mana_max=10000;w.cards={}
    for i,id in ipairs(ids) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=C.initial(w.cards,w.stats,1)
    return assert(C.compile(w))
end
local p=plan({"repeat_3","double","spark_hit","arrow","spark_timer","fire"})
assert(E.execute(p,owner,0,0,1,0,1))
local root=shots[1].p._nw_root
assert(root and not p.blocks[1].projectiles[1]._nw_root)
local carriers=#shots
assert(carriers==6)
for i=1,carriers do assert(shots[i].p._nw_root==root);shots[i].fire(0,0,1,0) end
for _,e in ipairs(shots) do assert(e.p._nw_root==root and e._nw_root==root) end
local nextshot=#shots+1
assert(E.execute(p,owner,0,0,1,0,1));assert(shots[nextshot].p._nw_root~=root)
-- Side embers re-enter the executor but retain the original cast.
local side=shots[1]._shot
side.p=U.copy(side.p);side.p.flags.side_embers=true
side.context={side_left=4,arcs={}};side.travelled=3
local start=#shots
require("nw/expanded_hits").step(side,0)
assert(#shots==start+2 and shots[#shots].p._nw_root==root)
-- Field-generated projectiles and explicit re-entry carry the same identity.
local field=U.copy(side.p);field.flags={};field.radius=10
local child=require("nw/field_effects").shot(field,"bee_swarm",16,.42)
assert(child._nw_root==root)
assert(E.execute({blocks={{projectiles={child}}},projectile_count=1,next_state={rng_state=1}},owner,0,0,1,0,1,nil,root))
assert(shots[#shots].p._nw_root==root)
-- Existing snapshots never gain mutable/root state; attaching a different
-- cast identity creates a new parameter record without changing shared flags.
local copied=D.parameters(child,"another-root")
assert(copied~=child and child._nw_root==root and copied.flags==child.flags)
for _,e in ipairs(shots) do e:Remove() end
assert(E.stats()==0)
print("balance lineage: copies/multicast, collision/timer children, side embers, emitted fields, template isolation")
