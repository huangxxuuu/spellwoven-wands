local Visual=require("nw/visual")
local assets = {
    Asset("ATLAS","images/inventoryimages/nw_icons.xml"),
    Asset("IMAGE","images/inventoryimages/nw_icons.tex"),
    Asset("ANIM", "anim/nw_parts.zip"),
    Asset("ANIM", "anim/swap_cane.zip"),
    Asset("ANIM", "anim/staffs.zip"),
    Asset("ANIM", "anim/swap_staffs.zip"),
    Asset("ANIM", "anim/ui_board_5x3.zip"),
}
for code=0,Visual.count-1,Visual.per_style do
    local atlas=Visual.atlas(code)
    table.insert(assets,Asset("ATLAS",atlas))
    table.insert(assets,Asset("IMAGE",(atlas:gsub("%.xml$",".tex"))))
end
local function equip(inst, owner)
    owner.AnimState:OverrideSymbol("swap_object", "nw_parts", "anchor")
    if inst._held_visual then inst._held_visual:Remove() end
    inst._held_visual = SpawnPrefab("nw_wand_visual")
    inst._held_visual.entity:SetParent(owner.entity)
    inst._held_visual._look:set(inst._nw_look:value())
    inst._held_visual._broken:set(inst._nw_broken:value())
    owner.AnimState:Show("ARM_carry")
    owner.AnimState:Hide("ARM_normal")
end
local function unequip(inst, owner)
    if inst._held_visual then inst._held_visual:Remove(); inst._held_visual = nil end
    owner.AnimState:Hide("ARM_carry")
    owner.AnimState:Show("ARM_normal")
end
local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()
    MakeInventoryPhysics(inst)
    inst:AddTag("nw_wand")
    inst:AddTag("_writeable")
    inst:AddTag("allow_action_on_impassable") -- Native right-click picker also offers POINT actions over water.
    -- Native attack animation, without adding a melee weapon or custom state.
    inst:AddTag("nopunch");inst:AddTag("rangedweapon")
    -- Both peers declare the same schema before the client return.
    inst._nw_broken = net_bool(inst.GUID,"nw_wand.broken","nw_lookdirty")
    inst._nw_ready = net_bool(inst.GUID, "nw_wand.ready", "nw_wanddirty")
    inst._nw_cancast = net_bool(inst.GUID, "nw_wand.cancast", "nw_wanddirty")
    inst._nw_castreason = net_string(inst.GUID,"nw_wand.castreason","nw_wanddirty")
    inst._nw_capacity = net_smallbyte(inst.GUID, "nw_wand.capacity", "nw_wanddirty")
    inst._nw_mana = net_ushortint(inst.GUID, "nw_wand.mana", "nw_wanddirty")
    inst._nw_look = net_ushortint(inst.GUID, "nw_wand.look", "nw_lookdirty")
    inst._nw_cards=net_string(inst.GUID,"nw_wand.cards","nw_wanddirty")
    inst._nw_stats=net_string(inst.GUID,"nw_wand.stats","nw_wanddirty")
    inst._nw_revision=net_uint(inst.GUID,"nw_wand.revision","nw_wanddirty")
    inst._nw_maxmana=net_ushortint(inst.GUID,"nw_wand.maxmana","nw_wanddirty")
    inst._nw_cooldown=net_ushortint(inst.GUID,"nw_wand.cooldown","nw_wanddirty")
    inst._nw_cooltotal=net_ushortint(inst.GUID,"nw_wand.cooltotal","nw_wanddirty")
    require("nw/visual").apply(inst, 0, "ground")
    MakeInventoryFloatable(inst, "med", .1)
    local function refresh() require("nw/visual").apply_dropped(inst, inst._nw_look:value()) end
    require("nw/recycle_mark").attach(inst,function(glow,item)
        Visual.apply_dropped(glow,item._nw_look:value(),item.components.floater and item.components.floater:IsFloating())
    end)
    inst.entity:SetPristine()
    inst.displaynamefn=function(self)
        if self.name_author_netid or self:HasTag("nw_customname") then return end -- Keep native filtering for player-written names.
        return require("nw/locale").translate(self.name)
    end
    if not TheWorld.ismastersim then
        inst:ListenForEvent("nw_lookdirty", refresh)
        inst:ListenForEvent("landeddirty", function() inst:DoTaskInTime(0,refresh) end)
        inst:DoTaskInTime(0, refresh)
        return inst
    end
    inst:ListenForEvent("floater_startfloating", function()
        require("nw/visual").apply_dropped(inst,inst._nw_look:value(),true)
    end)
    inst:ListenForEvent("floater_stopfloating", function()
        require("nw/visual").apply_dropped(inst,inst._nw_look:value(),false)
    end)
    inst:ListenForEvent("onremove", function()
        if inst._held_visual then inst._held_visual:Remove(); inst._held_visual = nil end
    end)
    inst:AddComponent("inspectable")
    inst:AddComponent("named")
    inst:RemoveTag("_writeable")
    require("nw/wand_naming").setup(inst)
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname=Visual.atlas(0)
    inst.components.inventoryitem:ChangeImageName(require("nw/visual").icon(0))
    inst:AddComponent("equippable")
    inst.components.equippable:SetOnEquip(equip)
    inst.components.equippable:SetOnUnequip(unequip)
    inst:AddComponent("nw_wand")
    require("nw/wand_container").setup(inst)
    inst:AddComponent("weapon")
    inst.components.weapon:SetDamage(function() return inst:HasTag("nw_broken") and 0 or TUNING.UNARMED_DAMAGE end)
    inst.components.weapon:SetOnAttack(require("nw/wand_damage").hit)
    inst.OnSave=function(self,data) data.nw_customname=self:HasTag("nw_customname") or nil end
    inst.OnLoad=function(self,data) if data and data.nw_customname then self:AddTag("nw_customname") end end
    inst.onPreBuilt = function(self, builder, materials, recipe)
        local row = require("nw/acquisition").by_name[recipe.name]
        self.components.nw_wand:InitializeNew(row and row.tier or 0, recipe.name)
    end
    inst:DoTaskInTime(0, function()
        if inst.components.nw_wand.data == nil then inst.components.nw_wand:InitializeNew(0,"starter") end
    end)
    -- Inventory cooldown meters must keep advancing after unequipping, too.
    inst:DoPeriodicTask(.1,function()
        local wand=inst.components.nw_wand
        local data=wand.data
        if data then
            local r=data.runtime
            if r.mana<data.stats.mana_max or r.remaining_cast>0 or r.remaining_recharge>0 then
                wand:UpdateTime()
            end
        end
    end)
    return inst
end
return Prefab("nw_wand", fn, assets, {"nw_wand_visual","nw_projectile"})
