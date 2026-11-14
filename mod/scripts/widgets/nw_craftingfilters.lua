local C=require("nw/constants/ui").nw_craftingfilters
local Widget=require("widgets/widget")
local Image=require("widgets/image")
local Spinner=require("widgets/spinner")
local ImageButton=require("widgets/imagebutton")
local TextButton=require("widgets/textbutton")
local T=require("nw/locale").t

local WIDTH=C.width
local TAG_ROWS=C.tag_rows
local ROW_GAP=C.row_gap
local GOLD=C.gold
local MUTED=C.muted
local FOCUS=C.focus

local Filters=Class(Widget,function(self,options,onclass,ontag)
    Widget._ctor(self,"nw_craftingfilters")
    self.ontag=ontag
    self.tagbuttons={}
    self.tag_by_id={}

    self.title_backing=self:AddChild(Image("images/ui.xml","option_highlight.tex"))
    self.title_backing:SetPosition(unpack(C.title_position))
    self.title_backing:ScaleToSize(unpack(C.title_size))
    self.title_backing:SetTint(unpack(C.title_colour))
    self.title_backing:SetClickable(false)

    self.spinner=self:AddChild(Spinner(options,C.spinner_size[1],C.spinner_size[2],
        {font=HEADERFONT or UIFONT,size=C.spinner_font_size},false,"images/ui.xml",nil,true,unpack(C.spinner_text_size)))
    self.spinner:SetPosition(unpack(C.spinner_position))
    self.spinner:SetTextColour(GOLD)
    self.spinner:SetWrapEnabled(true)
    self.spinner:SetOnChangedFn(onclass)
    self.spinner.leftimage.scale_on_focus=false
    self.spinner.rightimage.scale_on_focus=false
    self.spinner.leftimage.move_on_click=false
    self.spinner.rightimage.move_on_click=false
    self.focus_forward=self.spinner

    self.rule=self:AddChild(Image("images/ui.xml","line_horizontal_white.tex"))
    self.rule:SetPosition(unpack(C.rule_position))
    self.rule:ScaleToSize(unpack(C.rule_size))
    self.rule:SetTint(unpack(C.rule_colour))
    self.rule:SetClickable(false)

    self.tags=self:AddChild(Widget("tags"))
    self.tags:SetPosition(unpack(C.tags_position))
    local function arrow(direction,x)
        local button=self:AddChild(ImageButton("images/ui.xml","arrow2_"..direction..".tex"))
        button.scale_on_focus=false
        button.move_on_click=false
        button:ForceImageSize(unpack(C.arrow_size))
        button:SetImageNormalColour(unpack(MUTED))
        button:SetImageFocusColour(unpack(FOCUS))
        button:SetPosition(x,C.arrow_y)
        button:SetOnClick(function() self:SetPage(self.page+(direction=="left" and -1 or 1)) end)
        button:Hide()
        return button
    end
    self.prevpage=arrow("left",-C.arrow_x)
    self.nextpage=arrow("right",C.arrow_x)
end)

function Filters:SetChoices(options)
    self.spinner:SetOptions(options)
end

function Filters:SetChoice(choice)
    for i,option in ipairs(self.spinner.options) do
        if option.data==choice then self.spinner:SetSelectedIndex(i);return end
    end
end

local function paint(button)
    button:SetTextColour(button.nw_selected and GOLD or MUTED)
    button:SetTextFocusColour(FOCUS)
    button.text:SetColour(button.focus and FOCUS or button.nw_selected and GOLD or MUTED)
    button.backing:SetTint(C.tag_colour[1],C.tag_colour[2],C.tag_colour[3],button.focus and C.focus_alpha or button.nw_selected and C.selected_alpha or 0)
    if button.nw_selected then button.underline:Show() else button.underline:Hide() end
    button:SetHelpTextMessage(T(button.nw_selected and "取消标签" or "选中标签"))
end

function Filters:MakeTag(id,description)
    local button=self.tags:AddChild(TextButton("nw_tag_"..id))
    button:SetFont(UIFONT)
    button:SetTextSize(unpack(C.tag_text_size))
    button.scale_on_focus=false
    button.move_on_click=false
    button.backing=button:AddChild(Image("images/ui.xml","option_highlight.tex"))
    button.backing:MoveToBack()
    button.backing:SetClickable(false)
    button.underline=button:AddChild(Image("images/ui.xml","line_horizontal_white.tex"))
    button.underline:SetPosition(unpack(C.underline_position))
    button.underline:SetTint(unpack(GOLD))
    button.underline:SetClickable(false)
    local gain,lose=button.OnGainFocus,button.OnLoseFocus
    button.OnGainFocus=function(b) gain(b);paint(b) end
    button.OnLoseFocus=function(b) lose(b);paint(b) end
    button:SetOnClick(function() self.ontag(id) end)
    return button
end

