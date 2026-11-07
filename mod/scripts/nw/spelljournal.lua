local M={}
function M.observe(player,item,seen)
    local journal=player and player.components and player.components.nw_spelljournal
    if not journal or not item then return end
    seen=seen or {}
    if seen[item] then return end
    seen[item]=true
    local c=item.components or {}
    if item.prefab=="nw_spellcard" then journal:Collect(item.spell_id) end
    if c.nw_wand and c.nw_wand.data then
        journal:ObserveWand(item)
        for _,card in pairs(c.nw_wand.data.cards or {}) do
            if type(card)=="table" then journal:Collect(card.spell_id) end
        end
    end
    if c.container then
        for _,child in pairs(c.container.slots or {}) do M.observe(player,child,seen) end
    end
end
function M.owner(item)
    local inv=item.components and item.components.inventoryitem
    return inv and inv:GetGrandOwner() or nil
end
function M.scan(player)
    local inv=player.components.inventory
    if not inv then return end
    local seen={}
    for _,item in pairs(inv.itemslots or {}) do M.observe(player,item,seen) end
    for _,item in pairs(inv.equipslots or {}) do M.observe(player,item,seen) end
    M.observe(player,inv.activeitem,seen)
end
function M.report(id,player)
    player=player or ConsoleCommandPlayer()
    local journal=player and player.components.nw_spelljournal
    if not journal then return end
    local function when(at)
        if not at then return "unknown" end
        local real=at.unix and os.date("!%Y-%m-%dT%H:%M:%SZ",at.unix) or "unknown"
        return real..(at.world_day and string.format(" / day %.3f",at.world_day) or "")
    end
    local result
    if id then
        local row=journal:GetCard(id)
        result=string.format("%s: collected=%s, casts=%d, damage=%.2f",id,tostring(row.collected==true),row.casts or 0,row.damage or 0)
        result=result.."\nCollected: "..when(row.collected_at).."; first used: "..when(row.used_at)
            .."\nCast count updated: "..when(row.casts_at).."; damage updated: "..when(row.damage_at)
    else
        local s=journal:GetSummary()
        result=string.format("Spell journal: collected=%d/%d, used=%d, casts=%d, damage=%.2f, hits=%d, max_hit=%.2f\nBest damage: 1s=%.2f, 5s=%.2f, 10s=%.2f",
            s.collected,s.total,s.used,s.casts,s.damage,s.hits,s.max_hit,s.best_damage[1] or 0,s.best_damage[5] or 0,s.best_damage[10] or 0)
        for _,key in ipairs({"collected","used","casts","damage","hits"}) do
            result=result.."\n"..key.." updated: "..when(s.times[key])
        end
        for _,seconds in ipairs({0,1,5,10}) do
            local best=journal:GetDamageRecord(seconds~=0 and seconds or nil)
            result=result.."\n"..(seconds==0 and "Max hit" or seconds.."s best")..": "..when(best.at)
                .."; held wand: "..(best.wand and (best.wand.name or best.wand.wand_uid) or (best.at and "none" or "unknown"))
        end
    end
    require("nw/dev_output").report(result)
    return result
end
function M.renamed(wand,doer)
    local data=wand.components.nw_wand and wand.components.nw_wand.data
    if not data then return end
    -- Refresh the actor's encounter, and update snapshots held by online peers.
    local journal=doer and doer.components.nw_spelljournal
    if journal then
        journal:ObserveWand(wand)
        journal:RenameWand(data.wand_uid,wand.components.named.name)
    end
    for _,player in ipairs(AllPlayers or {}) do
        local journal=player.components.nw_spelljournal
        if journal and player~=doer then journal:RenameWand(data.wand_uid,wand.components.named.name) end
    end
end
function M.install(env)
    env.AddPlayerPostInit(function(player)
        if not TheWorld.ismastersim then return end
        player:AddComponent("nw_spelljournal")
        local function acquired(_,data) M.observe(player,data and (data.item or data.inst)) end
        player:ListenForEvent("itemget",acquired)
        player:ListenForEvent("equip",acquired)
        player:ListenForEvent("newactiveitem",acquired)
        player:DoTaskInTime(0,function() M.scan(player) end)
        local save,load=player.SaveForReroll,player.LoadForReroll
        player.SaveForReroll=function(self,...)
            local data=save and save(self,...) or {}
            data=data or {};data.nw_spelljournal=self.components.nw_spelljournal:OnSave()
            return data
        end
        player.LoadForReroll=function(self,data,...)
            if load then load(self,data,...) end
            self.components.nw_spelljournal:OnLoad(data and data.nw_spelljournal)
            M.scan(self)
        end
    end)
    env.AddComponentPostInit("container",function(container)
        if not TheWorld.ismastersim then return end
        container.inst:ListenForEvent("itemget",function(_,data)
            M.observe(M.owner(container.inst),data and data.item)
        end)
    end)
end
return M
