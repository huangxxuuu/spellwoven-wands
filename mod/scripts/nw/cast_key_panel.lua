local C=require("nw/constants/ui").guide
local M={}

function M.attach(screen,label)
    local Binding=require("nw/cast_binding")
    local Key=require("nw/cast_key")
    local L=require("nw/performance_settings").text
    local Button=require("widgets/textbutton")
    local Popup=require("screens/popupdialog")
    local parent=screen.personal
    local panel={}
    screen.binding_panel=panel
    label(parent,C.label_size,L("施法按键","Cast key"),C.label_x,C.cast_key_y,C.label_width,C.label_height):SetHAlign(ANCHOR_LEFT)
    local value=label(parent,C.spinner_size,"",C.cast_value_x,C.cast_key_y,C.cast_value_width,C.label_height)
    value:SetHAlign(ANCHOR_LEFT)
    local button=parent:AddChild(Button())
    button:SetFont(UIFONT);button:SetTextSize(C.spinner_size);button:SetText(L("修改","Change"));button:SetPosition(C.cast_change_x,C.cast_key_y)
    local reset=parent:AddChild(Button())
    reset:SetFont(UIFONT);reset:SetTextSize(C.spinner_size);reset:SetText(L("恢复房主默认","Restore host default"));reset:SetPosition(C.spinner_x,C.cast_record_y)
    local status=label(parent,C.notice_size,"",0,C.cast_status_y,C.notice_width,C.notice_height)
    screen.cast_key,screen.cast_key_capture,screen.cast_key_reset=value,button,reset
    panel.value,panel.button,panel.reset,panel.status=value,button,reset,status
    local capture,refresh,removed

    panel.cancel=function()
        if capture then capture:cancel() end
    end
    local function record()
        if removed or capture or not Binding.ready() or Binding.pending() or screen.active_page~="personal" then return end
        local player=ThePlayer
        if not player then return end
        local popup=Popup(L("录入施法按键","Record cast key"),L("按下鼠标按钮或键盘按键。\nEsc 取消；松开按键后保存。","Press a mouse button or keyboard key.\nEsc cancels; release the key to save."),{},nil,nil,"dark")
        popup.bg:Kill()
        popup.bg=popup.proot:AddChild(require("widgets/nw_wandframe")())
        -- Use local layout dimensions, as the guide does; image metrics and
        -- inherited scale must not be applied again inside the same root.
        popup.bg:SetSize(C.cast_capture_width,C.cast_capture_height);popup.bg:SetPosition(0,C.cast_capture_y)
        popup.bg:SetClickable(false);popup.bg:MoveToBack()
        popup.title:SetPosition(0,C.cast_capture_title_y)
        popup.title:SetRegionSize(C.cast_capture_text_width,C.cast_capture_title_height)
        popup.text:SetPosition(0,C.cast_capture_text_y)
        popup.text:SetRegionSize(C.cast_capture_text_width,C.cast_capture_text_height)
        capture=popup;panel.capture=popup;player._nw_binding_capture=popup
        local armed,candidate,kind,code=false
        local arm_task
        local function cleanup()
            if popup.closed then return false end
            popup.closed=true
            if arm_task then arm_task:Cancel();arm_task=nil end
            if player._nw_binding_capture==popup then player._nw_binding_capture=nil end
            if capture==popup then capture=nil;panel.capture=nil end
            return true
        end
        function popup:cancel()
            if cleanup() then TheFrontEnd:PopScreen(self) end
        end
        popup.OnControl=function() return true end
        local function input(source,value,down)
            if popup.closed then return true end
            if source=="key" and value==KEY_ESCAPE and down then popup:cancel();return true end
            if not armed then return true end
            if candidate then
                if not down and source==kind and value==code then
                    local selected=candidate
                    popup:cancel()
                    if Binding.ready() and not Binding.pending() then Binding.set(selected) end
                    refresh()
                end
                return true
            end
            if not down then return true end
            local encoded=source=="mouse" and Key.mouse(value) or source=="key" and Key.keyboard(value)
            if not encoded or not Key.valid(encoded) then
                popup.text:SetString(L("无法使用这个按键，请重试。\nEsc 取消。","That key cannot be used. Try another.\nEsc cancels."))
                return true
            end
            candidate,kind,code=encoded,source,value
            popup.text:SetString(L("松开后保存：","Release to save: ")..Key.label(encoded))
            return true
        end
        popup.OnRawKey=function(_,key,down) return input("key",key,down) end
        popup.OnMouseButton=function(_,mouse,down) return input("mouse",mouse,down) end
        local inactive,lose=popup.OnBecomeInactive,popup.OnLoseFocus
        local function deactivate(self,previous)
            if cleanup() then
                -- Native PopScreen calls OnBecomeInactive before removing the
                -- screen. Defer removal to avoid recursively popping it there.
                self.inst:DoTaskInTime(0,function()
                    if self.inst:IsValid() then TheFrontEnd:PopScreen(self) end
                end)
            end
            if previous then previous(self) end
        end
        popup.OnBecomeInactive=function(self) deactivate(self,inactive) end
        popup.OnLoseFocus=function(self) deactivate(self,lose) end
        popup.inst:ListenForEvent("onremove",cleanup)
        -- Opening via a button can deliver its raw event to the new screen in
        -- the same input dispatch. Arm on the next update, consuming that event.
        arm_task=popup.inst:DoTaskInTime(0,function() arm_task=nil;armed=true end)
        TheFrontEnd:PushScreen(popup)
    end
    button:SetOnClick(record)
    reset:SetOnClick(function()
        if removed or not Binding.ready() or Binding.pending() then return end
        Binding.set(nil)
        refresh()
    end)
    refresh=function()
        if removed or not screen.inst:IsValid() then return end
        local ready,pending=Binding.ready(),Binding.pending()
        if not ready or pending then panel.cancel() end
        value:SetString(ready and Key.label(Binding.get()) or L("同步中…","Syncing…"))
        if ready and not pending then button:Enable();reset:Enable() else button:Disable();reset:Disable() end
        status:SetString(not ready and L("正在同步施法按键…","Syncing cast key…")
            or pending and L("正在保存，等待服务器确认…","Saving; waiting for server confirmation…")
            or L("施法按键随玩家存档保存。","The cast key saves with your character."))
        reset:SetHoverText(L("恢复使用房主设置的默认施法按键。","Use the host's default cast key.")
            ..(ready and "\n"..L("世界默认：","World default: ")..Key.label(Binding.get_default()) or ""),
            {font=UIFONT,font_size=C.hover_font,colour=screen.text_colour})
    end
    panel.refresh=refresh
    local unsubscribe=Binding.subscribe(refresh)
    screen.inst:ListenForEvent("onremove",function() removed=true;panel.cancel();unsubscribe() end)
    screen.limit_speech:SetFocusChangeDir(MOVE_DOWN,button)
    button:SetFocusChangeDir(MOVE_UP,screen.limit_speech);button:SetFocusChangeDir(MOVE_DOWN,reset)
    reset:SetFocusChangeDir(MOVE_UP,button);reset:SetFocusChangeDir(MOVE_DOWN,screen.menu)
    refresh()
    return panel
end

return M
