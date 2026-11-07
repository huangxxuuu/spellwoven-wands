local arena=require("nw/photo_arena")
local function entity(x,z,tag,owner,parent)
    local e={prefab="test",components={inventoryitem={owner=owner}},entity={GetParent=function() return parent end},
        Transform={GetWorldPosition=function() return x,0,z end}}
    function e:IsValid() return not self.removed end
    function e:HasTag(t) return t==tag end
    function e:Remove() self.removed=true end
    return e
end
local player=entity(0,0,"player")
ConsoleCommandPlayer=function() return player end
WORLD_TILES={CARPET=1,CHECKER=2}
local changed={}
TheWorld={ismastersim=true,Map={
    GetTileCoordsAtPoint=function(_,x,y,z) return math.floor(x/4+.5),math.floor(z/4+.5) end,
    GetTileCenterPoint=function(_,x,z) return x*4,0,z*4 end,
    IsPassableAtPoint=function() return true end,
    IsOceanAtPoint=function(_,x,y,z) return x==8 and z==8 end,
    SetTile=function(_,x,z,t) changed[x..":"..z]=t end,
}}
local inside=entity(8,0)
local outside=entity(12,0)
local held=entity(0,0,nil,player)
local attached=entity(0,0,nil,nil,player)
TheSim={FindEntities=function() return {player,inside,outside,held,attached} end}
local count,removed=arena.build(2)
assert(count==24 and removed==1 and inside.removed)
assert(not player.removed and not outside.removed and not held.removed and not attached.removed)
assert(changed["0:0"]==1 and changed["2:0"]==1 and changed["1:1"]==2 and changed["2:2"]==nil)
changed={}
assert(arena.build(0)==nil and next(changed)==nil)
assert(arena.build(2.5)==nil and next(changed)==nil)
TheWorld.ismastersim=false
assert(arena.build(2)==nil and next(changed)==nil)
print("photo arena: bounds, carpet layout, ocean and player/inventory protection")
