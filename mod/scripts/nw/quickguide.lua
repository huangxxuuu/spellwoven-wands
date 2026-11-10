local M={}
function M.open()
    local T=require("nw/locale").t
    local Popup=require("screens/popupdialog")
    local Widget=require("widgets/widget")
    local Image=require("widgets/image")
    local Button=require("widgets/textbutton")
    local Spinner=require("widgets/spinner")
    local Text=require("widgets/text")
    local Direction=require("nw/cast_direction")
    local Trail=require("nw/trail_budget")
    local Feedback=require("nw/limit_feedback")
    local Settings=require("nw/performance_settings")
    local L=Settings.text
    local screen=Popup(T("织法之杖"),"",{
        {text=T("资料站"),cb=function() VisitURL("https://huangxxuuu.github.io/spellwoven-wands/"..(require("nw/locale").language=="en" and "en/" or ""),false) end},
        {text=T("关闭"),cb=function() TheFrontEnd:PopScreen() end},
    },nil,nil,"dark")
    local root=screen.proot
    local gold={.91,.75,.39,1}
    local cream={.92,.89,.80,1}
    screen.title:SetPosition(0,242);screen.title:SetSize(30);screen.title:SetColour(unpack(gold))
    screen.bg:Kill()
    screen.bg=root:AddChild(require("widgets/nw_wandframe")())
    screen.bg:SetSize(720,580);screen.bg:SetClickable(false);screen.bg:MoveToBack()
    screen.menu:SetPosition(-100,-249)
    local function label(parent,size,value,x,y,width,height,colour)
        local text=parent:AddChild(Text(UIFONT,size,value))
        text:SetPosition(x,y);text:SetColour(unpack(colour or cream));text:SetClickable(false)
        if width then text:EnableWordWrap(true);text:SetRegionSize(width,height) end
        return text
    end
    local function rule(parent,y,width)
        local image=parent:AddChild(Image("images/global.xml","square.tex"))
        image:SetSize(width or 620,1);image:SetPosition(0,y);image:SetTint(.43,.34,.22,1);image:SetClickable(false)
        return image
    end
    -- Native Text hover buttons are sized once; resize after every choice change
    -- and keep their hit area clear of both arrows (also for read-only spinners).
    screen.option_tip=function(spinner,tip)
        spinner.text:SetHoverText(tip,{font=UIFONT,font_size=17,colour=cream,
            region_w=460,region_h=160,wordwrap=true,offset_x=-150,offset_y=70})
        if spinner.text.hover then
            local w,h=spinner.text:GetRegionSize()
            spinner.text.hover.image:ScaleToSize(math.min(w,spinner.width-2*spinner.height-12),h)
        end
    end
    screen.text_colour=cream
    rule(root,174);rule(root,-215)
    local guide=root:AddChild(Widget("nw_guide_content"))
    local personal=root:AddChild(Widget("nw_personal_settings"));personal:Hide()
    screen.guide,screen.personal=guide,personal
    -- The introduction contains only the three buildings, with consistent rows.
    local rows={
        {"nw_workbench",T("奥术台"),L("制作法杖与法术卡，装配法术组合。\n在炼金引擎旁制作。","Craft wands and spell cards; assemble spell combinations.\nCraft beside an Alchemy Engine.")},
        {"nw_engraver",T("武器刻印台"),L("将武器和工具刻成对应法术卡。\n在炼金引擎旁制作。","Turn weapons and tools into matching spell cards.\nCraft beside an Alchemy Engine.")},
        {"nw_disassembler",T("奥术分解炉"),L("回收地面上的法术卡与法杖。\n在炼金引擎旁制作。","Recycle spell cards and wands placed on the ground.\nCraft beside an Alchemy Engine.")},
    }
    for i,row in ipairs(rows) do
        local row_height=(174-(-215))/#rows
        local y=174-(i-.5)*row_height
        local pic=guide:AddChild(Image("images/nw_guide.xml",row[1]..".tex"))
        pic:SetSize(84,84);pic:SetPosition(-266,y);pic:SetClickable(false)
        label(guide,23,row[2],35,y+25,460,32,gold):SetHAlign(ANCHOR_LEFT)
        label(guide,18,row[3],35,y-20,460,72):SetHAlign(ANCHOR_LEFT)
        if i<3 then rule(guide,174-i*row_height) end
    end

    label(personal,16,L("仅影响自己，自动保存到本机。","Only affects you. Preferences save on this device."),0,147,620,36)
    local heading=label(personal,18,T("施法方向"),-150,97,310,34)
    heading:SetHAlign(ANCHOR_LEFT)
    local direction=personal:AddChild(Spinner({
        {text=T("目标选择"),data="target"},
        {text=T("鼠标方向"),data="mouse"},
    },250,34,{font=UIFONT,size=18},false,nil,nil,true))
    direction:SetPosition(175,97);direction:SetTextColour(unpack(cream));direction:SetWrapEnabled(true)
    screen.direction=direction
    local descriptions={
        target=T("选中物体时，朝它脚下施法。\n指着 Boss 头部，也会瞄准脚下。\n无目标时，朝鼠标地面点施法。"),
        mouse=T("始终朝鼠标对应的地面点施法。\n不受树冠等物体的选中影响；\n指着物体上半身时，可能打偏。"),
    }
    local function refresh_direction()
        if not screen.inst:IsValid() then return end
        local mode=Direction.get()
        direction:SetSelectedIndex(mode=="mouse" and 2 or 1)
        local tip=descriptions[mode].."\n\n"..T("自动保存，停止切换 1 秒后应用。\n不影响世界设置或其他玩家。")
        screen.option_tip(direction,tip)
    end
    direction:SetOnChangedFn(function(value) Direction.set(value);refresh_direction() end)
    local spec=Settings.trail_spec
    local trail_heading=label(personal,18,L(spec.zh,spec.en),-150,43,310,34)
    trail_heading:SetHAlign(ANCHOR_LEFT)
    local options={}
    for i,value in ipairs(spec.options) do options[i]={text=Settings.option_text(value),data=value} end
    local trail=personal:AddChild(Spinner(options,250,34,{font=UIFONT,size=18},false,nil,nil,true))
    trail:SetPosition(175,43);trail:SetTextColour(unpack(cream));trail:SetWrapEnabled(true)
    screen.trail_limit=trail
    local tip=L(unpack(spec.tip)).."\n"..L("立即生效，自动保存到本机。","Applies immediately and saves on this device.")
    local function refresh_trail()
        if screen.inst:IsValid() then
            trail:SetSelectedIndex(Settings.index(spec,Trail.limit))
            screen.option_tip(trail,tip)
        end
    end
    trail:SetOnChangedFn(function(value) Trail.set(value);refresh_trail() end)
    refresh_trail();Trail.load(refresh_trail)
    label(personal,18,L("限制触发时角色说话","Character speech on spell limits"),-150,-11,310,34):SetHAlign(ANCHOR_LEFT)
    local speech=personal:AddChild(Spinner({{text=L("关闭","Off"),data=false},{text=L("开启","On"),data=true}},250,34,{font=UIFONT,size=18},false,nil,nil,true))
    speech:SetPosition(175,-11);speech:SetTextColour(unpack(cream));speech:SetWrapEnabled(true)
    screen.limit_speech=speech
    local function refresh_speech()
        if screen.inst:IsValid() then speech:SetSelectedIndex(Feedback.enabled and 2 or 1) end
    end
    speech:SetOnChangedFn(function(value) Feedback.set(value);refresh_speech() end)
    screen.option_tip(speech,L("仅在实体数量或载荷层数限制实际生效时说话。每位玩家最多每30秒一次。自动保存到本机。",
        "Speak only when an entity or payload-depth limit takes effect. At most once per player every 30 seconds. Saved on this device."))
    refresh_speech();Feedback.load(refresh_speech)
    direction:SetFocusChangeDir(MOVE_DOWN,trail)
    trail:SetFocusChangeDir(MOVE_UP,direction)
    trail:SetFocusChangeDir(MOVE_DOWN,speech)
    speech:SetFocusChangeDir(MOVE_UP,trail)
    speech:SetFocusChangeDir(MOVE_DOWN,screen.menu)
    refresh_direction();Direction.load(refresh_direction)

    screen.tabs={}
    local marks={}
    local pages={guide=guide,personal=personal}
    local order={"guide","personal","performance"}
    local function focus_target(key)
        if key=="personal" then return direction,speech end
        if key=="performance" and Settings.synced and Settings.allowed and not Settings.pending then
            return screen.performance.rows[1].spinner,screen.performance.rows[#Settings.specs].spinner
        end
        return screen.menu,screen.tabs[key]
    end
    screen.refresh_navigation=function()
        for _,key in ipairs(order) do
            local first=focus_target(key)
            screen.tabs[key]:SetFocusChangeDir(MOVE_DOWN,first)
        end
        local _,last=focus_target(screen.active_page or "guide")
        screen.menu:SetFocusChangeDir(MOVE_UP,last)
    end
    screen.select_page=function(key)
        if not pages[key] then return end
        screen.active_page=key
        for _,id in ipairs(order) do
            local active=id==key
            if active then pages[id]:Show();marks[id]:Show() else pages[id]:Hide();marks[id]:Hide() end
            screen.tabs[id]:SetColour(unpack(active and gold or cream))
        end
        screen.performance.active=key=="performance"
        screen.refresh_navigation()
        if key=="performance" then Settings.query() end
    end
    local titles={guide=L("向导","Guide"),personal=L("个人设置","Personal settings"),performance=L("全局性能设置","Global performance")}
    for i,key in ipairs(order) do
        local x=(i-2)*214
        local button=root:AddChild(Button());button:SetFont(UIFONT);button:SetTextSize(21)
        button:SetText(titles[key]);button:SetPosition(x,198);button:SetOnClick(function() screen.select_page(key) end)
        screen.tabs[key]=button
        local mark=rule(root,174,180);mark:SetPosition(x,174);mark:SetTint(unpack(gold));marks[key]=mark
        if i>1 then
            button:SetFocusChangeDir(MOVE_LEFT,screen.tabs[order[i-1]])
            screen.tabs[order[i-1]]:SetFocusChangeDir(MOVE_RIGHT,button)
        end
    end
    screen.performance_tab=screen.tabs.performance
    pages.performance=require("nw/performance_panel").attach(screen,label)
    direction:SetFocusChangeDir(MOVE_UP,screen.tabs.personal)
    screen.select_page("guide")
    TheFrontEnd:PushScreen(screen)
    return screen
end
return M
