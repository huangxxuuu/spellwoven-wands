-- Input events and replicated cursor state need not arrive in the same frame.
Class=function(base) local t={};t.__index=t;return t end
package.loaded["widgets/widget"]={}
package.loaded["widgets/text"]={}
package.loaded["widgets/nw_slotrow"]={}
local calls,near,active,rev,now={},true,nil,5,0
GetTime=function() return now end
EQUIPSLOTS={HANDS=1}
local codes=require("nw/cards").codes
local function card(id)
    return {HasTag=function(_,t) return t=="nw_spellcard" end,_spell={value=function() return codes[id] end}}
end
local wand={IsValid=function() return true end,_nw_revision={value=function() return rev end}}
local inv={GetEquippedItem=function() return wand end,GetActiveItem=function() return active end}
ThePlayer={replica={inventory=inv}}
package.loaded["nw/editing"]={near=function() return near end}
package.loaded["nw/editor_client"]={submit=function(p,w,slot,item,cursor)
    assert(w==wand and cursor)
    calls[#calls+1]={slot,item}
    p._nw_edit_request={time=now}
    return true
end}
local P=require("widgets/nw_wandpanel")
local panel=setmetatable({wand=wand,shown=true,row={spells={"spark","arrow",false}}},P)
near=false;panel:Slot(1,true);assert(#calls==0)
near=true;panel:Slot(1,true);assert(#calls==1 and calls[1][1]==1 and not calls[1][2])
panel:Slot(2,false);assert(#calls==1 and panel.drop)
ThePlayer._nw_edit_request.done=true;ThePlayer._nw_edit_request.ok=true
now=.5;rev=rev+1;panel:FinishDrop();assert(#calls==1)
active=card("spark");panel:FinishDrop();assert(#calls==2 and calls[2][1]==2 and calls[2][2]==active)
panel:FinishDrop();assert(#calls==2)
local from_inventory=card("fire")
active=nil;panel:StartInventoryDrag(from_inventory);panel:Slot(3,false)
active=from_inventory;panel:FinishDrop();assert(#calls==3 and calls[3][2]==from_inventory)
active=nil;panel:StartInventoryDrag(from_inventory);panel:Slot(2,false)
near=false;active=from_inventory;panel:FinishDrop();assert(#calls==3 and not panel.drop)
near=true;active=nil;panel:Slot(1,true);panel:Slot(1,false)
assert(#calls==4 and not panel.drop,"same slot release must not install again")
print("slot drag: read-only distance, delayed result/cursor, exact item, click carry and no double placement")
