local T=require("nw/locale").t
local M={}
function M.reason(plan,err)
    if not plan then return err or "NOT_READY" end
    if plan.projectile_count>0 then return "READY" end
    for _,event in ipairs(plan.trace) do if event.event=="skip_mana" then return "NO_MANA" end end
    return "NO_PROJECTILES"
end
function M.tip(reason)
    local messages={
        NO_MANA=T("暂不可施法：当前法力不足"),
        NO_PROJECTILES=T("暂不可施法：未抽到有效的投射物或法术"),
        PROJECTILE_LIMIT=T("暂不可施法：超过已开启的弹体数量上限"),
        COMPILE_LIMIT=T("暂不可施法：超过载荷层数或编译安全限制"),
        DUPLICATE_CARD=T("暂不可施法：卡牌内部编号重复"),
        INVALID_DECK=T("暂不可施法：抽牌状态异常"),
        BROKEN=T("法杖破损：用 5 份奥术粉尘修复"),
    }
    return messages[reason] or T("暂不可施法：法杖尚未就绪")
end
return M