local function pack_rows(buttons,limit)
    local rows={{}}
    local width=0
    for _,button in ipairs(buttons) do
        local size=math.min(button.nw_width,limit)
        if #rows[#rows]>0 and width+size>limit then
            rows[#rows+1]={};width=0
        end
        table.insert(rows[#rows],button)
        width=width+size
    end
    return rows
end

function Filters:SetTags(list,selected)
    local buttons={}
    local used={}
    for _,tag in ipairs(list) do
        local button=self.tag_by_id[tag.id]
        if not button then
            button=self:MakeTag(tag.id,tag.description)
            self.tag_by_id[tag.id]=button
        end
        used[tag.id]=true
        button:Show()
        button:SetText(tag.text)
        local textwidth=button.text:GetRegionSize()
        button.nw_width=textwidth+C.tag_padding
        button.image:SetSize(button.nw_width,C.tag_height)
        button.backing:ScaleToSize(button.nw_width+C.backing_padding,C.tag_height)
        button.underline:ScaleToSize(math.max(C.underline_min_width,textwidth),C.underline_height)
        button.nw_selected=selected[tag.id]==true
        paint(button)
        buttons[#buttons+1]=button
    end
    for id,button in pairs(self.tag_by_id) do
        if not used[id] then
            if button.focus then button:ClearFocus();self.spinner:SetFocus() end
            button:Hide()
        end
    end
    local ids={}
    for _,tag in ipairs(list) do ids[#ids+1]=tag.id end
    local key=table.concat(ids,",")
    if key~=self.listkey then self.page=1;self.listkey=key end
    self.allbuttons=buttons
    local rows=pack_rows(buttons,WIDTH)
    self.row_limit=#rows>TAG_ROWS and WIDTH-C.page_arrow_reserve or WIDTH
    if self.row_limit<WIDTH then rows=pack_rows(buttons,self.row_limit) end
    self.pages={}
    for i,row in ipairs(rows) do
        local page=math.floor((i-1)/TAG_ROWS)+1
        self.pages[page]=self.pages[page] or {}
        table.insert(self.pages[page],row)
    end
    self:SetPage(self.page or 1)
end

function Filters:SetPage(page)
    self.page=(page-1)%#self.pages+1
    local rows=self.pages[self.page]
    local buttons={}
    local visible={}
    for r,row in ipairs(rows) do
        local width=0
        for _,button in ipairs(row) do width=width+math.min(button.nw_width,self.row_limit) end
        local x=-width/2
        for _,button in ipairs(row) do
            local size=math.min(button.nw_width,self.row_limit)
            button:SetScale(size/button.nw_width)
            button.nw_x=x+size/2
            button:SetPosition(button.nw_x,-(r-1)*ROW_GAP)
            x=x+size
            visible[button]=true
            buttons[#buttons+1]=button
        end
    end
    for _,button in ipairs(self.allbuttons) do
        if visible[button] then button:Show() else
            if button.focus then button:ClearFocus();self.spinner:SetFocus() end
            button:Hide()
        end
    end
    local paged=#self.pages>1
    for _,button in ipairs({self.prevpage,self.nextpage}) do
        if paged then button:Show() else
            if button.focus then button:ClearFocus();self.spinner:SetFocus() end
            button:Hide()
        end
    end
    self.tagbuttons=buttons
    self.tagrows=rows
    self:UpdateNavigation()
end

function Filters:HasFilterFocus()
    if self.spinner.focus or self.prevpage.focus or self.nextpage.focus then return true end
    for _,button in ipairs(self.tagbuttons) do if button.focus then return true end end
    return false
end

function Filters:GetHelpText()
    for _,button in ipairs(self.tagbuttons) do
        if button.focus then return button:GetHelpText() end
    end
    return self.spinner:GetHelpText()
end

function Filters:SetNavigation(up,down)
    self.up,self.down=up,down
    self:UpdateNavigation()
end

function Filters:UpdateNavigation()
    if not self.up or not self.down then return end
    self.spinner:SetFocusChangeDir(MOVE_UP,self.up)
    self.spinner:SetFocusChangeDir(MOVE_DOWN,self.tagbuttons[1] or self.down)
    local function nearest(row,x,fallback)
        local best,distance=fallback,math.huge
        for _,button in ipairs(row or {}) do
            local delta=math.abs(button.nw_x-x)
            if delta<distance then best,distance=button,delta end
        end
        return best
    end
    local rows=self.tagrows or {}
    local paged=self.pages and #self.pages>1
    for r,row in ipairs(rows) do
        for i,button in ipairs(row) do
            button:SetFocusChangeDir(MOVE_UP,nearest(rows[r-1],button.nw_x,self.spinner))
            button:SetFocusChangeDir(MOVE_DOWN,nearest(rows[r+1],button.nw_x,self.down))
            button:SetFocusChangeDir(MOVE_LEFT,row[i-1] or paged and self.prevpage or row[#row])
            button:SetFocusChangeDir(MOVE_RIGHT,row[i+1] or paged and self.nextpage or row[1])
        end
    end
    if paged then
        for _,button in ipairs({self.prevpage,self.nextpage}) do
            local x=button==self.prevpage and -WIDTH or WIDTH
            button:SetFocusChangeDir(MOVE_UP,nearest(rows[1],x,self.spinner))
            button:SetFocusChangeDir(MOVE_DOWN,nearest(rows[2],x,self.down))
        end
        self.prevpage:SetFocusChangeDir(MOVE_RIGHT,rows[1][1])
        self.prevpage:SetFocusChangeDir(MOVE_LEFT,self.nextpage)
        self.nextpage:SetFocusChangeDir(MOVE_LEFT,rows[1][#rows[1]])
        self.nextpage:SetFocusChangeDir(MOVE_RIGHT,self.prevpage)
    end
end

return Filters
