local U=require("nw/util")
local now=0
GetTime=function() return now end
Class=function(fn)
    local c={};c.__index=c
    return setmetatable(c,{__call=function(_,...) local s=setmetatable({},c);fn(s,...);return s end})
end
local Journal=require("components/nw_spelljournal")
local Hooks=require("nw/spelljournal")
local Damage=require("nw/journal_damage")
local C=require("nw/compiler")
local function player()
    local p={components={}}
    p.components.nw_spelljournal=Journal(p)
    return p
end
local p=player();local j=p.components.nw_spelljournal
local function wand(ids)
    local data=require("nw/generator").starter()
    data.wand_uid="wand:1";data.config_revision=1
    data.stats.mana_max=1200;data.stats.capacity=12
    data.cards={}
    for i,id in ipairs(ids) do data.cards[i]={card_uid="c:"..i,spell_id=id} end
    data.runtime=C.initial(data.cards,data.stats,1)
    local inst={components={nw_wand={data=data},named={name="test"}},HasTag=function() return false end}
    return inst,data
end
local w,data=wand({"double","spark_hit","damage_up","arrow"})
local bag={components={container={slots={w,{prefab="nw_spellcard",spell_id="fire",components={}}}}}}
Hooks.observe(p,bag)
assert(j:GetSummary().collected==5 and j:GetCard("fire").collected)
Hooks.observe(p,bag);assert(j:GetSummary().collected==5)
local plan=assert(C.compile(data))
assert(plan.blocks[1].projectiles[1].journal_id=="spark_hit" and plan.blocks[2].projectiles[1].journal_id=="arrow")
assert(j.casts==0 and not j:GetCard("arrow").casts,"preview must not count")
j:RecordCast(data,plan)
for _,id in ipairs({"double","spark_hit","damage_up","arrow"}) do assert(j:GetCard(id).casts==1,id) end
assert(j.casts==1 and not j:GetCard("fire").casts)
local _,same=wand({"double","spark","spark"})
j:RecordCast(same,assert(C.compile(same)))
assert(j:GetCard("spark").casts==2,"different physical cards count independently")
local repeated=U.copy(plan)
repeated.trace[#repeated.trace+1]=U.copy(repeated.trace[1])
j:RecordCast(data,repeated)
assert(j:GetCard("double").casts==3,"same UID counted once per cast")
local _,poor=wand({"damage_up","spark"})
poor.runtime.mana=5
j:RecordCast(poor,assert(C.compile(poor)))
assert(j:GetCard("damage_up").casts==2,"unaffordable modifier does not count")
poor.always_cast="precision"
j:RecordCast(poor,assert(C.compile(poor)))
assert(j:GetCard("precision").casts==1 and not j:GetCard("precision").collected)

-- Actual health loss: armour/overkill/blocked/healing and native adapter.
Damage.loss(p,{id="spark"},{currenthealth=-50},10)
Damage.loss(p,{id="arrow"},{currenthealth=80},100)
Damage.loss(p,{id="arrow"},{currenthealth=100},100)
Damage.loss(p,{id="arrow"},{currenthealth=110},100)
Damage.record(p,{id="damage_up"},50)
assert(j.damage==30 and j:GetCard("spark").damage==10 and not j:GetCard("damage_up").damage)
Damage.record(p,{id="fire",journal_id="spore_sentry"},7)
assert(j:GetCard("spore_sentry").damage==7 and not j:GetCard("fire").damage)
TheWorld.ismastersim=true
local adapter
Damage.install({AddComponentPostInit=function(name,fn) assert(name=="combat");adapter=fn end})
local health={currenthealth=100}
local combat={inst={components={health=health}}}
function combat:GetAttacked_Internal(a,n) health.currenthealth=health.currenthealth-n*.5;return "result" end
function combat:GetAttacked(...) return self:GetAttacked_Internal(...) end
adapter(combat)
local weapon={};Damage.tag(weapon,p,{id="edge_trident"})
assert(combat:GetAttacked({},20,weapon)=="result")
combat:GetAttacked_Internal({},20,weapon) -- DoAttack's native direct entry
assert(j:GetCard("edge_trident").damage==20)
combat:GetAttacked({},20,{})
assert(j:GetCard("edge_trident").damage==20,"ordinary weapons not counted")

local victim={components={health={currenthealth=80,IsDead=function() return false end}},
    IsValid=function() return true end,IsInLimbo=function() return false end,HasTag=function() return false end}
victim.components.combat={GetAttacked=function(_,_,n) victim.components.health.currenthealth=victim.components.health.currenthealth-n end}
p.IsValid=function() return true end
p.components.combat={CanTarget=function() return true end,IsAlly=function() return false end}
local damage_before=j:GetCard("spark").damage
require("nw/targeting").damage(p,victim,12,{},plan.blocks[1].projectiles[1])
assert(j:GetCard("spark_hit").damage==12 and j:GetCard("spark").damage==damage_before,
    "simple projectiles keep their trigger variant attribution")

-- Sliding records match a bucket oracle over boundaries, idle gaps and clock reset.
local rolling=Journal({})
local samples={}
for i=1,2500 do
    local t=i*.017
    local amount=i%9+1
    rolling:RecordDamage("spark",amount,t)
    samples[#samples+1]={tick=math.floor(t*10+1e-6),amount=amount}
    for _,seconds in ipairs(Journal.windows) do
        local total=0
        for _,hit in ipairs(samples) do
            if hit.tick>math.floor(t*10+1e-6)-seconds*10 then total=total+hit.amount end
        end
        assert(math.abs(rolling._sums[seconds]-total)<.0001,"rolling window mismatch")
    end
end
local count=0;for _ in pairs(rolling._buckets) do count=count+1 end
assert(count<=100)
rolling:RecordDamage("spark",5,1000);assert(rolling._sums[10]==5)
rolling:RecordDamage("spark",3,1);assert(rolling._sums[10]==3)
rolling:RecordDamage("spark",0/0,1);assert(rolling._sums[10]==3)
local saved=rolling:OnSave();assert(not saved._buckets)
local restored=Journal({});restored:OnLoad(saved)
assert(restored.best_damage[10]==rolling.best_damage[10] and not restored._tick)
restored:RecordDamage("spark",2,1);assert(restored._sums[10]==2)

-- Top-three ranks, stable ties, deduplicated immutable snapshots, renamed and reloaded.
local ranked=Journal({})
local all={}
for i=1,100 do
    local item,d=wand({"spark"})
    d.wand_uid="rank:"..i;d.stats.mana_max=i;d.stats.cast_delay=101-i
    item.components.named.name="wand "..i
    ranked:ObserveWand(item);all[#all+1]=item
end
assert(ranked:GetTopWands("mana_max")[1].wand_uid=="rank:100")
assert(ranked:GetTopWands("cast_delay")[3].stats.cast_delay==3)
count=0;for _ in pairs(ranked.wands) do count=count+1 end
assert(count<=24,"bounded snapshots")
ranked:RenameWand("rank:100","星火")
assert(ranked:GetTopWands("mana_max")[1].name=="星火")
all[100].components.nw_wand.data.cards[1].spell_id="fire"
assert(ranked:GetTopWands("mana_max")[1].cards[1]=="spark","snapshot must not retain live data")
local copy=ranked:GetTopWands("mana_max");copy[1].name="mutation"
assert(ranked:GetTopWands("mana_max")[1].name=="星火")
local r=Journal({});r:OnLoad(ranked:OnSave())
assert(r:GetTopWands("mana_max")[1].name=="星火" and r:GetTopWands("mana_max")[1].cards[1]=="spark")
local malformed={version=1,casts=0/0,cards={nonsense={collected=true},spark={casts=-3,damage=math.huge}},
    wands={bad={wand_uid="bad",stats={}}}}
r:OnLoad(malformed);assert(r.casts==0 and r:GetSummary().collected==0 and next(r.wands)==nil)

-- Inventory/backpack ownership and reroll hooks; ground chests don't unlock cards.
local init,container_init
Hooks.install({AddPlayerPostInit=function(fn) init=fn end,
    AddComponentPostInit=function(name,fn) assert(name=="container");container_init=fn end})
local function events(e)
    e.events={}
    function e:ListenForEvent(name,fn) self.events[name]=fn end
    function e:DoTaskInTime(_,fn) self.pending=fn end
    function e:AddComponent(name) self.components[name]=Journal(self) end
    return e
end
local live=events({components={inventory={itemslots={},equipslots={}}}})
init(live)
local card={prefab="nw_spellcard",spell_id="frost",components={}}
local pack=events({components={inventoryitem={GetGrandOwner=function() return live end}}})
container_init({inst=pack});pack.events.itemget(pack,{item=card})
assert(live.components.nw_spelljournal:GetCard("frost").collected)
pack.components.inventoryitem.GetGrandOwner=function() return nil end
card.spell_id="heavy";pack.events.itemget(pack,{item=card})
assert(not live.components.nw_spelljournal:GetCard("heavy").collected)
live.components.inventory.itemslots[1]=card;live.pending()
assert(live.components.nw_spelljournal:GetCard("heavy").collected)
local reroll=live:SaveForReroll()
local nextplayer=events({components={inventory={}}});init(nextplayer);nextplayer:LoadForReroll(reroll)
assert(nextplayer.components.nw_spelljournal:GetCard("frost").collected)
print("spell journal: collection, physical-card dedup, mana skips, native damage, sliding windows, bounded ranks, save/reroll")

-- Achievement timestamps and equipment AT THE HIT, including delayed spells.
local oldtime=os.time
local wall=1700000000
os.time=function() return wall end
TheWorld.state={cycles=9,time=.25}
TheShard={GetShardId=function() return "Caves" end}
EQUIPSLOTS={HANDS="hands"}
local timedplayer=player()
local timed=timedplayer.components.nw_spelljournal
local hand
timedplayer.components.inventory={GetEquippedItem=function(_,slot) assert(slot=="hands");return hand end}
local a,ad=wand({"spark"});ad.wand_uid="achievement:a";a.components.named.name="A"
local b,bd=wand({"arrow"});bd.wand_uid="achievement:b";b.components.named.name="B"
timed:Collect("frost")
local first=timed:GetCard("frost").collected_at
assert(first.unix==wall and first.world_day==10.25 and first.shard=="Caves")
wall=wall+1;timed:Collect("frost")
assert(timed:GetCard("frost").collected_at.unix==first.unix and timed.times.collected.unix==first.unix)
wall=wall+1;timed:RecordCast(ad,assert(C.compile(ad)))
local used_at=timed:GetCard("spark").used_at.unix
wall=wall+1;timed:RecordCast(ad,assert(C.compile(ad)))
assert(timed:GetCard("spark").used_at.unix==used_at and timed:GetCard("spark").casts_at.unix==wall)
assert(timed.times.used.unix==used_at and timed.times.casts.unix==wall)

wall=wall+1;hand=a;timed:RecordDamage("spark",10,0)
local hit=timed:GetDamageRecord()
assert(hit.damage==10 and hit.at.unix==wall and hit.wand.wand_uid==ad.wand_uid)
ad.cards[1].spell_id="fire";a.components.named.name="A changed"
assert(timed:GetDamageRecord().wand.cards[1]=="spark" and timed:GetDamageRecord().wand.name=="A")
wall=wall+1;hand=b;timed:RecordDamage("spark",20,.5)
assert(timed:GetDamageRecord().wand.wand_uid==bd.wand_uid,"delayed spell must record current B, not casting A")
for _,seconds in ipairs(Journal.windows) do
    local record=timed:GetDamageRecord(seconds)
    assert(record.damage==30 and record.at.unix==wall and record.wand.wand_uid==bd.wand_uid)
end
wall=wall+1;hand=nil
timedplayer.components.inventory.itemslots={a,b} -- inventory is not the hand slot
timed:RecordDamage("spark",40,1)
assert(timed:GetDamageRecord().wand==nil and timed:GetDamageRecord().at.unix==wall)
for _,seconds in ipairs(Journal.windows) do assert(timed:GetDamageRecord(seconds).wand==nil) end
wall=wall+1;hand={components={}};timed:RecordDamage("spark",80,2)
assert(timed:GetDamageRecord().wand==nil,"ordinary held items must not use last wand")
local tie_at=timed:GetDamageRecord().at.unix
wall=wall+1;hand=a;timed:RecordDamage("spark",80,20)
assert(timed:GetDamageRecord().at.unix==tie_at and not timed:GetDamageRecord().wand,"ties retain first record, even if wand absent")
wall=wall+1;hand=b;timed:RecordDamage("spark",200,40)
assert(timed:GetCard("spark").damage_at.unix==wall and timed:GetCard("spark").damage_first_at.unix==first.unix+4)
assert(timed.times.damage.unix==wall and timed.times.hits.unix==wall)
for _,seconds in ipairs(Journal.windows) do
    assert(timed:GetDamageRecord(seconds).damage==200 and timed:GetDamageRecord(seconds).at.unix==wall)
end

timed:ObserveWand(b)
local seen_at=timed:GetTopWands("mana_max")[1].first_seen_at.unix
wall=wall+1;b.components.named.name="B renamed"
Hooks.renamed(b,timedplayer)
assert(timed:GetTopWands("mana_max")[1].renamed_at.unix==wall)
assert(timed:GetTopWands("mana_max")[1].stats_at.mana_max.unix==seen_at)
assert(timed:GetDamageRecord().wand.name=="B","later renames cannot rewrite achievement snapshots")
wall=wall+1;bd.stats.mana_max=bd.stats.mana_max+1;bd.config_revision=bd.config_revision+1
timed:ObserveWand(b)
assert(timed:GetTopWands("mana_max")[1].stats_at.mana_max.unix==wall)
assert(timed:GetTopWands("mana_max")[1].stats_at.cast_delay.unix==seen_at)
assert(timed:GetDamageRecord().wand.stats.mana_max==bd.stats.mana_max-1)
local full=timed:OnSave();assert(full.version==2)
wall=wall+100
local loaded=Journal(timedplayer);loaded:OnLoad(full)
assert(loaded:GetDamageRecord().at.unix==full.max_hit_record.at.unix)
assert(loaded:GetDamageRecord(5).wand.name=="B" and loaded:GetCard("frost").collected_at.unix==first.unix)
local detached=loaded:GetSummary();detached.max_hit_record.wand.name="external mutation"
assert(loaded:GetDamageRecord().wand.name=="B")
full.max_hit_record.wand.name="save mutation"
assert(loaded:GetDamageRecord().wand.name=="B")

local legacy=Journal(timedplayer)
legacy:OnLoad({version=1,cards={spark={collected=true,casts=2,damage=300}},casts=2,damage=300,hits=1,
    max_hit=300,best_damage={[1]=500,[5]=500,[10]=500}})
assert(not legacy:GetCard("spark").collected_at and not legacy:GetDamageRecord().at)
legacy:Collect("spark");assert(not legacy:GetCard("spark").collected_at,"old collection time remains unknown")
legacy:RecordDamage("spark",300,1)
assert(not legacy:GetDamageRecord().at and not legacy:GetDamageRecord(5).at,"load/equal score never invents a date")
legacy:RecordDamage("spark",301,20)
assert(legacy:GetDamageRecord().at.unix==wall and not legacy:GetDamageRecord(5).at,
    "missing window record must not fall back to max-hit metadata")
assert(legacy:OnSave().version==2 and legacy:GetCard("spark").damage_at.unix==wall)
os.time=oldtime
print("spell journal v2: first/latest times, held/switch/unequip, record ties, immutable snapshots, v1 migration and v2 roundtrip")
