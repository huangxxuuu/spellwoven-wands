local T=require("nw/locale").t
local Widget=require("widgets/widget")
local Image=require("widgets/image")
local UIAnim=require("widgets/uianim")
local Text=require("widgets/text")
local Frame=require("widgets/nw_wandframe")
local Row=require("widgets/nw_slotrow")
local WIDTH,PAD,SLOT=480,22,36
local INNER=WIDTH-PAD*2
local VALUE={1,.93,.80,1}
local LABEL={.82,.73,.60,1}

local Panel=Class(Widget,function(self)
    Widget._ctor(self,"nw_itemhint")
    self:SetClickable(false)
    self.width=WIDTH
    self.frame=self:AddChild(Frame())
    self.frame:SetClickable(false)
    for _,part in ipairs(self.frame.pieces) do part:SetClickable(false) end
    self.body=self:AddChild(Widget("details"))
    self.body:SetClickable(false)
end)

-- Body coordinates start at the top left of the inset and grow down the page.
local function label(body,str,x,top,width,size,colour,wrap)
    local t=body:AddChild(Text(UIFONT,size))
    t:SetClickable(false)
    t:SetColour(unpack(colour))
    t:SetHAlign(ANCHOR_LEFT)
    local lines=1
    if wrap then
        lines=t:SetMultilineTruncatedString(str,32,width,nil,false)
    else
        t:SetString(tostring(str))
    end
    local height=lines*(size+5)
    t:SetRegionSize(width,height)
    t:SetPosition(x+width/2,-top-height/2)
    return height
end
local function line(body,y)
    local img=body:AddChild(Image("images/global.xml","square.tex"))
    img:SetSize(INNER,1);img:SetTint(.59,.46,.30,.75)
    img:SetPosition(INNER/2,-y);img:SetClickable(false)
end
local function badges(body,items,x,top,width)
    local dx,dy,rowheight=0,0,0
    for _,str in ipairs(items) do
        local badge=body:AddChild(Widget("hint_badge"))
        badge:SetClickable(false)
        local border=badge:AddChild(Image("images/global.xml","square.tex"))
        local fill=badge:AddChild(Image("images/global.xml","square.tex"))
        local text=badge:AddChild(Text(UIFONT,16))
        border:SetClickable(false);fill:SetClickable(false);text:SetClickable(false)
        border:SetTint(.57,.43,.25,.95)
        fill:SetTint(.19,.15,.10,1)
        text:SetColour(unpack(VALUE))
        text:SetString(str)
        local measured=text:GetRegionSize()
        local w=math.min(width,measured+14)
        local lines=text:SetMultilineTruncatedString(str,32,w-14,nil,false)
        local h=lines*21+6
        if dx>0 and dx+w>width then dx=0;dy=dy+rowheight+5;rowheight=0 end
        badge.width,badge.height=w,h
        badge:SetPosition(x+dx+w/2,-top-dy-h/2)
        border:SetSize(w,h);fill:SetSize(w-2,h-2)
        text:SetRegionSize(w-14,h-6)
        dx=dx+w+5;rowheight=math.max(rowheight,h)
    end
    return dy+rowheight
end
function Panel:Display(data)
    local body=self.body
    body:KillAllChildren()
    local top=0
    if data.wand_look~=nil then
        local art=body:AddChild(UIAnim())
        art:SetClickable(false)
        local state=art:GetAnimState()
        -- Preview clips share the ground artwork, centered into 88 x 100 pixels
        -- without grass or shadow. Their placement needs no first-frame bounds.
        require("nw/visual").apply({AnimState=state},data.wand_look,"preview",data.wand_broken)
        art:SetPosition(48,-54)
        top=label(body,data.title,104,0,INNER-104,23,VALUE,true)
        if data.wand_broken then
            top=top+label(body,data.subtitle,104,top,INNER-104,16,LABEL,true)
        else
            top=top+5+badges(body,{data.subtitle},104,top+5,INNER-104)
        end
        top=math.max(108,top)
    elseif data.icon then
        local art=body:AddChild(Image(data.atlas,data.icon))
        art:SetSize(50,50);art:SetPosition(25,-25);art:SetClickable(false)
        local tagwidth=152
        top=label(body,data.title,62,0,INNER-62-tagwidth-12,23,VALUE,true)
        local tags=0
        if data.tags then
            tags=badges(body,data.tags,INNER-tagwidth,0,tagwidth)
        end
        top=math.max(50,top,tags)
    else
        top=label(body,data.title,0,0,INNER,21,VALUE)
    end
    if data.effect then
        top=top+10
        top=top+label(body,data.effect,0,top,INNER,18,VALUE,true)
    end
    if data.fields then
        top=top+9;line(body,top);top=top+8
        local columns=require("nw/locale").language=="en" and 1 or 2
        local labelwidth=columns==1 and 210 or 100
        for i,entry in ipairs(data.fields) do
            local x=(i-1)%columns*INNER/columns
            local y=top+math.floor((i-1)/columns)*25
            label(body,entry[1],x,y,labelwidth,17,LABEL)
            label(body,entry[2],x+labelwidth,y,INNER/columns-labelwidth,18,VALUE)
        end
        top=top+math.ceil(#data.fields/columns)*25
        if data.innate then
            label(body,T("固有法术"),0,top,100,17,LABEL)
            label(body,data.innate,100,top,INNER-100,18,VALUE)
            top=top+25
        end
        if data.slots then
            line(body,top+6);top=top+12
            label(body,T("已装法术"),0,top,100,17,LABEL)
            label(body,data.count,INNER-62,top,62,17,LABEL)
            top=top+25
            local row=body:AddChild(Row(SLOT))
            row:SetCards(data.slots)
            row:SetPosition(row.width/2,-top-SLOT/2)
            top=top+SLOT
        end
    end
    self.height=top+PAD*2
    self.frame:SetSize(WIDTH,self.height)
    body:SetPosition(-WIDTH/2+PAD,self.height/2-PAD)
end
return Panel
