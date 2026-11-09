-- Exercise the actual guide/panel constructors and callbacks without a renderer.
UIFONT="font";MOVE_UP=1;MOVE_DOWN=2;MOVE_LEFT=3;MOVE_RIGHT=4;ANCHOR_LEFT=1
local function widget()
    local w={children={},shown=true,pos={x=0,y=0},enabled=true}
    w.inst={IsValid=function() return not w.dead end,
        DoPeriodicTask=function(_,dt,fn) w.tick=fn;return {Cancel=function() w.cancelled=true end} end,
        ListenForEvent=function(_,event,fn) w[event]=fn end}
    function w:AddChild(c) self.children[#self.children+1]=c;return c end
    function w:SetPosition(x,y) self.pos={x=x,y=y} end
    function w:GetPosition() return self.pos end
    function w:SetString(value) self.text=value end
    w.SetText=w.SetString
    function w:SetOnClick(fn) self.click=fn end
    function w:Show() self.shown=true end
    function w:Hide() self.shown=false end
    function w:Kill() self.dead=true end
    function w:Enable() self.enabled=true end
    function w:Disable() self.enabled=false end
    function w:SetSize(a,b) self.size={a,b} end
    function w:SetFocusChangeDir(dir,target) self.focus=self.focus or {};self.focus[dir]=target end
    function w:SetHoverText(t) self.tip=t end
    for _,name in ipairs({"SetHAlign","SetFont","SetTextSize","SetColour","SetClickable","MoveToBack","EnableWordWrap","SetRegionSize","SetTint","SetWrapEnabled","SetTextColour"}) do w[name]=function() end end
    return w
end
package.loaded["widgets/widget"]=widget
package.loaded["widgets/image"]=widget
package.loaded["widgets/nw_wandframe"]=widget
package.loaded["widgets/textbutton"]=widget
package.loaded["widgets/text"]=function(_,_,value) local w=widget();w.text=value;return w end
package.loaded["widgets/spinner"]=function(options)
    assert(#options>0,"native spinner requires an initial selection")
    local w=widget();w.options=options;w.text=widget();w.leftimage=widget();w.rightimage=widget()
    function w:SetOptions(v) self.options=v end
    function w:SetSelectedIndex(i) assert(self.options[i]);self.selected=i end
    function w:SetOnChangedFn(fn) self.changed=fn end
    return w
end
package.loaded["screens/popupdialog"]=function()
    local w=widget();w.proot=widget();w.title=widget();w.bg=widget();w.menu=widget();return w
end
local mode="target"
package.loaded["nw/cast_direction"]={get=function() return mode end,set=function(v) mode=v end,load=function(fn) fn() end}
TheSim={GetPersistentString=function(_,_,cb) cb(false,"") end,SetPersistentString=function(_,_,_,_,cb) cb() end}
TheFrontEnd={PushScreen=function(_,screen) TheFrontEnd.screen=screen end,PopScreen=function() end}
local Settings=require("nw/performance_settings")
local changed,listener,unsubscribed
Settings.query=function() end
Settings.poll=function() end
Settings.subscribe=function(fn) Settings.allowed=false;Settings.synced=false;listener=fn;return function() unsubscribed=true;listener=nil end end
Settings.change=function(key,index) changed={key,index};return true end
local guide=require("nw/quickguide").open()
assert(TheFrontEnd.screen==guide and guide.direction)
assert(guide.active_page=="guide" and guide.guide.shown and not guide.personal.shown)
assert(#guide.guide.children==11,"introduction contains only three building rows and two separators")
assert(guide.performance_tab.shown and not guide.performance.shown,"everyone can open the performance tab")
guide.performance_tab.click();assert(guide.performance.shown)
local panel=guide.performance
assert(#panel.rows==7 and not panel.rows[1].spinner.enabled)
assert(panel.rows[1].spinner.options[1].text=="同步中…")
Settings.synced=true;Settings.client_values.limit_projectiles=400;listener()
assert(panel.rows[1].spinner.selected==7 and not panel.rows[1].spinner.enabled)
panel.rows[1].spinner.changed(1);assert(not changed,"read-only callbacks cannot send writes")
guide.tabs.personal.click();assert(guide.personal.shown and not panel.shown and not guide.guide.shown)
guide.trail_limit.changed(1300);assert(require("nw/trail_budget").limit==1300,"personal trails need no admin permission")
Settings.allowed=true;listener()
guide.tabs.performance.click()
assert(panel.shown and panel.rows[1].spinner.enabled)
panel.rows[1].spinner.changed(6);assert(changed[1]=="limit_projectiles" and changed[2]==6)
panel.refresh()
assert(#panel.rows[5].spinner.options==31,"all 30 payload depths must fit in the selector")
panel.rows[5].spinner.changed(31);assert(changed[1]=="limit_depth" and changed[2]==31)
Settings.pending={};panel.refresh();assert(not panel.rows[5].spinner.enabled)
Settings.pending=nil;Settings.allowed=false;Settings.client_values.limit_projectiles=800;listener()
assert(panel.shown and guide.performance_tab.shown and not panel.rows[1].spinner.enabled)
assert(panel.rows[1].spinner.selected==11,"permission revocation keeps the latest server value visible")
guide.tabs.personal.click();assert(not panel.shown and guide.menu.focus[MOVE_UP]==guide.trail_limit)
guide.direction.changed("mouse");assert(mode=="mouse","existing personal preference must still work")
guide.onremove();assert(unsubscribed and guide.cancelled)
require("nw/locale").configure("en","en")
local english=require("nw/quickguide").open();Settings.allowed=true;listener()
assert(english.performance.rows[1].title.text=="Live projectiles per player" and english.trail_limit.selected==5)
english.onremove()
print("performance guide: three separate tabs, public read-only performance, server values and syncing placeholder, independent personal trails, all depths, pending disable, permission revocation, existing preference, English and teardown")
