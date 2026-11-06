local T=require("nw/locale").t
local Widget=require("widgets/widget")
local Image=require("widgets/image")
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
function Panel:Display(data)
    local body=self.body
    body:KillAllChildren()
    local top=0
    if data.icon then
        local plate=body:AddChild(Image("images/hud.xml","inv_slot.tex"))
        plate:SetClickable(false);plate:SetSize(46,46);plate:SetPosition(23,-23)
        local art=plate:AddChild(Image(data.atlas,data.icon))
        art:SetSize(40,40);art:SetClickable(false)
        top=label(body,data.title,58,0,INNER-58,23,VALUE,true)
        top=math.max(46,top+label(body,data.subtitle,58,top,INNER-58,16,LABEL))
    else
        top=label(body,data.title,0,0,INNER,21,VALUE)
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
        line(body,top+6);top=top+12
        if data.slots then
            label(body,T("已装法术"),0,top,100,17,LABEL)
            label(body,data.count,INNER-62,top,62,17,LABEL)
            top=top+25
            local row=body:AddChild(Row(SLOT))
            row:SetCards(data.slots)
            row:SetPosition(row.width/2,-top-SLOT/2)
            top=top+SLOT
        else
            top=top+label(body,T("效果"),0,top,INNER,17,LABEL)+2
            top=top+label(body,data.effect,0,top,INNER,18,VALUE,true)
        end
    end
    self.height=top+PAD*2
    self.frame:SetSize(WIDTH,self.height)
    body:SetPosition(-WIDTH/2+PAD,self.height/2-PAD)
end
return Panel
