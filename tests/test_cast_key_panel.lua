-- Exercise the real panel/capture callbacks with widget and transport shells.
UIFONT="font";MOVE_UP=1;MOVE_DOWN=2;ANCHOR_LEFT=1;ANCHOR_RIGHT=2;KEY_ESCAPE=27
local tasks={}
local Widget={}
local function initialize(w)
    w.enabled=true;w.events={};w.children={}
    w.position={x=0,y=0,z=0};w.scale={x=1,y=1,z=1}
    w.inst={IsValid=function() return not w.dead end,
        ListenForEvent=function(_,event,fn)
            local previous=w.events[event]
            w.events[event]=function() if previous then previous() end;fn() end
        end,
        DoTaskInTime=function(_,_,fn)
            local task={fn=fn,Cancel=function(self) self.cancelled=true end}
            tasks[#tasks+1]=task;return task
        end}
end
function Widget:AddChild(child)
    self.children[#self.children+1]=child;child.parent=self;return child
end
function Widget:SetPosition(x,y,z)
    self.position=type(x)=="table" and {x=x.x,y=x.y,z=x.z or 0} or {x=x,y=y or 0,z=z or 0}
end
function Widget:GetPosition() return self.position end
function Widget:SetScale(x,y,z) self.scale={x=x,y=y or x,z=z or x} end
-- Native Widget:GetScale includes ancestor scales; GetPosition stays local.
function Widget:GetScale() return self:GetWorldScale() end
function Widget:GetWorldScale()
    local p=self.parent and self.parent:GetWorldScale() or {x=1,y=1,z=1}
    return {x=p.x*self.scale.x,y=p.y*self.scale.y,z=p.z*self.scale.z}
end
function Widget:GetWorldPosition()
    if not self.parent then return self.position end
    local p,s=self.parent:GetWorldPosition(),self.parent:GetWorldScale()
    return {x=p.x+self.position.x*s.x,y=p.y+self.position.y*s.y,z=p.z+self.position.z*s.z}
end
function Widget:SetSize(width,height) self.width=width;self.height=height end
function Widget:GetSize() return self.width,self.height end
function Widget:SetClickable(value) self.clickable=value end
function Widget:SetTint(...) self.tint={...} end
function Widget:MoveToBack()
    for i,child in ipairs(self.parent.children) do
        if child==self then table.remove(self.parent.children,i);break end
    end
    table.insert(self.parent.children,1,self)
end
function Widget:Kill()
    self.dead=true
    if self.parent then
        for i,child in ipairs(self.parent.children) do
            if child==self then table.remove(self.parent.children,i);break end
        end
    end
end
local function widget()
    local w=setmetatable({},{__index=Widget});initialize(w)
    function w:SetString(value) self.value=value end
    function w:GetString() return self.value or "" end
    function w:SetRegionSize(width,height) self.region={width,height} end
    function w:GetRegionSize()
        if self.region then return unpack(self.region) end
        return #(self.value or "")*(self.size or 18)*.55,(self.size or 18)*1.1
    end
    function w:SetTextSize(size) self.size=size end
    function w:Show() self.shown=true end
    function w:Hide() self.shown=false end
    w.SetText=w.SetString
    function w:Enable() self.enabled=true end
    function w:Disable() self.enabled=false end
    function w:SetOnClick(fn) self.click=fn end
    function w:SetOnChangedFn(fn) self.changed=fn end
    function w:SetOptions(options) self.options=options end
    function w:SetSelectedIndex(index) assert(self.options[index]);self.selected=index end
    function w:SetFocusChangeDir(dir,target) self.focus=self.focus or {};self.focus[dir]=target end
    for _,method in ipairs({"SetTextColour","SetWrapEnabled","SetFont","SetHAlign","SetHoverText","SetColour"}) do w[method]=function() end end
    return w
end
Widget._ctor=initialize
package.loaded["widgets/widget"]=Widget
package.loaded["widgets/image"]=function(atlas,texture)
    local w=widget();w.atlas=atlas;w.texture=texture;return w
end
Class=function(base,ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__index=base,__call=function(_,...) local w=setmetatable({},cls);ctor(w,...);return w end})
end
package.loaded["widgets/textbutton"]=widget
package.loaded["widgets/nw_keyhint"]=function() error("settings must display plain key names, not keycaps") end
package.loaded["widgets/spinner"]=function() error("cast key row must not construct arrow selectors") end
local popup_layout={x=960,y=540,scale=1,root_scale=1}
package.loaded["screens/popupdialog"]=function(title,text)
    local w=widget();w:SetPosition(popup_layout.x,popup_layout.y);w:SetScale(popup_layout.scale)
    w.black=w:AddChild(widget());w.black:SetSize(1920,1080)
    w.black:SetTint(0,0,0,0);w.black:SetClickable(true)
    w.proot=w:AddChild(widget());w.proot:SetScale(popup_layout.root_scale)
    -- Image metrics can be unavailable before layout or reflect the source
    -- texture; neither is the custom frame's local layout contract.
    w.bg=w.proot:AddChild(widget());w.bg:SetSize(popup_layout.width or 1024,popup_layout.height or 512)
    w.bg:SetScale(.70);w.bg:SetPosition(0,10)
    w.original_bg=w.bg
    w.text=w.proot:AddChild(widget());w.text:SetString(text);w.text:SetTextSize(28)
    w.text:SetPosition(5,-15);w.text:SetRegionSize(500,160)
    w.title=w.proot:AddChild(widget());w.title:SetString(title);w.title:SetTextSize(50);w.title:SetPosition(5,88)
    w.menu=w.proot:AddChild(widget());w.menu:SetPosition(0,-100)
    return w
end
local english=false
package.loaded["nw/performance_settings"]={text=function(zh,en) return english and en or zh end}
local ready,pending,override=true,false,nil
local writes,subscribers={},{}
local default="mouse:1001"
local Binding={ready=function() return ready end,pending=function() return pending end,
    get_override=function() return override end,get_default=function() return default end,
    get=function() return override or default end}
local function notify() for fn in pairs(subscribers) do fn() end end
Binding.set=function(value)
    writes[#writes+1]={value=value};pending=true;notify()
end
Binding.subscribe=function(fn) subscribers[fn]=true;return function() subscribers[fn]=nil end end
package.loaded["nw/cast_binding"]=Binding
package.loaded["nw/locale"]={language="zh"}
STRINGS={UI={CONTROLSSCREEN={INPUTS={{[1001]="RMB",[1002]="MMB",[1005]="M4"}}}}}
ThePlayer={}
TheFrontEnd={stack={}}
function TheFrontEnd:PushScreen(screen) self.stack[#self.stack+1]=screen end
function TheFrontEnd:PopScreen(screen)
    assert(self.stack[#self.stack]==screen,"capture must remove its own screen")
    screen:OnBecomeInactive()
    table.remove(self.stack)
    screen.dead=true
    if screen.events.onremove then screen.events.onremove() end
end
local function tick()
    local queued=tasks;tasks={}
    for _,task in ipairs(queued) do if not task.cancelled then task.fn() end end
end
local screen=widget()
screen.personal=widget();screen.limit_speech=widget();screen.menu=widget()
screen.text_colour={1,1,1,1};screen.active_page="personal";screen.option_tip=function() end
local panel=require("nw/cast_key_panel").attach(screen,function() return widget() end)
local value,button,reset=panel.value,panel.button,panel.reset
local function ack(value)
    override=value;pending=false;notify()
end
local function near(a,b,message) assert(math.abs(a-b)<.00001,message) end
local function capture_frame(popup)
    local frame=popup.bg
    assert(popup.original_bg.dead,"native dialog background must be removed")
    assert(frame.parent==popup.proot and popup.proot.children[1]==frame,
        "replacement frame belongs behind dialog content in the same local root")
    assert(frame.clickable==false and #frame.pieces==9,"capture uses the real nine-piece noninteractive frame")
    assert(not popup.black.dead and popup.black.parent==popup and popup.black.clickable==true
        and popup.black.tint[4]==0,"transparent fullscreen input blocker must stay transparent and intact")
    local left,right,bottom,top=math.huge,-math.huge,math.huge,-math.huge
    for _,piece in ipairs(frame.pieces) do
        assert(piece.parent==frame and piece.clickable==false,"frame pieces cannot intercept input")
        local p,s=piece:GetWorldPosition(),piece:GetScale()
        local width,height=piece:GetSize()
        assert(width>0 and height>0,"nine-slice dimensions remain positive")
        left=math.min(left,p.x-width*s.x/2);right=math.max(right,p.x+width*s.x/2)
        bottom=math.min(bottom,p.y-height*s.y/2);top=math.max(top,p.y+height*s.y/2)
    end
    local p,s=popup.proot:GetWorldPosition(),popup.proot:GetScale()
    near((left+right)/2,p.x,"capture frame stays horizontally centered on its root")
    near((bottom+top)/2,p.y+24*s.y,"capture frame keeps the requested raised vertical center")
    near((right-left)/s.x,370,"capture width follows the screenshot's compact frame independent of inherited scale/image metrics")
    near((top-bottom)/s.y,190,"capture height follows the screenshot's compact frame")
    local edge=require("nw/constants/ui").nw_wandframe.edge
    for _,content in ipairs({popup.title,popup.text}) do
        local cp,cs=content:GetWorldPosition(),content:GetScale()
        local width,height=content:GetRegionSize()
        -- Only absorb floating-point roundoff at the exact top/bottom fit.
        local epsilon=.00001
        assert(cp.x-width*cs.x/2>=left+edge*s.x-epsilon and cp.x+width*cs.x/2<=right-edge*s.x+epsilon
            and cp.y-height*cs.y/2>=bottom+edge*s.y-epsilon and cp.y+height*cs.y/2<=top-edge*s.y+epsilon,
            "capture title and instructions must fit inside the sixteen-pixel frame edge")
    end
    assert(popup.title.size==50 and popup.text.size==28,"compacting the frame must preserve the native text sizes")
    local title_width,title_height=popup.title:GetRegionSize()
    assert(title_width==330 and title_height==50,"title uses its compact single-line region")
    local text_width,text_height=popup.text:GetRegionSize()
    assert(text_width==330 and text_height==80,"instructions use the compact text region")
    assert(popup.title.position.x==0 and popup.title.position.y==78
        and popup.text.position.x==0 and popup.text.position.y==-15,
        "title and instructions stay centered while the title gains top padding")
end
local function open()
    button.click()
    local popup=panel.capture
    assert(popup and ThePlayer._nw_binding_capture==popup)
    assert(popup:OnControl(1,true)==true and popup:OnControl(1,false)==true,"controls never reach gameplay")
    capture_frame(popup)
    return popup
end
assert(button.enabled and reset.enabled and value:GetString()=="鼠标右键","show plain effective key name even when following host")
assert(screen.cast_key==value and screen.cast_key_capture==button and screen.cast_key_reset==reset)
assert(screen.limit_speech.focus[MOVE_DOWN]==button and button.focus[MOVE_DOWN]==reset
    and reset.focus[MOVE_DOWN]==screen.menu,"navigation follows modify, restore, menu")
for _,layout in ipairs({
    {x=320,y=180,scale=.75,root_scale=1.2,width=2048,height=1024},
    {x=1280,y=720,scale=1.5,root_scale=.8,width=0,height=0},
}) do
    popup_layout=layout
    local scaled=open();scaled:OnRawKey(KEY_ESCAPE,true);tick()
    assert(#writes==0 and #TheFrontEnd.stack==0,"layout regression must not save any input")
end
popup_layout={x=960,y=540,scale=1,root_scale=1}
local initial=open();tick();initial:OnMouseButton(1002,true);initial:OnMouseButton(1002,false)
assert(#writes==1 and writes[1].value=="mouse:1002" and not reset.enabled and not button.enabled)
assert(panel.status.value=="正在保存，等待服务器确认…" and value:GetString()=="鼠标右键","do not display unacknowledged override")
reset.click();button.click();assert(#writes==1 and not panel.capture,"pending blocks edits")
ack("mouse:1002");assert(value:GetString()=="鼠标中键")
reset.click();assert(#writes==2 and writes[2].value==nil)
ack(nil);assert(value:GetString()=="鼠标右键")
local popup=open()
popup:OnMouseButton(1001,true);popup:OnMouseButton(1001,false)
assert(#writes==2 and panel.capture==popup,"opening click is ignored")
tick();popup:OnRawKey(0,true);popup:OnRawKey(0,false)
assert(#writes==2 and panel.capture==popup,"invalid keys keep capture open")
capture_frame(popup)
popup:OnRawKey(107,true)
assert(popup.text:GetString()=="松开后保存：K" and not popup.nw_cast_key,
    "capture candidate must display a plain readable key name")
capture_frame(popup)
assert(#writes==2 and ThePlayer._nw_binding_capture==popup,"key down alone cannot save or rearm casting")
popup:OnRawKey(0,false);assert(#writes==2,"another key's release cannot finish capture")
popup:OnRawKey(107,false)
assert(#writes==3 and writes[3].value=="key:107" and not panel.capture and not ThePlayer._nw_binding_capture)
assert(pending and not button.enabled);ack("key:107")
assert(value:GetString()=="K" and not value.cap_left,"custom key displays as plain text")
popup=open();tick();popup:OnMouseButton(1005,true)
assert(#writes==3);popup:OnMouseButton(1005,false)
assert(#writes==4 and writes[4].value=="mouse:1005");ack("mouse:1005")
popup=open();popup:OnRawKey(KEY_ESCAPE,true)
assert(not panel.capture and not ThePlayer._nw_binding_capture and #writes==4,"Esc cancels even before arming")
popup=open();tick();popup:OnRawKey(107,true);popup:OnBecomeInactive()
assert(not panel.capture and not ThePlayer._nw_binding_capture and #writes==4,"screen losing activity cancels unsaved candidate")
tick();assert(#TheFrontEnd.stack==0)
popup=open();tick();popup:OnLoseFocus()
assert(not panel.capture and not ThePlayer._nw_binding_capture,"focus loss cancels")
tick();assert(#TheFrontEnd.stack==0)
popup=open();TheFrontEnd:PopScreen(popup);tick()
assert(not panel.capture and #TheFrontEnd.stack==0,"external native removal cannot recursively pop twice")
popup=open();panel.cancel()
assert(not panel.capture and #writes==4,"guide page change uses the same cancellation")
ready=false;notify()
assert(not reset.enabled and not button.enabled and value:GetString()=="同步中…")
button.click();assert(not panel.capture)
ready=true;notify();popup=open();screen.events.onremove()
assert(not panel.capture and not ThePlayer._nw_binding_capture and not next(subscribers),"guide closure clears capture and subscription")
tick();assert(not panel.capture,"delayed arming cannot resurrect a closed popup")
english=true
require("nw/locale").language="en"
local other=widget();other.personal=widget();other.limit_speech=widget();other.menu=widget()
other.text_colour={1,1,1,1};other.active_page="personal";other.option_tip=function() end
local english_panel=require("nw/cast_key_panel").attach(other,function() return widget() end)
assert(english_panel.button.value=="Change" and english_panel.reset.value=="Restore host default" and english_panel.value:GetString()=="Mouse button 4")
english_panel.button.click();capture_frame(english_panel.capture)
other.events.onremove()
print("cast key UI: bounded centered nine-slice capture under inherited scales, transparent input blocker, actual key without arrows, modify and restore, acknowledged saves, pending/sync disable, raw keyboard/mouse capture, opening event, invalid keys, release barrier, cancellation, teardown and English")
