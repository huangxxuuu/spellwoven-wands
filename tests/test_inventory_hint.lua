local H=require("nw/inventory_hint")
local D=require("nw/hover_data")
local Cards=require("nw/cards")
local Visual=require("nw/visual")
local wand=require("nw/generator").starter()
wand.always_cast="precision"
local slots={[2]={spell_id="scatter"},[12]={spell_id="spark"}}
for capacity=2,12 do
    wand.stats.capacity=capacity
    local model=D.wand(D.encode(wand),Cards.encode(slots,capacity),Visual.per_style,"试杖")
    assert(model.title=="试杖" and model.subtitle=="非乱序" and model.innate=="精准")
    assert(model.icon==Visual.icon(Visual.per_style)..".tex" and model.atlas==Visual.atlas(Visual.per_style))
    assert(#model.fields==8 and model.fields[7][2]==20 and model.fields[8][2]==capacity)
    assert(model.count==(capacity==12 and "2 / 12" or "1 / "..capacity))
end
assert(not D.wand(D.encode(wand),"0",0,"试杖").fields)
for _,id in ipairs(Cards.order) do
    local basic=D.card(id)
    local Tags=require("nw/card_tags")
    local labels={}
    for _,tag in ipairs(Tags.options(Tags.for_card(id))) do labels[#labels+1]=tag.text end
    assert(basic.subtitle==table.concat(labels," · "),"hover must list every public tag: "..id)
    assert(#basic.fields>=3 and not basic.effect:match("^[^\n]*"):find("%d"))
    if require("nw/arsenal").notes[id] then
        assert(basic.effect:find("\n基础音 ",1,true) and basic.effect:find("可调音域",1,true))
    else
        assert(not basic.effect:find("%d"))
    end
    local shown={};for _,f in ipairs(basic.fields) do shown[f[1]]=f[2] end
    assert(shown["法力消耗"]~=nil and shown["施放修正"] and shown["充能修正"])
    assert(not shown["最大转向"] and not shown["振幅"] and not shown["频率"])
    if id=="spark" then assert(shown["单弹伤害"]==18) end
    if id=="explosion" then assert(shown["范围伤害"]=="25 / 目标") end
    if id=="gunpowder" then assert(shown["范围伤害"]=="200 / 目标") end
    local card=D.card_details(id)
    assert(card.title==Cards.names[id] and card.subtitle and card.effect and card.icon)
    local fields={}
    for _,f in ipairs(card.fields) do fields[f[1]]=f[2] end
    assert(fields["法力消耗"]~=nil and fields["施放修正"]:find("秒") and fields["充能修正"]:find("秒"))
    if id=="scatter" then assert(fields["单弹伤害"]=="9 × 3" and fields["基础散射"]=="±2.5°") end
    if id=="chain" then assert(fields["首击 / 后续"]=="15 / 10" and fields["跳跃距离"]==6) end
    if id=="damage_up" then assert(fields["伤害加成"]=="+10" and not fields["单弹伤害"]) end
end

-- Exercise the real panel, nine-slice and slot row on a minimal DST widget backend.
Class=function(base,ctor)
    local c={_ctor=ctor};c.__index=c
    return setmetatable(c,{__index=base,__call=function(cls,...)
        local obj=setmetatable({},cls);ctor(obj,...);return obj
    end})
end
local Widget=Class(nil,function(self,name)
    self.name=name;self.children={};self.shown=true;self.scale=1
    self.inst={IsValid=function() return true end}
end)
function Widget:AddChild(w)
    if w.parent then
        for i,child in ipairs(w.parent.children) do
            if child==w then table.remove(w.parent.children,i);break end
        end
    end
    w.parent=self;self.children[#self.children+1]=w;return w
end
function Widget:KillAllChildren() self.children={} end
function Widget:SetClickable(v) self.click=v end
function Widget:Hide() self.shown=false end
function Widget:Show() self.shown=true end
function Widget:SetPosition(x,y) self.x,self.y=x,y end
function Widget:SetScale(s) self.scale=s end
function Widget:GetScale() return {x=self.scale,y=self.scale} end
function Widget:SetSize(w,h) self.w,self.h=w,h end
function Widget:SetTint() end
function Widget:SetTexture(a,t) self.atlas,self.texture=a,t end
local Image=Class(Widget,function(self,a,t) Widget._ctor(self,"image");self:SetTexture(a,t) end)
local UIAnim=Class(Widget,function(self)
    Widget._ctor(self,"uianim")
    self.state={symbols={},hidden={}}
    function self.state:SetBank(v) self.bank=v end
    function self.state:SetBuild(v) self.build=v end
    function self.state:PlayAnimation(v) self.animation=v end
    function self.state:OverrideSymbol(k,build,v) self.symbols[k]={build,v} end
    function self.state:HideSymbol(k) self.hidden[k]=true end
    function self.state:GetVisualBB() return -50,-20,70,180 end
end)
function UIAnim:GetAnimState() return self.state end
package.loaded["widgets/uianim"]=UIAnim
local Text=Class(Widget,function(self,font,size) Widget._ctor(self,"text");self.fontsize=size end)
function Text:SetColour() end
function Text:SetHAlign() end
function Text:SetString(str) self.str=str end
function Text:GetRegionSize() return self.str:utf8len()*self.fontsize,self.fontsize end
function Text:SetRegionSize(w,h) self.w,self.h=w,h end
function Text:SetMultilineTruncatedString(str,lines,width)
    self:SetString(str)
    local count=0
    for row in (str.."\n"):gmatch("(.-)\n") do
        count=count+math.max(1,math.ceil(row:utf8len()*self.fontsize/width))
    end
    return count
end
function string:utf8len() local _,n=self:gsub("[^\128-\191]","");return n end
package.loaded["widgets/widget"]=Widget;package.loaded["widgets/image"]=Image;package.loaded["widgets/text"]=Text
UIFONT="font";ANCHOR_LEFT=1
local sw,sh=1024,576
TheSim={GetScreenSize=function() return sw,sh end}
local function net(v) return {v=v,value=function(self) return self.v end} end
local cursor
local card_cursor={HasTag=function(_,tag) return tag=="nw_spellcard" end}
ThePlayer={replica={inventory={GetActiveItem=function() return cursor end}}}
local function hover(wand_item)
    local item={_nw_stats=net(""),_nw_cards=net(""),_nw_look=net(0),_spell=net(0),valid=true,
        GetDisplayName=function() return "试杖" end,IsValid=function(self) return self.valid end}
    local tile=Widget("itemtile")
    local events,task={}
    tile.item=item;tile.inst={
        ListenForEvent=function(_,name,cb,target)
            assert(target==(name=="newactiveitem" and ThePlayer or item));events[name]=cb
        end,
        RemoveEventCallback=function(_,name,cb,target)
            assert(target==ThePlayer and events[name]==cb);events[name]=nil
        end,
        DoPeriodicTask=function(_,_,fn) assert(not task);task={tick=fn,Cancel=function() task=nil end};return task end}
    function tile:SetTooltip(v) self.tooltip=v end
    function tile:SetHoverText()
        self.hovertext_root=Widget("global root");self.hovertext_root:Hide()
        self.hovertext=Widget("native text")
        self.OnGainFocus=function(t) t.hovertext_root:Show();t:UpdateTooltip() end
        self.OnLoseFocus=function(t) t.hovertext_root:Hide() end
    end
    function tile:IsVisible() return self.shown end
    function tile:GetWorldPosition() return {x=self.x,y=self.y} end
    H.install(tile,wand_item)
    local root=tile.hovertext_root
    assert(not root.shown and #root.children==0)
    tile.focus=true;tile:SetPosition(35,45);tile:OnGainFocus()
    local panel=root.children[1]
    assert(root.shown and root.click==false and #panel.frame.pieces==9 and task)
    for _,piece in ipairs(panel.frame.pieces) do assert(piece.click==false) end
    item._nw_stats.v=D.encode(wand);item._nw_cards.v=Cards.encode(slots,12)
    item._spell.v=Cards.codes.arrow_hit
    events[wand_item and "nw_wanddirty" or "nw_carddirty"]()
    if wand_item then
        cursor=card_cursor;task.tick();assert(root.shown);cursor=nil
        local row=panel.body.children[#panel.body.children]
        assert(row.width==12*36 and not row.selectslot and #row.cells==12)
        assert(not row.cells[1].icon.shown and row.cells[2].icon.texture=="nw_spell_scatter.tex")
        item._nw_look.v=Visual.per_style
        events.nw_lookdirty()
        local art=panel.body.children[1]
        assert(art.name=="uianim" and art.state.bank=="nw_parts")
        assert(art.state.animation=="preview_short" and art.x==48 and art.y==-54)
        assert(art.state.symbols.body[2]=="body_02_short")
    else
        cursor=card_cursor;events.newactiveitem();assert(root.shown)
        events.nw_carddirty();task.tick();assert(root.shown)
        tile.focus=false;tile:OnLoseFocus();assert(not events.newactiveitem)
        tile.focus=true;tile:OnGainFocus();assert(root.shown)
        cursor=nil;events.newactiveitem();assert(root.shown)
        cursor={HasTag=function() return false end};events.newactiveitem();assert(root.shown)
        cursor=nil
        local function effect_label()
            for _,child in ipairs(panel.body.children) do
                if child.str==D.card(Cards.bycode[item._spell:value()]).effect then return child end
            end
        end
        local effect=effect_label()
        assert(effect.str:find("载荷",1,true))
        item._spell.v=Cards.codes.chain;events.nw_carddirty()
        effect=effect_label()
        assert(effect.str==D.card("chain").effect and effect.h>=23)
    end
    local content=panel.body.children
    for _,scale in ipairs({.75,1,1.75}) do
        root.scale=scale;tile.scale=scale
        for _,p in ipairs({{35,45},{sw-25,45},{63,sh-25},{sw/2,sh/2}}) do
            tile:SetPosition(unpack(p));task.tick()
            local w,h=panel.width*scale*panel.scale,panel.height*scale*panel.scale
            assert(root.x>=w/2 and root.x<=sw-w/2 and root.y>=h/2 and root.y<=sh-h/2)
            assert(math.abs(root.y-p[2])-h/2>=40*scale-.001)
        end
    end
    assert(content==panel.body.children,"position and mana changes need not redraw contents")
    tile:Hide();task.tick();assert(not root.shown)
    tile.focus=false;tile:OnLoseFocus();assert(not task)
    tile:Show();tile.focus=true;tile:OnGainFocus();assert(root.shown and task)
    item.valid=false;events.onremove();assert(not root.shown and not task)
    return root,panel
end
local first,wand_panel=hover(true)
local second,card_panel=hover(false)
assert(wand_panel==card_panel and #first.children==0 and #second.children==1)
-- Tags stay in the upper-right header; effects precede the attributes, which
-- end without a trailing divider. Cover every card in both interface languages.
local Locale=require("nw/locale")
local language=Locale.language
for _,lang in ipairs({"zh","en"}) do
    Locale.language=lang
    for _,id in ipairs(Cards.order) do
        local data=D.card_details(id)
        data.title=data.title.."\nInspect"
        card_panel:Display(data)
        local effect,divider,dividers
        local badges={}
        dividers=0
        for _,child in ipairs(card_panel.body.children) do
            if child.str==data.effect then effect=child end
            if child.name=="hint_badge" then badges[#badges+1]=child end
            assert(child.str~=Locale.t("效果"),"effect heading must be omitted")
            if child.texture=="square.tex" then divider=child;dividers=dividers+1 end
        end
        assert(effect and dividers==1)
        assert(effect.y-effect.h/2>divider.y,"effects precede the property divider")
        assert(#badges==#data.tags)
        for i,tag in ipairs(badges) do
            assert(tag.children[3].str==data.tags[i])
            assert(tag.x-tag.width/2>=284 and tag.x+tag.width/2<=436)
            assert(tag.y+tag.height/2<=0)
            assert(tag.y-tag.height/2>effect.y+effect.h/2,"wrapped tags cannot overlap effects")
        end
        assert(card_panel.body.children[#card_panel.body.children].name=="text")
    end
end
Locale.language=language
for _,length in ipairs({"short","medium","long"}) do
    local index=length=="short" and 0 or length=="medium" and 1 or 2
    local data=D.wand(D.encode(wand),Cards.encode(slots,12),Visual.per_style+index*9,"试杖")
    card_panel:Display(data)
    local status=card_panel.body.children[3]
    assert(status.name=="hint_badge" and status.children[3].str==data.subtitle)
    data.wand_broken=true
    card_panel:Display(data)
    local art=card_panel.body.children[1]
    assert(art.state.animation=="preview_"..length)
    assert(art.state.symbols.head[2]:find("_broken$"))
end
print("inventory hover: real panel + frame, replicated rows, lifecycle, all spell IDs and HUD edge placement")
