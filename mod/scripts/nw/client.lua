local M={}
function M.tile(self)
    if self.item and self.item:HasTag("nw_spellcard") then
        require("nw/inventory_hint").install(self,false)
        return
    end
    if not self.item or not self.item:HasTag("nw_wand") then return end
    require("nw/inventory_hint").install(self,true)
end
return M
