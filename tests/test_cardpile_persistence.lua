-- Exercise the real prefab callbacks: the server's visual choice survives load
-- and container refreshes, and an old save without this field remains loadable.
ANIM_ORIENTATION={BillBoard=7};LAYER_BACKGROUND=1
Asset=function() end
Prefab=function(name,fn) return {fn=fn} end
TheWorld={ismastersim=true}
net_byte=function()
    local value=0
    return {value=function() return value end,set=function(_,v) value=v end}
end
net_ushortint=net_byte
net_bool=function()
    local value=false
    return {value=function() return value end,set=function(_,v) value=v end}
end
package.loaded['nw/recycle_mark']={attach=function() end}
local serial=0
CreateEntity=function()
    serial=serial+1
    local inst={GUID=serial,components={},callbacks={},slots={{spell_id='fire'},{spell_id='frost'}}}
    inst.entity={AddTransform=function() end,AddAnimState=function() end,
        AddNetwork=function() end,SetPristine=function() end}
    inst.AnimState={SetBuild=function() end,SetOrientation=function() end,SetLayer=function() end,
        SetSortOrder=function() end,OverrideSymbol=function() end,SetBankAndPlayAnimation=function() end}
    inst.AddTag=function() end
    inst.ListenForEvent=function(self,event,fn) self.callbacks[event]=fn end
    inst.DoTaskInTime=function(self,_,fn) self.pending=fn;return {} end
    inst.AddComponent=function(self,name)
        self.components[name]={WidgetSetup=function() end,SetName=function() end,
            GetNumSlots=function() return 25 end,
            GetItemInSlot=function(_,i) return self.slots[i] end,
            NumItems=function() return #self.slots end}
    end
    return inst
end
local prefab=require('prefabs/nw_spellpile')
local original=math.random
math.random=function() return .1 end
local first=prefab.fn();assert(first._separated:value())
local saved={};first:OnSave(saved);assert(saved.separated==true)
math.random=function() return .9 end
local restored=prefab.fn();assert(not restored._separated:value())
restored:OnLoad(saved);assert(restored._separated:value())
restored.pending(restored)
for i=3,12 do restored.slots[i]={spell_id='speed_up'} end
restored.callbacks.itemget(restored);restored.pending(restored)
assert(restored._separated:value(),'adding cards must not reroll the visual')
assert(math.floor(restored._layers:value()/9)==2,'count only lower hexagons')
local saved_again={};restored:OnSave(saved_again);assert(saved_again.separated)
restored:OnLoad({separated=false});assert(not restored._separated:value())
restored:OnLoad({});assert(not restored._separated:value())
math.random=original
print('card pile persistence: true/false save values, legacy saves and item changes preserve the chosen visual')
