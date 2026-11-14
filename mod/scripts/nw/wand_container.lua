local C=require("nw/constants/ui").wand_container
local M={}
local Layout=require("nw/hud_layout")

function M.owner(inst)
    local item=inst.components.inventoryitem
    local p=item and item.owner
    return p and p.components.inventory
        and p.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==inst
        and p.components.health and not p.components.health:IsDead()
        and require("nw/editing").near(p) and p or nil
end

function M.install(env)
    local containers=require("containers")
    local positions={}
    for i=1,C.slots do positions[i]=Vector3((i-C.centre)*Layout.slot_step,0,0) end
    containers.params.nw_wand={type="nw_wand",acceptsstacks=false,
        widget={slotpos=positions,pos=Vector3(0,0,0),slotscale=C.slot_pixels/C.texture_pixels,
            bgatlas="images/hud.xml",bgimage="inv_slot.tex"},
        itemtestfn=function(container,item,slot)
            if not item:HasTag("nw_spellcard") or not item._spell
                or not require("nw/cards").playable[require("nw/cards").bycode[item._spell:value()]] then return false end
            local capacity=container.inst._nw_capacity:value()
            if slot then return slot>=1 and slot<=capacity end
            for i=1,capacity do if not container:GetItemInSlot(i) then return true end end
            return false
        end}
    containers.MAXITEMSLOTS=math.max(containers.MAXITEMSLOTS,12)
    if not TheNet:IsDedicated() then
        env.AddClassPostConstruct("widgets/containerwidget",M.widget)
    end
end

function M.layout(widget,count)
    for i,slot in ipairs(widget.inv) do
        if i<=count then
            slot:SetPosition((i-(count+1)/2)*Layout.slot_step,0)
            slot:Show()
        else slot:Hide() end
    end
end

function M.widget(widget)
    local open=widget.Open
    widget.Open=function(self,inst,doer)
        open(self,inst,doer)
        if not inst:HasTag("nw_wand") then return end
        local panel=doer.HUD and doer.HUD.controls.nw_wandpanel
        if panel then
            panel:AddChild(self)
            self:SetScale(1)
            self:SetPosition(0,0)
            self.bgimage:Hide();self.bganim:Hide()
            M.layout(self,inst._nw_capacity:value())
            panel.native_container=self
            panel.row:Hide()
        end
    end
end

function M.sync(inst)
    if not inst.components then return end
    local c=inst.components.container
    local w=inst.components.nw_wand
    local d=w and w.data
    if not c or not d or c._nw_syncing
        or c._nw_data==d and c._nw_revision==d.config_revision then return end
    c._nw_syncing=true
    for i=1,c:GetNumSlots() do
        local item=c:RemoveItemBySlot(i)
        if item then item:Remove() end
    end
    for i=1,d.stats.capacity do
        local card=d.cards[i]
        if card then
            local item=SpawnPrefab("nw_spellcard")
            item:SetSpell(card.spell_id)
            item.card_uid,item.source=card.card_uid,card.source
            c:GiveItem(item,i,nil,false)
        end
    end
    c._nw_data,c._nw_revision=d,d.config_revision
    c._nw_syncing=nil
end

function M.changed(inst)
    local c=inst.components.container
    local w=inst.components.nw_wand
    if c._nw_syncing or not w.data then return end
    c._nw_syncing=true
    w:UpdateTime()
    local d=w.data
    local cards={}
    for i=1,d.stats.capacity do
        local item=c:GetItemInSlot(i)
        if item then
            local uid=require("nw/card_identity").unique(cards,item:GetCardUID())
            item.card_uid=uid
            cards[i]={spell_id=item.spell_id,card_uid=uid,source=item.source}
        else cards[i]=false end
    end
    local previous=d.runtime
    d.cards=cards
    d.runtime=require("nw/compiler").initial(cards,d.stats,previous.rng_state)
    d.runtime.mana=previous.mana
    d.runtime.remaining_cast=previous.remaining_cast
    d.runtime.remaining_recharge=math.max(previous.remaining_recharge,d.stats.recharge)
    d.config_revision=d.config_revision+1
    c._nw_data,c._nw_revision=d,d.config_revision
    c._nw_syncing=nil
    w:Sync()
end

function M.setup(inst)
    inst:AddComponent("container")
    local c=inst.components.container
    c:WidgetSetup("nw_wand")
    c.canbeopened=false
    c.skipopensnd=true;c.skipclosesnd=true
    c.excludefromcrafting=true
    c.OnSave=function() return nil end
    c.OnLoad=function() end
    local can=c.CanTakeItemInSlot
    c.CanTakeItemInSlot=function(self,item,slot)
        return (self._nw_syncing or M.owner(inst)~=nil) and can(self,item,slot)
    end
    local give=c.GiveItem
    c.GiveItem=function(self,item,slot,...)
        if slot and self:GetItemInSlot(slot) then
            slot=nil
        end
        return give(self,item,slot,...)
    end
    local remove=c.RemoveItem_Internal
    c.RemoveItem_Internal=function(self,...)
        if self._nw_syncing or M.owner(inst) then return remove(self,...) end
    end
    local open=c.Open
    c.Open=function(self,doer)
        if doer and M.owner(inst)==doer then return open(self,doer) end
    end
    for _,name in ipairs({"PutOneOfActiveItemInSlot","PutAllOfActiveItemInSlot",
        "TakeActiveItemFromHalfOfSlot","TakeActiveItemFromCountOfSlot","TakeActiveItemFromAllOfSlot",
        "AddOneOfActiveItemToSlot","AddAllOfActiveItemToSlot",
        "SwapActiveItemWithSlot","SwapOneOfActiveItemWithSlot",
        "MoveItemFromAllOfSlot","MoveItemFromHalfOfSlot","MoveItemFromCountOfSlot"}) do
        local method=c[name]
        c[name]=function(self,...)
            if M.owner(inst) then return method(self,...) end
        end
    end
    inst:ListenForEvent("itemget",M.changed)
    inst:ListenForEvent("itemlose",M.changed)
    inst:ListenForEvent("unequipped",function() c:Close() end)
    inst:ListenForEvent("onremove",function()
        c._nw_syncing=true
        for i=1,c:GetNumSlots() do
            local item=c:GetItemInSlot(i)
            if item then item:Remove() end
        end
    end)
    inst:DoPeriodicTask(C.refresh_interval,function()
        local owner=M.owner(inst)
        for p in pairs(c.openlist) do if p~=owner then c:Close(p) end end
        if owner and inst.components.nw_wand.data then
            M.sync(inst)
            if not c:IsOpenedBy(owner) then c:Open(owner) end
        end
    end)
end

return M
