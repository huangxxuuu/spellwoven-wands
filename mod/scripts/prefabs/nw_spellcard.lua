local Cards=require("nw/cards")
local Ground=require("nw/ground_card")
local assets=Ground.assets()
assets[#assets+1]=Asset("ATLAS","images/inventoryimages/nw_icons.xml")
assets[#assets+1]=Asset("IMAGE","images/inventoryimages/nw_icons.tex")
local function refresh(inst)
    local code=inst._spell:value()
    Ground.show(inst,code,1)
    if inst._nw_outline then Ground.show(inst._nw_outline,code,1) end
end
local function fn()
    local inst=CreateEntity()
    inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddNetwork()
    MakeInventoryPhysics(inst)
    inst:AddTag("nw_spellcard")
    inst._spell=net_byte(inst.GUID,"nw_card.spell","nw_carddirty")
    inst.displaynamefn=function(self) return Cards.names[Cards.bycode[self._spell:value()]] end
    inst.stackable_CanStackWithFn=function(a,b) return a._spell:value()~=0 and a._spell:value()==b._spell:value() end
    require("nw/recycle_mark").attach(inst,function(glow,item)
        Ground.show(glow,item._spell:value(),1)
    end)
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then
        inst:ListenForEvent("nw_carddirty",refresh);inst:DoTaskInTime(0,refresh)
        return inst
    end
    inst:AddComponent("stackable")
    inst.components.stackable.maxsize=40
    inst.components.stackable:SetOnDeStack(function(one,stack)
        one:SetSpell(stack.spell_id)
        one.source=stack.source
    end)
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname="images/inventoryimages/nw_icons.xml"
    inst:AddComponent("inspectable");inst:AddComponent("named")
    function inst:SetSpell(id)
        assert(Cards.codes[id],"unsupported card")
        self.spell_id=id;self._spell:set(Cards.codes[id])
        self.components.named:SetName(Cards.names[id])
        self.components.inventoryitem:ChangeImageName("nw_spell_"..id)
        self.components.inspectable.description=Cards.names[id]
        refresh(self)
        require("nw/spelljournal").observe(require("nw/spelljournal").owner(self),self)
    end
    function inst:GetCardUID()
        local Identity=require("nw/card_identity")
        if not Identity.valid(self.card_uid) then self.card_uid=require("nw/wand_factory").uid() end
        Identity.observe(self.card_uid)
        return self.card_uid
    end
    inst.onPreBuilt = function(self, builder, materials, recipe)
        self.source = recipe.name
        local row = require("nw/acquisition").by_name[recipe.name]
        self:SetSpell(row and row.card or "spark")
    end
    inst.OnSave=function(self,data)
        data.spell_id, data.card_uid, data.source = self.spell_id, self:GetCardUID(), self.source
    end
    inst.OnLoad=function(self,data)
        self.card_uid, self.source = data and data.card_uid, data and data.source or "legacy"
        self:GetCardUID()
        local id=Cards.migrate_id(data and data.spell_id)
        self:SetSpell(Cards.codes[id] and id or "spark")
    end
    -- Allocate at creation, never for the first time after the world counter
    -- has already been serialized during a save.
    inst:GetCardUID()
    inst:SetSpell("spark")
    return inst
end
return Prefab("nw_spellcard",fn,assets)
