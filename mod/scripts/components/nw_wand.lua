local U = require("nw/util")
local Generator = require("nw/generator")
local Compiler = require("nw/compiler")
local Balance = require("nw/balance")
local Wand = Class(function(self, inst)
    self.inst = inst
    self.data = nil
    self.last_time = GetTime()
end)
function Wand:ReadyPlan()
    local d=self.data
    if d.broken then return nil,"BROKEN" end
    local r=d.runtime
    -- Reuse the draw until a previously skipped card becomes affordable or
    -- an accepted card can no longer be paid. Cast accounts for regenerated mana.
    local mana=r.mana
    local c=self._ready_cache
    local balanced=Balance.is_balanced()
    if not c or c.runtime~=r or c.revision~=d.config_revision or c.balanced~=balanced or mana<c.low or mana>=c.high then
        local plan,err=Compiler.compile(d)
        if err=="DUPLICATE_CARD" and require("nw/card_identity").repair(d) then
            r=d.runtime
            plan,err=Compiler.compile(d)
        end
        if plan then plan._source_runtime=r;plan._config_revision=d.config_revision;plan._balanced=balanced end
        c={runtime=r,revision=d.config_revision,balanced=balanced,low=plan and plan.mana_required or math.floor(mana),
            high=plan and plan.next_afford or math.floor(mana)+1,plan=plan,err=err}
        self._ready_cache=c
    end
    return c.plan,c.err
end
function Wand:Sync()
    if not self.data then return end
    if self.inst._nw_cancast then
        local plan,err
        if self.data.runtime.remaining_cast<=.001 and self.data.runtime.remaining_recharge<=.001 then
            plan,err=self:ReadyPlan()
        else
            err="COOLDOWN"
        end
        self.inst._nw_cancast:set(plan~=nil and plan.projectile_count>0)
        if self.inst._nw_castreason then self.inst._nw_castreason:set(require("nw/cast_status").reason(plan,err)) end
    end
    self.inst._nw_capacity:set(self.data.stats.capacity)
    require("nw/wand_container").sync(self.inst)
    self.inst._nw_mana:set(math.floor(self.data.runtime.mana))
    if self.inst._nw_cards then
        if self._synced_data~=self.data or self._synced_revision~=self.data.config_revision then
            self.inst._nw_cards:set(require("nw/cards").encode(self.data.cards,self.data.stats.capacity))
            self.inst._nw_stats:set(require("nw/hover_data").encode(self.data))
            self._synced_data=self.data;self._synced_revision=self.data.config_revision
        end
        self.inst._nw_revision:set(self.data.config_revision or 1)
        self.inst._nw_maxmana:set(self.data.stats.mana_max)
        local remaining=math.max(self.data.runtime.remaining_cast,self.data.runtime.remaining_recharge)
        self.cool_total=math.max(self.cool_total or 0,remaining)
        self.inst._nw_cooldown:set(math.min(65535,math.ceil(remaining*100)))
        self.inst._nw_cooltotal:set(math.min(65535,math.ceil((self.cool_total or 0)*100)))
    end
    local look = require("nw/visual").from_data(self.data)
    local broken=self.data.broken==true
    if broken then self.inst:AddTag("nw_broken") else self.inst:RemoveTag("nw_broken") end
    if self.inst._nw_look then
        if not self.inst._nw_ready:value() or self.inst._nw_look:value() ~= look or self.inst._nw_broken and self.inst._nw_broken:value()~=broken then
            if self.inst._nw_broken then self.inst._nw_broken:set(broken) end
            self.inst._nw_look:set(look)
            self.inst.components.inventoryitem.atlasname=require("nw/visual").atlas(look)
            self.inst.components.inventoryitem:ChangeImageName(require("nw/visual").icon(look,broken))
            if self.inst._held_visual then self.inst._held_visual._look:set(look);self.inst._held_visual._broken:set(broken) end
            require("nw/visual").apply_dropped(self.inst, look)
        end
    end
    self.inst._nw_ready:set(true)
end
function Wand:InitializeNew(tier, source, theme, seed)
    if self.data then return end
    local factory = require("nw/wand_factory")
    self.data = factory.build(tier, source, theme, seed or math.random(1, 1073741823),
        theme and math.random(1,1073741823),math.random(0,require("nw/visual").cosmetic_rolls-1))
    self.inst.components.named:SetName(factory.name(self.data))
    self.last_time = GetTime()
    self:Sync()
