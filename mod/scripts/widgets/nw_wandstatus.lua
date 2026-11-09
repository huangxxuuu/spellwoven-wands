local T=require("nw/locale").t
local Widget=require("widgets/widget")
local Image=require("widgets/image")
local Layout=require("nw/hud_layout")
local Hint=require("nw/inventory_hint")
local ATLAS="images/nw_hud.xml"
local function rectangle(parent,w,h,r,g,b)
    local image=parent:AddChild(Image("images/global.xml","square.tex"))
    image:SetSize(w,h);image:SetTint(r,g,b,1);image:SetClickable(false)
    return image
end
local function tip(widget,text)
    if widget._nw_tip==text then return end
    widget._nw_tip=text
    widget:SetHoverText(text,{font_size=17,bg_atlas="images/global.xml",bg_texture="square.tex"})
    widget.hovertext_bg:SetTint(.055,.05,.045,1)
end
local Status=Class(Widget,function(self)
    Widget._ctor(self,"nw_wandstatus")
    self.edit=self:AddChild(Image(ATLAS,"readonly.tex"))
    self.edit:SetSize(26,26);self.edit:SetPosition(-66,Layout.status_y)
    self.mana=rectangle(self,Layout.mana_width,18,.035,.025,.02)
    self.mana:SetClickable(true);self.mana:SetPosition(0,Layout.status_y)
    rectangle(self.mana,Layout.mana_width-4,14,.56,.40,.20)
    rectangle(self.mana,Layout.mana_width-7,11,.035,.06,.12)
    self.fill=rectangle(self.mana,1,9,.10,.48,.85)
    self.highlight=rectangle(self.fill,1,2,.30,.70,.95)
    self.highlight:SetPosition(0,3)
    self.cast=self:AddChild(Image(ATLAS,"ring_60.tex"))
    self.cast:SetSize(28,28);self.cast:SetPosition(66,Layout.status_y)
    self.spark=self.cast:AddChild(Image(ATLAS,"cast.tex"))
    self.spark:SetSize(18,18);self.spark:SetClickable(false)
end)
function Status:Refresh(wand,near,hint)
    local mana,maximum=wand._nw_mana:value(),wand._nw_maxmana:value()
    local cooling,total=wand._nw_cooldown:value(),wand._nw_cooltotal:value()
    local fraction,_,state=Layout.state(mana,maximum,cooling,total,wand._nw_cancast:value())
    if self.wand~=wand then self.shown_mana=fraction end
    if self.wand~=wand or cooling~=self.cooling or total~=self.total then
        self.cool_at=GetTime();self.cooling=cooling;self.total=total
    end
    self.wand=wand;self.target_mana=fraction;self.state=state
    if self.near~=near then
        self.near=near;self.edit:SetTexture(ATLAS,near and "edit.tex" or "readonly.tex")
        self.edit:SetSize(26,26)
    end
    tip(self.edit,(hint or (near and T("可编辑：点击或拖动法术卡") or T("只读：靠近奥术台可编辑")))..T("\n按住右键拖动窗口"))
    tip(self.mana,string.format(T("法力 %d / %d\n按住右键拖动窗口"),mana,maximum))
    tip(self.cast,wand._nw_broken and wand._nw_broken:value() and T("法杖破损：用 5 份奥术粉尘修复") or state=="cooling" and string.format(T("冷却剩余 %.1f 秒"),cooling/100)
        or state=="ready" and T("可以施法") or require("nw/cast_status").tip(wand._nw_castreason and wand._nw_castreason:value()))
end
function Status:OnUpdate(dt)
    if not self.wand then return end
    local target=self.target_mana
    self.shown_mana=self.shown_mana+(target-self.shown_mana)*math.min(1,dt*16)
    if math.abs(self.shown_mana-target)<.001 then self.shown_mana=target end
    local width=(Layout.mana_width-9)*self.shown_mana
    if self.fill_width~=width then
        self.fill_width=width
        if width<.1 then self.fill:Hide() else
            self.fill:Show();self.fill:SetSize(width,9)
            self.fill:SetPosition(-(Layout.mana_width-9)/2+width/2,0)
            self.highlight:SetSize(width,2)
        end
    end
    local remaining=math.max(0,self.cooling-(GetTime()-self.cool_at)*100)
    local _,progress=Layout.state(0,1,remaining,self.total,false)
    local step=self.state=="cooling" and math.min(59,math.floor(progress*60)) or 60
    if self.step~=step then
        self.step=step;self.cast:SetTexture(ATLAS,string.format("ring_%02d.tex",step));self.cast:SetSize(28,28)
    end
    if self.draw_state~=self.state then
        self.draw_state=self.state
        local tint=self.state=="blocked" and .4 or 1
        self.cast:SetTint(tint,tint,tint,1)
        local glow=self.state=="ready" and 1 or .45
        self.spark:SetTint(glow,glow,glow,1)
    end
    for _,widget in ipairs({self.edit,self.mana,self.cast}) do
        if widget.focus and widget.hovertext_root and widget.hovertext_root.shown then
            local root=widget.hovertext_root
            local w,h=widget.hovertext:GetRegionSize()
            w,h=w*1.1+24,h*1.1+16;widget.hovertext_bg:SetSize(w,h)
            local scale=root:GetScale();local p=widget:GetWorldPosition()
            local sw,sh=TheSim:GetScreenSize()
            local x,y=Hint.position(p.x,p.y,w*scale.x,h*scale.y,sw,sh,16*widget:GetScale().y,scale.y)
            root:SetPosition(x,y,0)
        end
    end
end
return Status
