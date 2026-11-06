local Protocol=require("nw/edit_protocol")
local Client=require("nw/editor_client")
local Compiler=require("nw/compiler")
local Generator=require("nw/generator")
EQUIPSLOTS={HANDS="hands"}
local now=0;GetTime=function() return now end
local near=true;TheSim={FindEntities=function() return near and {true} or {} end}
local function network(id) return {GetNetworkID=function() return id end} end
local function card(guid,id,spell)
    return {GUID=guid,Network=network(id),spell_id=spell,valid=true,
        HasTag=function(_,tag) return tag=="nw_spellcard" end,GetCardUID=function() return "test:"..guid end,
        SetSpell=function(self,s) self.spell_id=s end,Remove=function(self) self.valid=false end}
end
local nextid=100
SpawnPrefab=function() nextid=nextid+1;return card(900+nextid,nextid,"spark") end
local data=Generator.starter()
data.cards={{card_uid="a",spell_id="spark"},false,false,false}
data.config_revision=1;data.runtime=Compiler.initial(data.cards,data.stats,1)
local clientwand={GUID=11,Network=network(77),_nw_revision={value=function() return data.config_revision end}}
local serverwand={GUID=901,Network=network(77),components={nw_wand={data=data,UpdateTime=function() end,Sync=function() end}}}
local clientcard=card(12,88,"arrow")
local servercard=card(902,88,"arrow")
assert(clientwand.GUID~=serverwand.GUID and clientcard.GUID~=servercard.GUID)
local slots={servercard}
local equipped=serverwand
local inv={maxslots=2,GetEquippedItem=function() return equipped end,GetItemInSlot=function(_,i) return slots[i] end}
function inv:GetItemSlot(item) for i,v in pairs(slots) do if v==item then return i end end end
function inv:RemoveItem(item) local i=self:GetItemSlot(item);if i then slots[i]=nil;return item end end
function inv:GiveItem(item,i) if slots[i] then return false end;slots[i]=item;return true end
local player={userid="test",components={inventory=inv,health={IsDead=function() return false end}},Transform={GetWorldPosition=function() return 0,0,0 end}}
ThePlayer={}
MOD_RPC={nw_weave={edit="edit"}};CLIENT_MOD_RPC={nw_weave={edit_result="result"}}
local request_payload,delay=false,false
SendModRPCToServer=function(rpc,...)
    assert(rpc=="edit");request_payload={...}
    if not delay then Protocol.handle(player,...) end
end
SendModRPCToClient=function(rpc,userid,...)
    assert(rpc=="result" and userid=="test");Client.result(...)
end
local id,canedit=Protocol.focus(player);assert(id==77 and canedit)
assert(player._nw_edit_until>now)
Protocol.focus(player,false);assert(player._nw_edit_until==0)
Protocol.focus(player);assert(player._nw_edit_until>now)
Client.status(id,canedit)
local range=Client.text(ThePlayer,clientwand);assert(range=="已靠近奥术台 · 可以编辑")
assert(Client.submit(ThePlayer,clientwand,1,clientcard))
assert(request_payload[2]==88 and request_payload[4]==77) -- No local GUID crosses the boundary.
assert(data.cards[1].spell_id=="arrow" and not servercard.valid and slots[1].spell_id=="spark")
assert(ThePlayer._nw_edit_request.code=="OK" and ThePlayer._nw_edit_request.done)
local _,feedback=Client.text(ThePlayer,clientwand);assert(feedback==Protocol.messages.OK)
now=.2
local ok,err=Protocol.handle(player,unpack(request_payload))
assert(not ok and err=="CARD_MISSING") -- Replaying the consumed input cannot duplicate cards.
local available=slots[1]
local second=card(13,Protocol.id(available),available.spell_id)
near=false;now=.4
id,canedit=Protocol.focus(player);Client.status(id,canedit)
assert(Client.text(ThePlayer,clientwand)=="未检测到附近奥术台")
Client.submit(ThePlayer,clientwand,1,second)
assert(ThePlayer._nw_edit_request.code=="OUT_OF_RANGE" and available.valid and data.cards[1].spell_id=="arrow")
near=true;now=.6
Client.submit(ThePlayer,clientwand,1,nil)
assert(data.cards[1]==false and slots[2].spell_id=="arrow")
now=.8
ok,err=Protocol.request(player,1,Protocol.id(available),data.config_revision,11)
assert(not ok and err=="WAND_CHANGED") -- Passing the client GUID is rejected, explicitly.
ok,err=Protocol.request(player,1,9999,data.config_revision,77);assert(not ok and err=="CARD_MISSING")
now=1
ok,err=Protocol.request(player,1,Protocol.id(available),1,77);assert(not ok and err=="STALE_REVISION")
now=1.2
ok,err=Protocol.request(player,1,0/0,data.config_revision,77);assert(not ok and err=="INVALID_REQUEST")
equipped=nil
ok,err=Protocol.request(player,1,0,data.config_revision,77);assert(not ok and err=="NOT_OWNER")
equipped=serverwand
delay=true;now=2
assert(Client.submit(ThePlayer,clientwand,1,second))
assert(not Client.submit(ThePlayer,clientwand,1,second))
local pending=ThePlayer._nw_edit_request
Client.result(pending.id-1,77,true,"OK");assert(not pending.done)
Client.result(pending.id,123,true,"OK");assert(not pending.done)
now=6
range,feedback=Client.text(ThePlayer,clientwand)
assert(range=="正在确认奥术台距离…" and string.find(feedback,"未收到服务器回复",1,true))
assert(Client.submit(ThePlayer,clientwand,1,second))
print("edit protocol: distinct client/server GUIDs, network IDs, request/reply, ownership, stale/moved cards, range, removal, timeout and stale replies")