end
-- Explicit debug fixture; normal crafting and drops use InitializeNew.
function Wand:InitializePrototype()
    if self.data then return end
    self.data = Generator.starter(math.random(0,require("nw/visual").cosmetic_rolls-1))
    self.data.stats.capacity = 4
    self.data.cards = { require("nw/wand_factory").card("spark","debug"), false, false, false }
    self.data.wand_uid = require("nw/wand_factory").uid()
    self.data.source = "debug"
    self.data.runtime = Compiler.initial(self.data.cards, self.data.stats, self.data.seed)
    self.data.config_revision = 1
    self.last_time = GetTime()
    self:Sync()
end
function Wand:UpdateTime()
    if not self.data then return end
    local now = GetTime()
    local dt = math.max(0, now - self.last_time)
    self.last_time = now
    local r, s = self.data.runtime, self.data.stats
    r.mana = math.min(s.mana_max, r.mana + dt * s.mana_regen)
    r.remaining_cast = math.max(0, r.remaining_cast - dt)
    r.remaining_recharge = math.max(0, r.remaining_recharge - dt)
    self:Sync()
end
function Wand:PreviewCast()
    self:UpdateTime()
    if not self.data then return nil, "NOT_READY" end
    if self.data.broken then return nil,"BROKEN" end
    return Compiler.compile(self.data)
end
function Wand:CanCast(doer,prepared)
    self:UpdateTime()
    if not self.data then return false,"NOT_READY" end
    if self.data.broken then return false,"BROKEN" end
    if not doer or not doer:IsValid() or not doer.components.inventory
        or doer.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS) ~= self.inst
        or not doer.components.health or doer.components.health:IsDead() then return false,"NOT_OWNER" end
    if self.data.runtime.remaining_cast > .001 or self.data.runtime.remaining_recharge > .001 then return false,"COOLDOWN" end
    local plan,err=prepared,nil
    if plan then
        if plan._source_runtime~=self.data.runtime or plan._config_revision~=self.data.config_revision
            or plan._balanced~=Balance.is_balanced() then
            return false,"STALE_CAST"
        end
        if self.data.runtime.mana<plan.mana_required then return false,"NO_MANA" end
    else
        plan,err=self:ReadyPlan()
        if not plan then return false,err end
    end
    if plan.projectile_count==0 then
        for _,event in ipairs(plan.trace) do
            if event.event=="skip_mana" then return false,"NO_MANA" end
        end
        return false,"NO_PROJECTILES"
    end
    return true,nil,plan
end
function Wand:Cast(doer,pos,prepared)
    local ok,reason,plan=self:CanCast(doer,prepared)
    if not ok then return false,reason end
    if not pos or not U.finite(pos.x) or not U.finite(pos.z) then return false,"INVALID_AIM" end
    local x,_,z=doer.Transform:GetWorldPosition()
    local dx,dz=pos.x-x,pos.z-z
    local length=math.sqrt(dx*dx+dz*dz)
    if length<.05 or length>30 then return false,"OUT_OF_RANGE" end
    dx,dz=dx/length,dz/length
    -- Keep the accepted draw decision through the wind-up. Regeneration must
    -- not make a newly affordable modifier steal mana from its planned bullet.
    -- Only commit at launch; waiting/previews never spend mana or move cards.
    plan.next_state.mana=math.min(self.data.stats.mana_max,self.data.runtime.mana-plan.mana_spent)
    local mx,my,mz=require("nw/muzzle").origin(doer,self.data.stats.capacity,dx,dz,length)
    local result,why=require("nw/executor").execute(plan,doer,mx,mz,dx,dz,my,pos)
    if not result then self.data.runtime.remaining_cast=.3;return false,why end
    local journal=doer.components.nw_spelljournal
    if journal then
        journal:RecordCast(self.data,plan)
        journal:ObserveWand(self.inst)
    end
    require("nw/dummy_trials").cast(doer,plan.mana_spent,GetTime())
    self.data.runtime=plan.next_state
    self.cool_total=plan.cooldown
    self:Sync()
    local sanity=doer.components.sanity
    local cost=math.max(.1,plan.mana_spent/Generator.sanity_conversion_for(self.data.stats))
    if sanity and sanity.current>0 then
        local paid=math.min(sanity.current,cost)
        sanity:DoDelta(-paid)
        cost=cost-paid
    end
    local hunger=doer.components.hunger
    if Balance.is_balanced() and cost>0 and hunger and hunger.current>0 then
        hunger:DoDelta(-math.min(hunger.current,cost/2))
    end
    return true
