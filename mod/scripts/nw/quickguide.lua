local M={}
function M.open()
    local T=require("nw/locale").t
    local Popup=require("screens/popupdialog")
    local Image=require("widgets/image")
    local Text=require("widgets/text")
    local screen=Popup(T("织法之杖 · 向导"),"",{
        {text=T("资料站"),cb=function() VisitURL("https://huangxxuuu.github.io/spellwoven-wands/"..(require("nw/locale").language=="en" and "en/" or ""),false) end},
        {text=T("关闭"),cb=function() TheFrontEnd:PopScreen() end},
    },nil,nil,"dark")
    local root=screen.proot
    screen.title:SetPosition(0,145);screen.title:SetSize(32)
    screen.bg:SetScale(.90,.92)
    screen.menu:SetPosition(-100,-145)
    local rows={
        {"nw_workbench","images/nw_guide.xml",T("奥术台"),T("制杖、刻卡、装配法术\n炼金引擎旁制作")},
        {"nw_engraver","images/nw_guide.xml",T("武器刻印台"),T("把武器和工具刻成法术卡\n炼金引擎旁制作")},
        {"nw_disassembler","images/nw_guide.xml",T("奥术分解炉"),T("回收地面卡牌与法杖\n炼金引擎旁制作")},
    }
    for i,row in ipairs(rows) do
        local x=(i-2)*185
        local pic=root:AddChild(Image(row[2],row[1]..".tex"));pic:SetSize(76,76);pic:SetPosition(x,65)
        local name=root:AddChild(Text(UIFONT,22,row[3]));name:SetPosition(x,12)
        local desc=root:AddChild(Text(UIFONT,18,row[4]));desc:SetPosition(x,-37);desc:EnableWordWrap(true);desc:SetRegionSize(175,70)
    end
    local tip=root:AddChild(Text(UIFONT,19,T("制作栏 → 魔法：搜索建筑名称\n靠近奥术台：Shift + 左键装卡 / 取卡；修饰卡放在弹体前")))
    tip:SetPosition(0,-90)
    TheFrontEnd:PushScreen(screen)
end
return M
