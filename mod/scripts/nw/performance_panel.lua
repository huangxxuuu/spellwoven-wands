local C=require("nw/constants/ui").performance_panel
local M={}
function M.attach(screen,label)
    local Settings=require("nw/performance_settings")
    local L=Settings.text
    local Widget=require("widgets/widget")
    local Spinner=require("widgets/spinner")
    local root=screen.proot
    local panel=root:AddChild(Widget("nw_performance"));panel:Hide()
    screen.performance=panel;panel.rows={};panel.page=1
    panel.notice=label(panel,C.notice_size,L("当前世界设置，仅管理员可修改（需开启开发者选项）。\n仅运行时生效，世界重启后恢复模组配置。",
        "Current world settings. Only admins with developer mode can edit.\nRuntime only; restart restores mod configuration."),0,C.notice_y,C.notice_width,C.notice_height)
    local status=label(panel,C.notice_size,"",0,C.status_y,C.notice_width,C.status_height)
    local refresh
    for row=1,#Settings.specs do
        local y=C.row_y-(row-1)*C.row_step
        local title=label(panel,C.label_size,"",C.label_x,y,C.label_width,C.label_height);title:SetHAlign(ANCHOR_LEFT)
        local spinner=panel:AddChild(Spinner({{text="",data=1}},C.spinner_width,C.spinner_height,{font=UIFONT,size=C.spinner_size},false,nil,nil,true))
        spinner:SetPosition(C.spinner_x,y);spinner:SetWrapEnabled(true)
        panel.rows[row]={title=title,spinner=spinner}
        spinner:SetOnChangedFn(function(index)
            if panel.refreshing or not Settings.synced or not Settings.allowed then return end
            local spec=Settings.specs[row]
            Settings.change(spec.key,index);refresh()
        end)
        spinner:SetFocusChangeDir(MOVE_DOWN,screen.menu)
        if row>1 then
            spinner:SetFocusChangeDir(MOVE_UP,panel.rows[row-1].spinner)
            panel.rows[row-1].spinner:SetFocusChangeDir(MOVE_DOWN,spinner)
        else spinner:SetFocusChangeDir(MOVE_UP,screen.tabs.performance) end
    end
    refresh=function()
        if not screen.inst:IsValid() then return end
        panel.refreshing=true
        for row,widgets in ipairs(panel.rows) do
            local spec=Settings.specs[row]
            widgets.title:SetString(L(spec.zh,spec.en))
            local options={}
            if Settings.synced then
                for i,value in ipairs(spec.options) do options[i]={text=Settings.option_text(value),data=i} end
            else options[1]={text=L("同步中…","Syncing…"),data=1} end
            widgets.spinner:SetOptions(options)
            widgets.spinner:SetSelectedIndex(Settings.synced and Settings.index(spec,Settings.value(spec)) or 1)
            if Settings.synced and Settings.allowed and not Settings.pending then widgets.spinner:Enable() else widgets.spinner:Disable() end
            widgets.spinner:SetTextColour(unpack(screen.text_colour))
            local tip=spec.tip and L(unpack(spec.tip)) or L("对后续施法或生成生效，已有实体不会因为调低上限被立即删除。",
                "Applies to future casts or spawns. Lowering the limit does not immediately remove existing entities.")
            screen.option_tip(widgets.spinner,tip)
        end
        local messages={PENDING=L("正在应用…","Applying…"),OK=L("已应用","Applied"),
            BUSY=L("操作太快，请重试。","Too fast; try again."),INVALID=L("设置值无效，请重试。","Invalid setting; try again."),
            UNAVAILABLE=L("主世界未连接，暂时无法同步修改。","Primary world unavailable; cannot apply a synced edit."),
            TIMEOUT=L("未收到确认，请重试。","No confirmation received; try again.")}
        local hint=not Settings.synced and L("正在同步服务器设置…","Syncing server settings…")
            or not Settings.allowed and L("仅查看：开启开发者选项的管理员可修改。","Read only: editing requires developer mode and administrator access.")
            or messages[Settings.status] or L("仅开启同步的世界接收跨世界修改。","Only opted-in worlds apply shared edits.")
        status:SetString(hint)
        panel.refreshing=false
        screen.refresh_navigation()
    end
    panel.refresh=refresh
    local unsubscribe=Settings.subscribe(refresh)
    local task=screen.inst:DoPeriodicTask(C.poll_interval,Settings.poll)
    screen.inst:ListenForEvent("onremove",function() unsubscribe();task:Cancel() end)
    refresh()
    return panel
end
return M
