local C=require("nw/constants/journal")
local Cards=require("nw/cards")
local U=require("nw/util")
local METRICS=U.copy(C.metrics)
local WINDOWS=U.copy(C.windows)
local RATE=C.bucket_rate
local LIMIT=C.max_value
local function number(n) return U.finite(n) and math.max(0,math.min(LIMIT,n)) or 0 end
local function add(a,b) return math.min(LIMIT,a+b) end
local function spell(id)
    id=Cards.migrate_id(id)
    return Cards.codes[id] and id or nil
end
local function text(s,max) return type(s)=="string" and #s<=max and s or nil end
local function timestamp()
    local at={unix=os.time()}
    local state=TheWorld and TheWorld.state
    if state and U.finite(state.cycles) then
        at.world_day=state.cycles+1+(U.finite(state.time) and state.time or 0)
    end
    if TheShard and TheShard.GetShardId then at.shard=tostring(TheShard:GetShardId()) end
    return at
end
local function readtime(at)
    if type(at)~="table" then return end
    local clean={}
    if U.finite(at.unix) and at.unix>=0 and at.unix<=LIMIT then clean.unix=math.floor(at.unix) end
    if U.finite(at.world_day) and at.world_day>=0 and at.world_day<=LIMIT then clean.world_day=at.world_day end
    clean.shard=text(at.shard,C.snapshot.shard_length)
    return (clean.unix or clean.world_day) and clean or nil
end
local function increment(row,key,n,at,times)
    local old=row[key] or 0
    row[key]=add(old,n)
    if row[key]>old then
        if times then times[key]=at else row[key.."_at"]=at end
    end
    return old
end
local function snapshot(data,name,custom)
    if type(data)~="table" or type(data.stats)~="table" then return end
    local uid=text(data.wand_uid,C.snapshot.wand_uid_length)
    if not uid or uid=="" then return end
    local s={}
    for key in pairs(METRICS) do
        if not U.finite(data.stats[key]) then return end
        s[key]=data.stats[key]
    end
    s.shuffle=data.stats.shuffle==true
    local result={wand_uid=uid,stats=s,name=text(name,C.snapshot.name_length),custom_name=custom==true,
        tier=number(data.tier),seed=number(data.seed),source=text(data.source,C.snapshot.source_length),
        archetype=text(data.archetype,C.snapshot.archetype_length),always_cast=spell(data.always_cast),cards={},broken=data.broken==true,
        generator_version=number(data.generator_version)}
    result.appearance={}
    for _,key in ipairs({"appearance_schema","roll","shaft_style","head_id","body_id","tail_id","length_class"}) do
        local v=type(data.appearance)=="table" and data.appearance[key]
        if U.finite(v) or text(v,C.snapshot.appearance_length) then
            result.appearance[key]=v
        end
    end
    for i=1,math.min(C.snapshot.max_cards,math.max(0,math.floor(s.capacity))) do
        local card=data.cards and data.cards[i]
        result.cards[i]=spell(type(card)=="table" and card.spell_id or card) or false
    end
    for _,key in ipairs({"first_seen_at","updated_at","renamed_at"}) do result[key]=readtime(data[key]) end
    if type(data.stats_at)=="table" then
        result.stats_at={}
        for key in pairs(METRICS) do result.stats_at[key]=readtime(data.stats_at[key]) end
    end
    return result
end
local function readrecord(record)
    if type(record)~="table" then return end
    return {at=readtime(record.at),wand=type(record.wand)=="table" and
        snapshot(record.wand,record.wand.name,record.wand.custom_name) or nil}
end
local Journal=Class(function(self,inst)
    self.inst=inst
    self.cards={}
    self.casts=0;self.damage=0;self.hits=0;self.max_hit=0
    self.best_damage={};self.wands={};self.leaders={}
    self.times={};self.best_damage_records={};self.max_hit_record=nil
    self._buckets={};self._sums={}
    self._observed=setmetatable({},{__mode="k"})
end)
Journal.metrics=METRICS
Journal.windows=WINDOWS
function Journal:Card(id)
    id=spell(id)
    if not id then return end
    if not self.cards[id] then self.cards[id]={} end
    return self.cards[id]
end
function Journal:Collect(id)
    local row=self:Card(id)
    if row and not row.collected then
        row.collected=true;row.collected_at=timestamp()
        self.times.collected=row.collected_at
    end
