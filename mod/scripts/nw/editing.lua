local C=require("nw/compiler")
local U=require("nw/util")
local M={}
function M.near(player)
    local x,y,z=player.Transform:GetWorldPosition()
    return #TheSim:FindEntities(x,y,z,4,{"nw_workbench"},{"INLIMBO"})>0
end
function M.commit(player,wand,slot,source,revision,cursor)
    local cmp=wand.components.nw_wand
    local inv=player.components.inventory
    if not cmp or not cmp.data or not inv or inv:GetEquippedItem(EQUIPSLOTS.HANDS)~=wand
        or not player.components.health or player.components.health:IsDead() then return false,"NOT_OWNER" end
    if not M.near(player) then return false,"OUT_OF_RANGE" end
    if cmp._editlock then return false,"BUSY" end
    if cmp.data.config_revision~=revision then return false,"STALE_REVISION" end
    if not U.finite(slot) or slot~=math.floor(slot) or slot<1 or slot>cmp.data.stats.capacity then return false,"INVALID_SLOT" end
    local sourceinv=inv
    local inputslot=source and inv:GetItemSlot(source)
    if source and not cursor and not inputslot and inv.GetOverflowContainer then
        local bag=inv:GetOverflowContainer()
        if bag then inputslot=bag:GetItemSlot(source);if inputslot then sourceinv=bag end end
    end
    if cursor and inv:GetActiveItem()~=source then return false,"CARD_MISSING" end
    if source and (not source:HasTag("nw_spellcard") or (not cursor and not inputslot) or not require("nw/cards").codes[source.spell_id]) then return false,"CARD_MISSING" end
    if source and not require("nw/cards").playable[source.spell_id] then return false,"UNSUPPORTED_CARD" end
    local old=cmp.data.cards[slot]
    if not source and not old then return true end
    local split=source and source.components and source.components.stackable and source.components.stackable:IsStack()
    local outputslot=not split and inputslot or nil
    local outputinv=outputslot and sourceinv or inv
    cmp._editlock=true
    local output
    if old then
        output=SpawnPrefab("nw_spellcard")
        if not output then cmp._editlock=nil;return false,"SPAWN_FAILED" end
        if not require("nw/cards").codes[old.spell_id] then output:Remove();cmp._editlock=nil;return false,"UNSUPPORTED_CARD" end
        output:SetSpell(old.spell_id)
        output.card_uid, output.source = old.card_uid, old.source
    end
    if split then
        source=inv:RemoveItem(source,false)
        if not source then
            if output then output:Remove() end
            cmp._editlock=nil;return false,"CARD_MISSING"
        end
    end
    if source and not split and inv:RemoveItem(source,true)~=source then
        if output then output:Remove() end
        cmp._editlock=nil;return false,"CARD_MISSING"
    end
    local function give(item)
        if cursor and not split then
            inv:GiveActiveItem(item)
            return inv:GetActiveItem()==item
        end
        -- Match native container-to-inventory transfers: GiveItem owns stack
        -- merging and overflow selection. A full destination must return the
        -- card to its source instead of dropping it or putting it on the cursor.
        local ignorefull=inv.ignorefull
        inv.ignorefull=true
        local accepted=outputinv:GiveItem(item,outputslot,nil,false)
        inv.ignorefull=ignorefull
        return accepted and true or false
    end
    if output and not give(output) then
        output:Remove()
        if source then
            if split then inv:GiveItem(source) else give(source) end
        end
        cmp._editlock=nil;return false,"INVENTORY_FULL"
    end
    cmp:UpdateTime()
    local previous=cmp.data.runtime
    cmp.data.cards[slot]=source and {card_uid=require("nw/card_identity").unique(cmp.data.cards,source:GetCardUID()),spell_id=source.spell_id,source=source.source} or false
    if source then source:Remove() end
    local runtime=C.initial(cmp.data.cards,cmp.data.stats,previous.rng_state)
    runtime.mana=previous.mana
    runtime.remaining_cast=previous.remaining_cast
    runtime.remaining_recharge=math.max(previous.remaining_recharge,cmp.data.stats.recharge)
    cmp.data.runtime=runtime;cmp.data.config_revision=revision+1
    cmp._editlock=nil;cmp:Sync()
    return true
end
return M
