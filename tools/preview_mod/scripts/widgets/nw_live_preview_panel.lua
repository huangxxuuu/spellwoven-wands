local Widget=require("widgets/widget")
local Text=require("widgets/text")
local Image=require("widgets/image")
local Button=require("widgets/imagebutton")
local FONT=BODYTEXTFONT
local spells={
    {"spark","火花"},{"arrow","箭弹"},{"fire","火弹"},{"frost","冰弹"},
    {"heavy","重弹"},{"scatter","散弹"},{"gust","风压弹"},{"slime","黏液弹"},
    {"heal_bolt","愈合弹"},{"land_hook","岸上抓钩"},{"spore_ball","蘑菇孢球"},
    {"flint_lance","燧晶投枪"},{"grow_orb","蓄势光球"},{"star_vortex","旋流四星"},
    {"glass_disc","月玻璃飞刃"},{"tri_electric","三相电球"},{"end_beam","终点聚爆束"},
    {"soundwave","音波"},{"bee_swarm","蜂群突袭"},{"fireflies","萤虫伴飞"},
}
local function label(parent,text,size,x,y)
    local t=parent:AddChild(Text(FONT,size,text))
    t:SetColour(.94,.96,1,1)
    t:SetPosition(x,y);t:SetClickable(false);return t
end
local function button(parent,text,x,y,w,fn)
    local b=parent:AddChild(Button("images/global.xml","square.tex"))
    b:ForceImageSize(w,26);b:SetPosition(x,y)
    b.scale_on_focus=false;b.move_on_click=false
    b:SetImageNormalColour(.16,.19,.24,1)
    b:SetImageFocusColour(.28,.36,.46,1)
    b:SetFont(FONT);b:SetTextSize(20)
    b:SetTextColour(.96,.97,1,1);b:SetTextFocusColour(1,1,1,1)
    b:SetTextDisabledColour(.65,.69,.75,1)
    b:SetText(text);b:SetOnClick(fn)
    return b
end
local Panel=Class(Widget,function(self,api)
    Widget._ctor(self,"nw_live_preview_panel")
    self.api=api;self.selected=1;self.speed=20;self.angle=0;self.size=1
    self.ui_scale=2.25
    self:SetHAnchor(ANCHOR_LEFT);self:SetVAnchor(ANCHOR_BOTTOM)
    self:SetScaleMode(SCALEMODE_NONE)
    self.body=self:AddChild(Widget("preview_body"))
    local bg=self.body:AddChild(Image("images/global.xml","square.tex"))
    bg:SetSize(360,570);bg:SetPosition(0,-300);bg:SetTint(.035,.045,.065,.96)
    -- A clickable background prevents clicks in panel gaps reaching the world.
    bg:SetClickable(true)
    self.toggle=button(self,"收起",148,0,64,function()
        self.collapsed=not self.collapsed
        if self.collapsed then self.body:Hide() else self.body:Show() end
        self.toggle:SetText(self.collapsed and "展开" or "收起")
    end)
    self.handle=button(self,"法术预览 · 拖动",-98,0,160,function() end)
    self.zoomout=button(self,"缩小",8,0,44,function() self:ChangeZoom(-.25) end)
    self.zoomin=button(self,"放大",58,0,44,function() self:ChangeZoom(.25) end)
    self.zoomtext=label(self,"",13,99,0)
    self.zoomout:SetHoverText("缩小界面（不改变弹体大小）",{font_size=18})
    self.zoomin:SetHoverText("放大界面；达到屏幕边界后停止放大",{font_size=18})
    self.handle.OnControl=function(_,control,down)
        if control==CONTROL_ACCEPT then
            if down then self:BeginDrag() else self.drag=nil end
            return true
        end
        return false
    end
    self.handle.OnMouseButton=function(_,btn,down)
        if btn==MOUSEBUTTON_LEFT then
            if down then self:BeginDrag() else self.drag=nil end
            return true
        end
        return false
    end
    label(self.body,"自制法术 · 飞行外观",23,0,-39)
    self.spellbuttons={}
    for i,row in ipairs(spells) do
        local index=i
        local b=button(self.body,row[2],(i%2==1 and -85 or 85),-74-math.floor((i-1)/2)*29,158,function()
            self.selected=index;self:RefreshSelection()
            local _,running=self.api.status()
            if running then self:Play() end
        end)
        b:SetHoverText(row[1],{font_size=18})
        self.spellbuttons[i]=b
    end
    self.idtext=label(self.body,"",19,0,-365)
    self.idtext:SetColour(.68,.84,1,1)
    self.values={}
    local rows={
        {"speed","速度",-398,5,.1,60},
        {"angle","方向",-432,45,0,360},
        {"size","大小",-466,.25,1,5},
    }
    for _,row in ipairs(rows) do
        local key,title,y,step,lo,hi=unpack(row)
        label(self.body,title,20,-123,y)
        self.values[key]=label(self.body,"",20,5,y)
        local function change(sign)
            local value=self[key]+sign*step
            self[key]=key=="angle" and value%360 or math.max(lo,math.min(hi,value))
            self:RefreshValues()
            local _,running=self.api.status();if running then self:Play() end
        end
        button(self.body,"−",-57,y,34,function() change(-1) end)
        button(self.body,"+",72,y,34,function() change(1) end)
    end
    button(self.body,"开始 / 重播",-112,-505,110,function() self:Play() end)
    button(self.body,"停止",0,-505,94,function() self.api.stop() end)
    button(self.body,"刷新素材",112,-505,110,function() self.api.refresh() end)
    self.status=label(self.body,"",18,0,-539)
    self.status:SetColour(.74,.90,.78,1)
    label(self.body,"保存素材自动刷新 · 方向为世界角度",17,0,-564)
    self:RefreshSelection();self:RefreshValues();self:StartUpdating()
end)
function Panel:RefreshSelection()
    for i,b in ipairs(self.spellbuttons) do
        if i==self.selected then b:SetImageNormalColour(.16,.34,.28,1)
        else b:SetImageNormalColour(.16,.19,.24,1) end
    end
    self.idtext:SetString(spells[self.selected][1])
