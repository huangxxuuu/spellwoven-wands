local C=require("nw/constants/ui").cast_hover
local Binding=require("nw/cast_binding")
local Key=require("nw/cast_key")
local Cast=require("nw/cast_action")
local Input=require("nw/cast_input")
local M={}

local function native_string(act)
    if not act then return end
    local control=TheInput:GetLocalizedControl(TheInput:GetControllerID(),CONTROL_SECONDARY)
    if act.action.show_secondary_input_right then return act:GetActionString().." "..control end
    if act.action~=ACTIONS.CASTAOE then return control..": "..act:GetActionString() end
end

function M.install(hover)
    if hover.nw_cast_text then return end
    local KeyHint=require("widgets/nw_keyhint")
    local hint=hover:AddChild(KeyHint(UIFONT,C.text_size))
    hint:SetClickable(false)
    hint:SetColour(unpack(NORMAL_TEXT_COLOUR))
    hint:Hide()
    hover.nw_cast_text=hint
    local update,position=hover.OnUpdate,hover.UpdatePosition
    local replaced,native_secondary=false,nil
    local layout=false

    local function replace_secondary(self,value)
        if not replaced then native_secondary=self.secondarystr;replaced=true end
        self.secondarystr=value
        if value then self.secondarytext:SetString(value);self.secondarytext:Show()
        else self.secondarytext:Hide() end
    end

    hover.UpdatePosition=function(self,x,y)
        position(self,x,y)
        if not layout then return end
        -- The native clamp knows only its two original lines. Account for the
        -- extra line's actual offset/size and inherited HUD scale at all edges.
        local scale=self:GetScale()
        local left,right,bottom,top
        for _,text in ipairs({self.text,self.secondarytext,hint}) do
            if text.shown then
                local pos=text:GetPosition()
                local w,h=text:GetRegionSize()
                local l,r=(pos.x-w/2)*scale.x,(pos.x+w/2)*scale.x
                local b,t=(pos.y-h/2)*scale.y,(pos.y+h/2)*scale.y
                left=left and math.min(left,l) or l;right=right and math.max(right,r) or r
                bottom=bottom and math.min(bottom,b) or b;top=top and math.max(top,t) or t
            end
        end
        if left then
            local sw,sh=TheSim:GetScreenSize()
            local pos=self:GetPosition()
            self:SetPosition(math.clamp(pos.x,C.screen_margin-left,sw-C.screen_margin-right),
                math.clamp(pos.y,C.screen_margin-bottom,sh-C.screen_margin-top),0)
        end
    end

    hover.OnUpdate=function(self,...)
        hint:Hide();layout=false
        -- Restore only presentation state before the native widget updates;
        -- never substitute playercontroller actions or send an input/RPC.
        if replaced then
            self.secondarystr=native_secondary
            replaced,native_secondary=false,nil
        end
        update(self,...)
        local p=self.owner
        local pc=p and p.components and p.components.playercontroller
        if self.isFE or not self.shown or self.forcehide or not pc or not Binding.ready()
            or not Input.world_input(pc) or not Cast.hand(p)
            or p.HUD.controls:GetTooltip()~=nil or pc:GetHoverTextOverride()~=nil then return end
        local key=Binding.get()
        if not Key.valid(key) then return end
        local action=Cast.input_action(p)
        local cancast=action and action.action==ACTIONS.NW_CAST
        local rmb=pc:GetRightMouseAction()
        local same=Key.matches_control(key,CONTROL_SECONDARY)
        if same and cancast and rmb and rmb.action==ACTIONS.NW_CAST and Key.decode(key)~="key" then
            -- The native line already uses exactly the configured button glyph.
            return
        end
        if same and (cancast or key~="mouse:1001") then
            -- One physical key cannot advertise both a cast and the secondary
            -- action whose control event the dedicated binding consumes.
            replace_secondary(self,nil)
        elseif rmb and rmb.action==ACTIONS.NW_CAST then
            -- A physical RMB cast can differ from a remapped secondary button.
            -- Show that button's actual native action, not a stale cast label.
            replace_secondary(self,native_string(Cast.input_action(p,true)))
        end
        if cancast then
            hint:SetBinding(key,action:GetActionString())
            local at=self.secondarytext:GetPosition()
            local y=at.y
            local _,hint_height=hint:GetRegionSize()
            for _,text in ipairs({self.text,self.secondarytext}) do
                if text.shown then
                    local _,height=text:GetRegionSize()
                    y=math.min(y,text:GetPosition().y-(height+hint_height)/2-C.line_gap)
                end
            end
            hint:SetPosition(at.x,y,at.z or 0)
            hint:Show()
        end
        layout=hint.shown or replaced
        if layout then
            local pos=TheInput:GetScreenPosition()
            self:UpdatePosition(pos.x,pos.y)
        end
    end
end
return M
