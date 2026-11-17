-- Exercise the production three-slice widget using measurable UI shells.
UIFONT="font";DIALOGFONT="dialog";ANCHOR_LEFT=1;ANCHOR_RIGHT=2
Class=function(base,ctor)
    local cls={_ctor=ctor};cls.__index=cls
    return setmetatable(cls,{__index=base,__call=function(_,...) local self=setmetatable({},cls);ctor(self,...);return self end})
end
local Widget={}
function Widget._ctor(self) self.shown=true;self.children={} end
function Widget:AddChild(w) self.children[#self.children+1]=w;return w end
function Widget:SetPosition(x,y) self.x=x;self.y=y end
function Widget:SetSize(w,h) self.width=w;self.height=h end
function Widget:SetColour(...) self.colour={...} end
function Widget:SetClickable() end
function Widget:Show() self.shown=true end
function Widget:Hide() self.shown=false end
local Text=Class(Widget,function(self,font,size,text) Widget._ctor(self);self.font=font;self.size=size;self.string=text or "" end)
function Text:SetString(text) self.string=text end
function Text:GetString() return self.string end
function Text:SetSize(size) self.size=size end
local measured_widths={}
function Text:GetRegionSize()
    if measured_widths[self.string] then return measured_widths[self.string],self.size*1.1 end
    local width=0
    for glyph in self.string:gmatch("[\1-\127\194-\244][\128-\191]*") do
        local ratio=#glyph>1 and 1 or (glyph=="I" or glyph=="i" or glyph=="l") and .22
            or (glyph=="W" or glyph=="M") and .95 or .55
        width=width+self.size*ratio
    end
    return width,self.size*1.1
end
local Image=Class(Widget,function(self,atlas,texture) Widget._ctor(self);self.atlas=atlas;self.texture=texture end)
function Image:SetTexture(atlas,texture) self.atlas=atlas;self.texture=texture end
package.loaded["widgets/widget"]=Widget;package.loaded["widgets/text"]=Text;package.loaded["widgets/image"]=Image
package.loaded["nw/locale"]={language="en"}
STRINGS={UI={CONTROLSSCREEN={INPUTS={{[1002]="native-middle-glyph",[1005]="native-mouse4-glyph"}}}}}
local C=require("nw/constants/ui").keyhint
local Key=require("nw/cast_key")
local KeyHint=require("widgets/nw_keyhint")
local function fitting_variant(label_width,height)
    local required=label_width+height*C.label_clearance_ratio
    local base=height*C.base_source_width/C.source_height
    if required<=base*C.variants.small.width_ratio then return "small" end
    if required<=base*C.variants.medium.width_ratio then return "medium" end
    return "wide"
end
for _,size in ipairs({18,30}) do
    local hint=KeyHint(UIFONT,size)
    local first_width
    for _,item in ipairs({{107,"K"},{286,"F5"},{9,"Tab"},{32,"Space"},{8,"Backspace"}}) do
        hint:SetBinding("key:"..item[1],"Cast")
        assert(hint.key_text:GetString()==item[2] and hint.key_text.size==size*C.key_size_ratio)
        assert(hint.key_text.font==DIALOGFONT,"long key names use the legible native dialog font")
        assert(hint.suffix_text:GetString()=="Cast" and hint.suffix_text.size==size)
        assert(hint.key_text.colour[1]==C.key_colour[1],"key names use the native mouse highlight colour")
        local label_width=hint.key_text:GetRegionSize()
        local height=size*C.height_ratio
        local expected=fitting_variant(label_width,height)
        local baseline=height*C.base_source_width/C.source_height*C.variants[expected].width_ratio
        assert(hint.variant==expected,"choose the smallest cap fitting the measured label")
        assert(hint.cap_width==math.max(baseline,label_width+height*C.label_clearance_ratio),"long names widen center without shrinking letters")
        assert(hint.cap_left.height==height and hint.cap_right.height==height)
        assert(hint.cap_left.width/height==32/128 and hint.cap_right.width/height==48/128,"asymmetric ends preserve source proportions")
        assert(math.abs(hint.cap_center.width+hint.cap_left.width+hint.cap_right.width-hint.cap_width)<1e-9,"only the center fills variable width")
        assert(hint.cap_left.atlas=="images/nw_keycap.xml" and hint.cap_center.texture=="keycap_"..expected.."_center.tex")
        assert(hint.cap_right.texture=="keycap_"..expected.."_right.tex")
        assert(math.abs(hint.key_text.x-(hint.cap_left.x-hint.cap_left.width/2+hint.cap_width/2+height*C.key_x_ratio))<1e-9
            and hint.key_text.y==height*C.key_y_ratio,"key name sits on the transparent top face")
        assert(#hint.children==6,"keycaps must use the transparent slices without a rectangular backing")
        assert(hint.suffix_text.x>hint.key_text.x and not hint.plain_text.shown)
        if item[1]==107 then first_width=hint.cap_width end
        if item[1]==8 then assert(hint.cap_width>first_width*2,"long names widen the cap instead of shrinking text") end
    end
    hint:SetBinding("key:8")
    local width=hint:GetRegionSize()
    assert(not hint.suffix_text.shown and width==hint.cap_width)
    hint:SetHAlign(ANCHOR_LEFT)
    assert(hint.cap_left.x-hint.cap_left.width/2==0,"left alignment uses the supplied widget origin")
    hint:SetColour(.1,.2,.3,1)
    assert(hint.key_text.colour[1]==C.key_colour[1] and hint.suffix_text.colour[1]==.1)
    hint:SetBinding("mouse:1002","Cast")
    assert(not hint.cap_left.shown and hint.plain_text.shown and hint:GetString()=="native-middle-glyph: Cast")
    hint:SetBinding("mouse:1007")
    assert(hint:GetString()==Key.label("mouse:1007") and not hint.cap_center.shown)
    hint:SetString("Syncing…")
    assert(not hint.binding and hint:GetString()=="Syncing…" and not hint.cap_right.shown)
    require("nw/locale").language="zh"
    hint:SetBinding("key:8")
    assert(hint.key_text:GetString()=="退格" and hint.key_text.size==size*C.key_size_ratio*C.chinese_key_size_scale and hint.variant=="wide")
    local chinese_width=hint.cap_width
    require("nw/locale").language="en";hint:SetBinding("key:8")
    assert(hint.variant=="wide" and hint.cap_width>chinese_width,"same key changes cap with the rendered language width")
    require("nw/locale").language="zh"
    hint:SetBinding("key:32");assert(hint.key_text:GetString()=="空格" and hint.variant=="wide")
    require("nw/locale").language="en"
    local names=STRINGS.UI.CONTROLSSCREEN.INPUTS[1]
    names[258],names[259]="III","WWW"
    hint:SetBinding("key:258");assert(hint.variant=="small")
    local narrow=hint.cap_width
    hint:SetBinding("key:259")
    assert(hint.variant=="wide" and hint.cap_width>narrow,"equal character counts with different glyph widths must choose different caps")
    local height=size*C.height_ratio
    local base=height*C.base_source_width/C.source_height
    local clearance=height*C.label_clearance_ratio
    names[258]="Boundary"
    for _,variant in ipairs({"small","medium","wide"}) do
        local limit=base*C.variants[variant].width_ratio
        measured_widths.Boundary=limit-clearance
        hint:SetBinding("key:258")
        assert(hint.variant==variant and math.abs(hint.cap_width-limit)<1e-9,"exact-fit boundary selects the smallest containing cap")
        measured_widths.Boundary=limit-clearance+.001
        hint:SetBinding("key:258")
        local next_variant=variant=="small" and "medium" or "wide"
        assert(hint.variant==next_variant,"just-over-boundary label must advance to the next fitting cap")
    end
    measured_widths.Boundary=base*4
    hint:SetBinding("key:258")
    assert(hint.variant=="wide" and hint.cap_width==base*4+clearance,"oversized label expands only the wide center")
    assert(hint.key_text.size==size*C.key_size_ratio and hint.cap_left.width==height*32/128
        and hint.cap_right.width==height*48/128,"oversized label never shrinks letters or resizes end proportions")
    measured_widths.Boundary=nil
end
print("keyhint: rendered-width selection, III/WWW, bilingual key widths, exact-fit boundaries, oversized center expansion, three variants, asymmetric slices, fixed fonts and mouse glyph/fallback")