end
function Panel:RefreshValues()
    self.values.speed:SetString(string.format("%.1f",self.speed))
    self.values.angle:SetString(string.format("%d°",self.angle))
    self.values.size:SetString(string.format("%.2f×",self.size))
end
function Panel:Play()
    self.api.start(spells[self.selected][1],self.speed,self.angle,self.size)
end
function Panel:BeginDrag()
    if self.drag or not TheInput:IsMouseDown(MOUSEBUTTON_LEFT) then return end
    local mouse=TheInput:GetScreenPosition()
    local pos=self:GetWorldPosition()
    self.drag={dx=pos.x-mouse.x,dy=pos.y-mouse.y}
end
function Panel:ChangeZoom(delta)
    -- Start from the displayed scale when the screen has capped the request,
    -- so shrinking always has an immediate, visible effect.
    self.ui_scale=math.max(.75,math.min(3,(self.actual_scale or self.ui_scale)+delta))
    self:PlaceWindow()
end
function Panel:PlaceWindow()
    if not self.parent then return end
    local sw,sh=TheSim:GetScreenSize()
    local parent=self.parent:GetScale()
    -- Use screen pixels; the HUD's proportional scale must not be applied twice.
    local fit=math.min(self.ui_scale,(sw-24)/360,(sh-24)/611)
    if self.actual_scale~=fit then
        self.actual_scale=fit
        self.zoomtext:SetString(string.format("%d%%",math.floor(fit*100+.5)))
    end
    self:SetScale(fit/parent.x,fit/parent.y,1)
    local x=self.saved and self.saved.x*sw or 12+180*fit
    local y=self.saved and self.saved.y*sh or sh-12-13*fit
    if self.drag then
        if not TheInput:IsMouseDown(MOUSEBUTTON_LEFT) or not self.shown
            or not ThePlayer or TheFrontEnd:GetActiveScreen()~=ThePlayer.HUD then self.drag=nil
        else
            local mouse=TheInput:GetScreenPosition()
            x,y=mouse.x+self.drag.dx,mouse.y+self.drag.dy
        end
    end
    x=math.max(12+180*fit,math.min(sw-12-180*fit,x))
    y=math.max(12+(self.collapsed and 13 or 585)*fit,math.min(sh-12-13*fit,y))
    self.saved={x=x/sw,y=y/sh}
    local at,pos=self:GetWorldPosition(),self:GetPosition()
    self:SetPosition(pos.x+(x-at.x)/parent.x,pos.y+(y-at.y)/parent.y)
end
function Panel:OnUpdate(dt)
    self:PlaceWindow()
    local message,running,revision=self.api.status()
    if running and revision then message="播放中 · "..revision end
    if message~=self.lastmessage then self.status:SetString(message);self.lastmessage=message end
end
function Panel:OnHide() self.drag=nil end
return Panel
