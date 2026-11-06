local Wand = Class(function(self, inst) self.inst = inst end)
function Wand:IsReady() return self.inst._nw_ready:value() end
function Wand:GetCapacity() return self.inst._nw_capacity:value() end
function Wand:GetMana() return self.inst._nw_mana:value() end
return Wand
