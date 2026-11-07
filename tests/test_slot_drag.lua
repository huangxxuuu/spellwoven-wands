-- Editor slots must keep native invslot hooks and the container widget lifecycle.
local M=require("nw/wand_container")
local panel={row={Hide=function(self) self.hidden=true end}}
function panel:AddChild(child) child.parent=self end
local owner={HUD={controls={nw_wandpanel=panel}}}
local wand={HasTag=function(_,tag) return tag=="nw_wand" end,_nw_capacity={value=function() return 2 end}}
local native_calls=0
local widget={bgimage={Hide=function() end},bganim={Hide=function() end}}
function widget:SetScale(s) self.scale=s end
function widget:SetPosition(x,y) self.x,self.y=x,y end
function widget:Open(inst,doer)
    native_calls=native_calls+1
    self.inv={}
    for i=1,12 do
        self.inv[i]={OnControl=function(_,key) return key=="third_party_shortcut" end,
            SetPosition=function(self,x,y) self.x=x end,
            Show=function(self) self.shown=true end,Hide=function(self) self.shown=false end}
    end
end
M.widget(widget)
widget:Open(wand,owner)
assert(native_calls==1 and widget.parent==panel and widget.scale==1)
assert(panel.native_container==widget and panel.row.hidden)
assert(widget.inv[1]:OnControl("third_party_shortcut"))
assert(widget.inv[2].shown and not widget.inv[3].shown)
M.layout(widget,4)
assert(widget.inv[4].shown and not widget.inv[5].shown and widget.inv[1].x==-123)
local chest={HasTag=function() return false end}
widget:Open(chest,owner)
assert(native_calls==2)
print("wand slots: native widget construction and third-party slot handlers preserved")