end
function Journal:RecordCast(data,plan)
    local at=timestamp()
    increment(self,"casts",1,at,self.times)
    local function used(row)
        if not row then return end
        if increment(row,"casts",1,at)==0 then row.used_at=at;self.times.used=at end
    end
    local byuid,seen={},{}
    for _,card in pairs(data.cards or {}) do
        if type(card)=="table" then byuid[card.card_uid]=card.spell_id end
    end
    for _,event in ipairs(plan.trace or {}) do
        if event.event=="execute" and not seen[event.card] then
            seen[event.card]=true
            local row=self:Card(byuid[event.card])
            used(row)
        end
    end
    local row=self:Card(data.always_cast)
    used(row)
end
function Journal:HeldWandSnapshot()
    local inv=self.inst.components and self.inst.components.inventory
    local item=inv and inv.GetEquippedItem and EQUIPSLOTS and inv:GetEquippedItem(EQUIPSLOTS.HANDS)
    if not item or item.IsValid and not item:IsValid() then return end
    local c=item.components
    local data=c and c.nw_wand and c.nw_wand.data
    return data and snapshot(data,c.named and c.named.name,item.HasTag and item:HasTag("nw_customname")) or nil
end
function Journal:RecordDamage(id,amount,now)
    id=spell(id)
    if not id or not U.finite(amount) or amount<=0 then return end
    local definition=require("nw/definitions").spells[id]
    if not definition or definition.kind=="modifier" or definition.kind=="multicast" then return end
    amount=math.min(LIMIT,amount)
    local at=timestamp()
    local captured,held=false,nil
    local function achievement()
        if not captured then held=self:HeldWandSnapshot();captured=true end
        return {at=at,wand=held}
    end
    local row=self:Card(id)
    if increment(row,"damage",amount,at)==0 then row.damage_first_at=at end
    increment(self,"damage",amount,at,self.times);increment(self,"hits",1,at,self.times)
    if amount>self.max_hit then self.max_hit=amount;self.max_hit_record=achievement() end
    local tick=math.floor((now or GetTime())*RATE+C.tick_epsilon)
    if not self._tick or tick<self._tick or tick-self._tick>=C.max_window*RATE then
        self._buckets={};self._sums={}
    else
        for t=self._tick+1,tick do
            for _,seconds in ipairs(WINDOWS) do
                self._sums[seconds]=math.max(0,(self._sums[seconds] or 0)-(self._buckets[t-seconds*RATE] or 0))
            end
            self._buckets[t-C.max_window*RATE]=nil
        end
    end
    self._tick=tick
    self._buckets[tick]=(self._buckets[tick] or 0)+amount
    for _,seconds in ipairs(WINDOWS) do
        self._sums[seconds]=(self._sums[seconds] or 0)+amount
        if self._sums[seconds]>(self.best_damage[seconds] or 0) then
            self.best_damage[seconds]=self._sums[seconds]
            self.best_damage_records[seconds]=achievement()
        end
    end
