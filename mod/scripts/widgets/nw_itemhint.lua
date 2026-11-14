local C=require("nw/constants/ui").nw_itemhint
local T=require("nw/locale").t
local Widget=require("widgets/widget")
local Image=require("widgets/image")
local UIAnim=require("widgets/uianim")
local Text=require("widgets/text")
local Frame=require("widgets/nw_wandframe")
local Row=require("widgets/nw_slotrow")
local WIDTH,PAD,SLOT=C.width,C.pad,C.slot
local INNER=WIDTH-PAD*2
local VALUE=C.value
local LABEL=C.label

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

local function label(body,str,x,top,width,size,colour,wrap)
    local t=body:AddChild(Text(UIFONT,size))
    t:SetClickable(false)
    t:SetColour(unpack(colour))
    t:SetHAlign(ANCHOR_LEFT)
    local lines=1
    if wrap then
        lines=t:SetMultilineTruncatedString(str,C.max_lines,width,nil,false)
    else
        t:SetString(tostring(str))
    end
    local height=lines*(size+C.line_padding)
    t:SetRegionSize(width,height)
    t:SetPosition(x+width/2,-top-height/2)
    return height
end
local function line(body,y)
    local img=body:AddChild(Image("images/global.xml","square.tex"))
    img:SetSize(INNER,C.rule_height);img:SetTint(unpack(C.rule_colour))
    img:SetPosition(INNER/2,-y);img:SetClickable(false)
end
local function badges(body,items,x,top,width)
    local dx,dy,rowheight=0,0,0
    for _,str in ipairs(items) do
        local badge=body:AddChild(Widget("hint_badge"))
        badge:SetClickable(false)
        local border=badge:AddChild(Image("images/global.xml","square.tex"))
        local fill=badge:AddChild(Image("images/global.xml","square.tex"))
        local text=badge:AddChild(Text(UIFONT,C.badge_font_size))
        border:SetClickable(false);fill:SetClickable(false);text:SetClickable(false)
        border:SetTint(unpack(C.badge_border_colour))
        fill:SetTint(unpack(C.badge_fill_colour))
        text:SetColour(unpack(VALUE))
        text:SetString(str)
        local measured=text:GetRegionSize()
        local w=math.min(width,measured+C.badge_padding_x)
        local lines=text:SetMultilineTruncatedString(str,C.max_lines,w-C.badge_padding_x,nil,false)
        local h=lines*C.badge_line_height+C.badge_padding_y
        if dx>0 and dx+w>width then dx=0;dy=dy+rowheight+C.badge_gap;rowheight=0 end
        badge.width,badge.height=w,h
        badge:SetPosition(x+dx+w/2,-top-dy-h/2)
        border:SetSize(w,h);fill:SetSize(w-C.badge_border_width,h-C.badge_border_width)
        text:SetRegionSize(w-C.badge_padding_x,h-C.badge_padding_y)
        dx=dx+w+C.badge_gap;rowheight=math.max(rowheight,h)
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
        require("nw/visual").apply({AnimState=state},data.wand_look,"preview",data.wand_broken)
        art:SetPosition(unpack(C.wand_preview_position))
        top=label(body,data.title,C.wand_text_x,0,INNER-C.wand_text_x,C.title_size,VALUE,true)
        if data.wand_broken then
            top=top+label(body,data.subtitle,C.wand_text_x,top,INNER-C.wand_text_x,C.subtitle_size,LABEL,true)
        else
            top=top+C.subtitle_gap+badges(body,{data.subtitle},C.wand_text_x,top+C.subtitle_gap,INNER-C.wand_text_x)
        end
        top=math.max(C.wand_header_height,top)
    elseif data.icon then
        local art=body:AddChild(Image(data.atlas,data.icon))
        art:SetSize(unpack(C.icon_size));art:SetPosition(unpack(C.icon_position));art:SetClickable(false)
        local tagwidth=C.tag_width
        top=label(body,data.title,C.icon_text_x,0,INNER-C.icon_text_x-tagwidth-C.title_tag_gap,C.title_size,VALUE,true)
        local tags=0
        if data.tags then
            tags=badges(body,data.tags,INNER-tagwidth,0,tagwidth)
        end
        top=math.max(C.icon_header_height,top,tags)
    else
        top=label(body,data.title,0,0,INNER,C.plain_title_size,VALUE)
    end
    if data.effect then
        top=top+C.effect_gap
        top=top+label(body,data.effect,0,top,INNER,C.value_size,VALUE,true)
    end
    if data.fields then
        top=top+C.fields_gap;line(body,top);top=top+C.fields_rule_gap
        local columns=require("nw/locale").language=="en" and 1 or 2
        local labelwidth=columns==1 and C.english_label_width or C.label_width
        for i,entry in ipairs(data.fields) do
            local x=(i-1)%columns*INNER/columns
            local y=top+math.floor((i-1)/columns)*C.field_row_height
            label(body,entry[1],x,y,labelwidth,C.label_size,LABEL)
            label(body,entry[2],x+labelwidth,y,INNER/columns-labelwidth,C.value_size,VALUE)
        end
        top=top+math.ceil(#data.fields/columns)*C.field_row_height
        if data.innate then
            label(body,T("固有法术"),0,top,C.label_width,C.label_size,LABEL)
            label(body,data.innate,C.label_width,top,INNER-C.label_width,C.value_size,VALUE)
            top=top+C.field_row_height
        end
        if data.slots then
            line(body,top+C.slots_rule_gap);top=top+C.slots_gap
            label(body,T("已装法术"),0,top,C.label_width,C.label_size,LABEL)
            label(body,data.count,INNER-C.icon_text_x,top,C.icon_text_x,C.label_size,LABEL)
            top=top+C.field_row_height
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
