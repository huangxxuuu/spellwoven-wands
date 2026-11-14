local M={}
function M.tag(inst,p)
    if not inst or not p then return end
    local prefab,key=inst._nw_native_prefab or inst.prefab,p.engraving
    local continuation=(key=="trident" and prefab=="trident")
        or (key=="staff_lunarplant" and (prefab=="staff_lunarplant" or prefab=="brilliance_projectile_fx"))
        or (key=="staff_tornado" and prefab=="tornado" and not inst._nw_controller)
        or (key=="voidcloth_boomerang" and prefab=="voidcloth_boomerang_proj" and not inst._nw_controller)
        or (key and key:find("^dumbbell") and prefab==key)
        or (p.source_weapon=="ruins_bat" and prefab=="shadowtentacle")
    if continuation then inst._nw_native_base_multiplier=p.base_damage_multiplier or 1 end
end
local function pack(...) return {n=select("#",...),...} end
function M.wrap_combat(combat)
    if combat._nw_native_base_wrapped then return end
    combat._nw_native_base_wrapped=true
    local key=combat.GetAttacked_Internal and "GetAttacked_Internal" or "GetAttacked"
    local attacked=combat[key]
    combat[key]=function(self,attacker,damage,weapon,stimuli,spdamage,...)
        local rate=weapon and weapon._nw_native_base_multiplier or attacker and attacker._nw_native_base_multiplier
        if not rate then return attacked(self,attacker,damage,weapon,stimuli,spdamage,...) end
        local from=self.redirected_from
        local forwarded=from and from.components and from.components.combat
            and from.components.combat._nw_native_base_forward
        if forwarded and forwarded.pending and forwarded.attacker==attacker and forwarded.weapon==weapon then
            forwarded.pending=false
        else
            damage=damage and damage*rate
            if spdamage then
                local scaled={}
                for k,v in pairs(spdamage) do scaled[k]=type(v)=="number" and v*rate or v end
                spdamage=scaled
            end
        end
        local previous=self._nw_native_base_forward
        self._nw_native_base_forward={attacker=attacker,weapon=weapon,pending=true}
        local result=pack(pcall(attacked,self,attacker,damage,weapon,stimuli,spdamage,...))
        self._nw_native_base_forward=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
end
return M
