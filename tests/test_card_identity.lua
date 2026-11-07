Class=function(ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...) local o=setmetatable({},cls);ctor(o,...);return o end})
end
TheNet={GetSessionIdentifier=function() return "session" end}
TheShard={GetShardId=function() return "1" end}
local I=require("components/nw_identity")
local identity=I({});TheWorld.components.nw_identity=identity
identity:OnLoad({sequence=1292})
identity:Observe("nw:session:1:1293")
assert(identity:Next()=="nw:session:1:1294","late saved cards must advance the allocator")
identity:OnLoad({sequence=1200})
assert(identity:Next()=="nw:session:1:1295","world load must not undo observed IDs")
identity:Observe("nw:other:1:999999");identity:Observe("nw:session:2:999999")
assert(identity:Next()=="nw:session:1:1296","foreign shards have independent namespaces")
local C=require("nw/compiler")
local w=require("nw/generator").starter()
w.stats.capacity=12;w.stats.mana_max=600;w.stats.draw_count=1;w.stats.shuffle=false
local ids={"giant_shot",false,"repeat_2","repeat_3","repeat_2","repeat_2","orbit","trident_cast",false,"fire","frost","fire"}
w.cards={}
for i,id in ipairs(ids) do w.cards[i]=id and {card_uid="nw:session:1:"..(1400+i),spell_id=id,source="kept"} or false end
w.cards[7].card_uid=w.cards[1].card_uid
w.runtime=C.initial(w.cards,w.stats,43);w.runtime.remaining_cast=1.25;w.runtime.remaining_recharge=.6
local plan,err=C.compile(w);assert(not plan and err=="DUPLICATE_CARD")
local repair=require("nw/card_identity")
assert(repair.repair(w))
assert(w.cards[1].card_uid=="nw:session:1:1401" and w.cards[7].card_uid=="nw:session:1:1413")
for i,id in ipairs(ids) do assert((w.cards[i] and w.cards[i].spell_id or false)==id) end
assert(w.runtime.mana==600 and w.runtime.remaining_cast==1.25 and w.runtime.remaining_recharge==.6)
plan=assert(C.compile(w));assert(plan.mana_required==223 and plan.projectile_count==72)
local revision=w.config_revision;assert(not repair.repair(w) and w.config_revision==revision)
assert(repair.unique(w.cards,w.cards[1].card_uid)~=w.cards[1].card_uid,"inserting a conflicting saved card must rekey it")
local Status=require("nw/cast_status")
assert(Status.reason(nil,"DUPLICATE_CARD")=="DUPLICATE_CARD")
assert(Status.reason({projectile_count=0,trace={{event="skip_mana"}}})=="NO_MANA")
assert(Status.reason({projectile_count=0,trace={}})=="NO_PROJECTILES")
assert(Status.tip("DUPLICATE_CARD")~=Status.tip("NO_MANA"))
local empty=require("nw/generator").starter()
empty.cards={false,false};empty.wand_uid="nw:session:1:9000"
empty.runtime=C.initial(empty.cards,empty.stats,1)
assert(not repair.repair(empty))
assert(identity:Next()=="nw:session:1:9001","an empty wand's own ID must advance the allocator")
w.cards[1].card_uid=nil;w.cards[3].card_uid="";w.cards[4].card_uid=45
assert(repair.repair(w))
plan=assert(C.compile(w));assert(plan.mana_spent==223 and plan.projectile_count==72)
assert(w.cards[1].spell_id=="giant_shot" and w.cards[3].spell_id=="repeat_2" and w.cards[4].spell_id=="repeat_3")
assert(identity:Next()=="nw:session:1:9005")
print("card identity: late-save high water, duplicate repair without card/resource loss, insertion collisions and precise cast reasons")
