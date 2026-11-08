local M={}
function M.open()
    local T=require("nw/locale").t
    local Popup=require("screens/popupdialog")
    local Image=require("widgets/image")
    local Spinner=require("widgets/spinner")
    local Text=require("widgets/text")
    local Direction=require("nw/cast_direction")
    local screen=Popup(T("织法之杖 · 向导"),"",{
        {text=T("资料站"),cb=function() VisitURL("https://huangxxuuu.github.io/spellwoven-wands/"..(require("nw/locale").language=="en" and "en/" or ""),false) end},
        {text=T("关闭"),cb=function() TheFrontEnd:PopScreen() end},
    },nil,nil,"dark")
    local root=screen.proot
    local gold={.91,.75,.39,1}
    local cream={.92,.89,.80,1}
    local muted={.72,.72,.67,1}
    screen.title:SetPosition(0,198);screen.title:SetSize(30);screen.title:SetColour(unpack(gold))
    screen.bg:Kill()
    screen.bg=root:AddChild(require("widgets/nw_wandframe")())
    screen.bg:SetSize(720,490);screen.bg:SetClickable(false);screen.bg:MoveToBack()
    screen.menu:SetPosition(-100,-194)
    local function label(parent,size,value,x,y,width,height,colour)
        local text=parent:AddChild(Text(UIFONT,size,value))
        text:SetPosition(x,y);text:SetColour(unpack(colour or cream));text:SetClickable(false)
        if width then text:EnableWordWrap(true);text:SetRegionSize(width,height) end
        return text
    end
    local rows={
        {"nw_workbench","images/nw_guide.xml",T("奥术台"),T("制杖、刻卡、装配法术\n炼金引擎旁制作")},
        {"nw_engraver","images/nw_guide.xml",T("武器刻印台"),T("把武器和工具刻成法术卡\n炼金引擎旁制作")},
        {"nw_disassembler","images/nw_guide.xml",T("奥术分解炉"),T("回收地面卡牌与法杖\n炼金引擎旁制作")},
    }
    for i,row in ipairs(rows) do
        local x=(i-2)*216
        local pic=root:AddChild(Image(row[2],row[1]..".tex"));pic:SetSize(68,68);pic:SetPosition(x,137);pic:SetClickable(false)
        label(root,20,row[3],x,77,208,48)
        label(root,17,row[4],x,16,208,60,muted)
    end
    label(root,18,T("制作栏 → 魔法：搜索建筑名称\n靠近奥术台：Shift + 左键装卡 / 取卡；修饰卡放在弹体前"),0,-45,660,48,muted)
    local divider=root:AddChild(Image("images/global.xml","square.tex"))
    divider:SetSize(660,1);divider:SetPosition(0,-82);divider:SetTint(.55,.44,.25,.65);divider:SetClickable(false)
    local heading=label(root,23,T("施法方向"),-160,-124,210,32,gold)
    heading:SetClickable(true)
    local direction=root:AddChild(Spinner({
        {text=T("目标选择"),data="target"},
        {text=T("鼠标方向"),data="mouse"},
    },260,38,{font=UIFONT,size=22},false,nil,nil,true))
    direction:SetPosition(100,-124);direction:SetTextColour(unpack(cream));direction:SetWrapEnabled(true)
    screen.direction=direction
    local descriptions={
        target=T("选中物体时，朝它脚下施法。\n指着 Boss 头部，也会瞄准脚下。\n无目标时，朝鼠标地面点施法。"),
        mouse=T("始终朝鼠标对应的地面点施法。\n不受树冠等物体的选中影响；\n指着物体上半身时，可能打偏。"),
    }
    local function refresh()
        if not screen.inst:IsValid() then return end
        local mode=Direction.get()
        -- SetSelectedIndex doesn't invoke the change callback when restoring.
        direction:SetSelectedIndex(mode=="mouse" and 2 or 1)
        local tip=descriptions[mode].."\n\n"..T("自动保存，停止切换 1 秒后应用。\n不影响世界设置或其他玩家。")
        for _,widget in ipairs({heading,direction,direction.leftimage,direction.rightimage}) do
            local x=widget==heading and -160 or 100
            if widget==direction.leftimage or widget==direction.rightimage then x=x+widget:GetPosition().x end
            widget:SetHoverText(tip,{font=UIFONT,font_size=18,offset_x=-x,offset_y=114,
                region_w=410,region_h=144,wordwrap=true})
        end
    end
    direction:SetOnChangedFn(function(value) Direction.set(value);refresh() end)
    direction:SetFocusChangeDir(MOVE_DOWN,screen.menu)
    screen.menu:SetFocusChangeDir(MOVE_UP,direction)
    refresh();Direction.load(refresh)
    TheFrontEnd:PushScreen(screen)
    return screen
end
return M