end
function Journal:RankWand(row)
    local id=row.wand_uid
    self.wands[id]=row
    local keep={}
    for metric,direction in pairs(METRICS) do
        local candidates={}
        for uid in pairs(self.wands) do candidates[#candidates+1]=uid end
        table.sort(candidates,function(a,b)
            local av,bv=self.wands[a].stats[metric],self.wands[b].stats[metric]
            if av~=bv then return av*direction>bv*direction end
            return a<b
        end)
        local leaders={}
        for i=1,math.min(C.leaders_per_metric,#candidates) do leaders[i]=candidates[i];keep[candidates[i]]=true end
        self.leaders[metric]=leaders
    end
    for uid in pairs(self.wands) do if not keep[uid] then self.wands[uid]=nil end end
end
function Journal:ObserveWand(inst)
    local wand=inst.components and inst.components.nw_wand
    local data=wand and wand.data
    local name=inst.components.named and inst.components.named.name
    local old=self._observed[inst]
    if data and old and old.data==data and old.revision==data.config_revision and old.name==name then return end
    local row=wand and snapshot(wand.data,inst.components.named and inst.components.named.name,
        inst.HasTag and inst:HasTag("nw_customname"))
    if row then
        local previous=self.wands[row.wand_uid]
        local at=timestamp()
        row.updated_at=at;row.stats_at={}
        if previous then
            row.first_seen_at=previous.first_seen_at
            row.renamed_at=previous.renamed_at
        else row.first_seen_at=at end
        for key in pairs(METRICS) do
            if previous and previous.stats[key]==row.stats[key] then
                row.stats_at[key]=previous.stats_at and previous.stats_at[key]
            else row.stats_at[key]=at end
        end
        if previous and previous.name~=row.name and row.custom_name then row.renamed_at=at end
        self:RankWand(row)
        self._observed[inst]={data=data,revision=data.config_revision,name=name}
    end
end
function Journal:RenameWand(uid,name)
    local row=self.wands[uid]
    if row and text(name,C.snapshot.name_length) then
        row.name=name;row.custom_name=true;row.renamed_at=timestamp();row.updated_at=row.renamed_at
    end
end
function Journal:GetCard(id)
    return U.copy(self.cards[spell(id)] or {})
end
function Journal:GetSummary()
    local collected,used=0,0
    for _,row in pairs(self.cards) do
        if row.collected then collected=collected+1 end
        if (row.casts or 0)>0 then used=used+1 end
    end
    return {collected=collected,used=used,total=#Cards.order,casts=self.casts,damage=self.damage,
        hits=self.hits,max_hit=self.max_hit,best_damage=U.copy(self.best_damage),times=U.copy(self.times),
        max_hit_record=U.copy(self.max_hit_record),best_damage_records=U.copy(self.best_damage_records)}
end
function Journal:GetDamageRecord(seconds)
    local record
    if seconds~=nil then record=self.best_damage_records[seconds] else record=self.max_hit_record end
    return {damage=seconds and (self.best_damage[seconds] or 0) or self.max_hit,
        at=U.copy(record and record.at),wand=U.copy(record and record.wand)}
end
function Journal:GetTopWands(metric)
    local rows={}
    for _,uid in ipairs(self.leaders[metric] or {}) do rows[#rows+1]=U.copy(self.wands[uid]) end
    return rows
end
function Journal:OnSave()
    return U.copy({version=2,cards=self.cards,casts=self.casts,damage=self.damage,hits=self.hits,
        max_hit=self.max_hit,best_damage=self.best_damage,wands=self.wands,times=self.times,
        max_hit_record=self.max_hit_record,best_damage_records=self.best_damage_records})
end
function Journal:OnLoad(data)
    if type(data)~="table" or (data.version~=1 and data.version~=2) then return end
    self.cards={};self.wands={};self.leaders={};self.best_damage={}
    self.times={};self.best_damage_records={};self.max_hit_record=nil
    for id,row in pairs(type(data.cards)=="table" and data.cards or {}) do
        local record=type(row)=="table" and self:Card(id)
        if record then
            record.collected=row.collected==true or nil
            record.casts=number(row.casts)>0 and math.floor(number(row.casts)) or nil
            record.damage=number(row.damage)>0 and number(row.damage) or nil
            if data.version==2 then
                for _,key in ipairs({"collected_at","used_at","casts_at","damage_at","damage_first_at"}) do
                    record[key]=readtime(row[key])
                end
            end
        end
    end
    for _,key in ipairs({"casts","damage","hits","max_hit"}) do self[key]=number(data[key]) end
    if data.version==2 then
        for _,key in ipairs({"collected","used","casts","damage","hits"}) do
            self.times[key]=readtime(type(data.times)=="table" and data.times[key])
        end
        self.max_hit_record=readrecord(data.max_hit_record)
    end
    for _,seconds in ipairs(WINDOWS) do
        self.best_damage[seconds]=number(type(data.best_damage)=="table" and data.best_damage[seconds])
        if data.version==2 and type(data.best_damage_records)=="table" then
            self.best_damage_records[seconds]=readrecord(data.best_damage_records[seconds])
        end
    end
    for _,row in pairs(type(data.wands)=="table" and data.wands or {}) do
        if type(row)=="table" then
            local clean=snapshot(row,row.name,row.custom_name)
            if clean then self:RankWand(clean) end
        end
    end
    self._tick=nil;self._buckets={};self._sums={}
    self._observed=setmetatable({},{__mode="k"})
end
return Journal
