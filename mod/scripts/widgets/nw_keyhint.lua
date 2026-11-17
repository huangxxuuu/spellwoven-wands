local Widget=require("widgets/widget")
local Text=require("widgets/text")
local Image=require("widgets/image")
local Key=require("nw/cast_key")
local C=require("nw/constants/ui").keyhint

local KeyHint=Class(Widget,function(self,font,size)
    Widget._ctor(self,"NWKeyHint")
    self.font=font or UIFONT
    self.size=size or C.default_size
    self.cap_left=self:AddChild(Image(C.atlas,"keycap_small_left.tex"))
    self.cap_center=self:AddChild(Image(C.atlas,"keycap_small_center.tex"))
    self.cap_right=self:AddChild(Image(C.atlas,"keycap_small_right.tex"))
    self.variant="small"
    self.key_text=self:AddChild(Text(DIALOGFONT or self.font,self.size*C.key_size_ratio))
    self.suffix_text=self:AddChild(Text(self.font,self.size))
    self.plain_text=self:AddChild(Text(self.font,self.size))
    self.key_text:SetColour(unpack(C.key_colour))
    for _,child in ipairs({self.cap_left,self.cap_center,self.cap_right,self.key_text,self.suffix_text,self.plain_text}) do child:SetClickable(false) end
    self:SetClickable(false)
    self:SetString("")
end)

function KeyHint:Layout()
    local start=-self.width/2
    if self.halign~=nil and self.halign==ANCHOR_LEFT then start=0
    elseif self.halign~=nil and self.halign==ANCHOR_RIGHT then start=-self.width end
    if not self.keyboard then
        self.plain_text:SetPosition(start+self.width/2,0)
        return
    end
    local height=self.size*C.height_ratio
    local left=height*C.left_source_width/C.source_height
    local right=height*C.right_source_width/C.source_height
    local center=self.cap_width-left-right
    self.cap_left:SetSize(left,height);self.cap_left:SetPosition(start+left/2,0)
    self.cap_center:SetSize(center,height);self.cap_center:SetPosition(start+left+center/2,0)
    self.cap_right:SetSize(right,height);self.cap_right:SetPosition(start+self.cap_width-right/2,0)
    self.key_text:SetPosition(start+self.cap_width/2+height*C.key_x_ratio,height*C.key_y_ratio)
    local suffix_width=self.suffix_text:GetRegionSize()
    self.suffix_text:SetPosition(start+self.cap_width+self.gap+suffix_width/2,0)
end

function KeyHint:SetBinding(value,suffix)
    self.binding=value
    local kind=Key.decode(value)
    self.keyboard=kind=="key"
    local name=self.keyboard and Key.label(value) or Key.hint(value) or ""
    suffix=suffix or ""
    self.string=name..(suffix~="" and ": "..suffix or "")
    if not self.keyboard then
        self:SetString(self.string)
        self.binding=value
        return self
    end
    self.plain_text:Hide()
    for _,child in ipairs({self.cap_left,self.cap_center,self.cap_right,self.key_text}) do child:Show() end
    -- Size Chinese key names separately; Latin labels (L, Tab, F5) retain their
    -- size even in the Chinese UI. Apply the size before measuring the label.
    local chinese=name:find("[\228-\233][\128-\191][\128-\191]")~=nil
    self.key_text:SetSize(self.size*C.key_size_ratio*(chinese and C.chinese_key_size_scale or 1))
    self.key_text:SetString(name)
    self.suffix_text:SetString(suffix)
    if suffix~="" then self.suffix_text:Show() else self.suffix_text:Hide() end
    local key_width=self.key_text:GetRegionSize()
    local suffix_width,suffix_height=self.suffix_text:GetRegionSize()
    local height=self.size*C.height_ratio
    local base_width=height*C.base_source_width/C.source_height
    local required_width=key_width+height*C.label_clearance_ratio
    -- Measure the current localized label in its display font, so Chinese and
    -- English select independently. Keep only the edge clearance when choosing
    -- the narrowest face; do not assign a shared width by key code or length.
    local variant=C.variant_order[#C.variant_order]
    for _,candidate in ipairs(C.variant_order) do
        if required_width<=base_width*C.variants[candidate].width_ratio then
            variant=candidate
            break
        end
    end
    if self.variant~=variant then
        for part,image in pairs({left=self.cap_left,center=self.cap_center,right=self.cap_right}) do
            image:SetTexture(C.atlas,"keycap_"..variant.."_"..part..".tex")
        end
        self.variant=variant
    end
    self.cap_width=math.max(base_width*C.variants[variant].width_ratio,required_width)
    self.gap=suffix~="" and self.size*C.suffix_gap_ratio or 0
    self.width=self.cap_width+self.gap+(suffix~="" and suffix_width or 0)
    self.height=math.max(height,suffix~="" and suffix_height or 0)
    self:Layout()
    return self
end

function KeyHint:SetString(value)
    self.binding=nil;self.keyboard=false;self.string=value or ""
    for _,child in ipairs({self.cap_left,self.cap_center,self.cap_right,self.key_text,self.suffix_text}) do child:Hide() end
    self.plain_text:SetString(self.string);self.plain_text:Show()
    self.width,self.height=self.plain_text:GetRegionSize()
    self:Layout()
    return self
end

function KeyHint:GetString() return self.string end
function KeyHint:GetRegionSize() return self.width,self.height end
function KeyHint:SetColour(...) self.plain_text:SetColour(...);self.suffix_text:SetColour(...) end
function KeyHint:SetHAlign(align) self.halign=align;self:Layout() end

return KeyHint