end
function Wand:SetTestLoadout(mode)
    self:InitializePrototype()
    local variants={spark={"spark"},double={"double","spark","arrow"},wrap={"spark","double","arrow"},fast={"speed_up","spark"}}
    if not variants[mode] then return false end
    self.data.stats.capacity=mode=="double" and 8 or mode=="wrap" and 12 or 4
    self.data.cards={}
    for i=1,self.data.stats.capacity do
        local id=variants[mode][i]
        self.data.cards[i]=id and require("nw/wand_factory").card(id,"debug") or false
    end
    self.data.runtime=Compiler.initial(self.data.cards,self.data.stats,self.data.seed)
    self.data.config_revision=(self.data.config_revision or 0)+1
    self.cool_total=0
    self.last_time=GetTime()
    self:Sync()
    return true
end
function Wand:OnSave()
    self:UpdateTime()
    return self.data and { wand = U.copy(self.data) } or nil
end
function Wand:OnLoad(saved)
    local d = saved and saved.wand
    if type(d) ~= "table" or d.schema_version ~= 1 or type(d.stats) ~= "table"
        or type(d.runtime) ~= "table" or type(d.cards) ~= "table" then
        return
    end
    local s, r = d.stats, d.runtime
    for _, key in ipairs({"capacity","mana_max","mana_regen","cast_delay","recharge","draw_count","spread"}) do
        if not U.finite(s[key]) then return end
    end
    if s.capacity < 2 or s.capacity > 12 or s.capacity ~= math.floor(s.capacity)
        or s.mana_max < 24 or s.mana_max > 1200 or s.mana_regen < 2 or s.mana_regen > 320
        or s.draw_count < 1 or s.draw_count > 6 or s.draw_count ~= math.floor(s.draw_count)
        or s.cast_delay < 0 or s.cast_delay > 2.4 or s.recharge < 0 or s.recharge > 6
        or s.spread < 0 or s.spread > 15 or type(s.shuffle) ~= "boolean" then return end
    if not U.finite(r.mana) or not U.finite(r.remaining_cast) or not U.finite(r.remaining_recharge)
        or not U.finite(r.reload_delta) or not U.finite(r.rng_state)
        or r.rng_state < 1 or r.rng_state > 2147483646 or r.rng_state ~= math.floor(r.rng_state)
        or type(r.deck) ~= "table" or type(r.discard) ~= "table" then return end
    if #d.cards ~= s.capacity then return end
    local ids = {}
    for _, card in ipairs(d.cards) do
        if card ~= false then
            if type(card) ~= "table" or type(card.spell_id) ~= "string"
                then return end
        end
    end
    self.data = U.copy(d)
    for _,card in ipairs(self.data.cards) do
        if card then card.spell_id=require("nw/cards").migrate_id(card.spell_id) end
    end
    if not U.finite(s.sanity_conversion) or s.sanity_conversion<=0 then
        self.data.stats.sanity_conversion=Generator.sanity_conversion
    end
    if not U.finite(self.data.config_revision) or self.data.config_revision<1
        or self.data.config_revision~=math.floor(self.data.config_revision) then self.data.config_revision=1 end
    require("nw/card_identity").repair(self.data)
    ids={}
    for _,card in ipairs(self.data.cards) do if card then ids[card.card_uid]=true end end
    r = self.data.runtime
    r.mana = math.max(0, math.min(s.mana_max, r.mana))
    r.remaining_cast = math.max(0, r.remaining_cast)
    r.remaining_recharge = math.max(0, r.remaining_recharge)
    local seen, valid = {}, true
    for _, area in ipairs({r.deck, r.discard}) do
        for _, id in ipairs(area) do
            if not ids[id] or seen[id] then valid = false end
            seen[id] = true
        end
    end
    for id in pairs(ids) do if not seen[id] then valid = false end end
    if not valid then
        local restored = Compiler.initial(self.data.cards, s, r.rng_state)
        restored.mana = r.mana
        restored.remaining_cast = r.remaining_cast
        restored.remaining_recharge = math.max(r.remaining_recharge, s.recharge)
        self.data.runtime = restored
    end
    local factory = require("nw/wand_factory")
    factory.upgrade(self.data)
    require("nw/visual").upgrade(self.data)
    self.last_time = GetTime()
    self:Sync()
end
return Wand
