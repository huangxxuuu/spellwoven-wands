local M={}
function M.valid(id) return type(id)=="string" and id~="" end
function M.observe(id)
    local identity=TheWorld.components.nw_identity
    if identity.Observe then identity:Observe(id) end
end
function M.unique(cards,id)
    local used={}
    for _,card in ipairs(cards) do
        if card and M.valid(card.card_uid) then used[card.card_uid]=true;M.observe(card.card_uid) end
    end
    M.observe(id)
    while not M.valid(id) or used[id] do id=require("nw/wand_factory").uid() end
    return id
end
function M.repair(data)
    local seen,changed={},false
    M.observe(data.wand_uid)
    for _,card in ipairs(data.cards) do if card then M.observe(card.card_uid) end end
    for _,card in ipairs(data.cards) do
        if card then
            if not M.valid(card.card_uid) or seen[card.card_uid] then
                card.card_uid=M.unique(data.cards,nil);changed=true
            end
            seen[card.card_uid]=true
        end
    end
    if changed then
        local old=data.runtime
        local state=require("nw/compiler").initial(data.cards,data.stats,old.rng_state)
        state.mana=old.mana
        state.remaining_cast=old.remaining_cast
        state.remaining_recharge=old.remaining_recharge
        state.reload_delta=old.reload_delta
        data.runtime=state
        data.config_revision=(data.config_revision or 0)+1
    end
    return changed
end
return M
