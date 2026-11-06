local Cards=require("nw/cards")
local M={}

function M.assets()
    local assets={}
    local pages={}
    for _,id in ipairs(Cards.order) do
        local page=math.floor((Cards.codes[id]-1)/128)
        if not pages[page] then
            pages[page]=true
            assets[#assets+1]=Asset("ANIM","anim/nw_ground_cards_"..page..".zip")
        end
    end
    return assets
end

function M.show(inst,code,count)
    -- Resolve the retired spell code exactly as the save/load and inventory paths do.
    local id=Cards.bycode[code] or "spark"
    code=Cards.codes[id]
    local bank="nw_ground_cards_"..math.floor((code-1)/128)
    local pose=count>=7 and "pile_large" or count>=4 and "pile_medium" or count>=2 and "pile_small" or "card"
    local anim=inst.AnimState
    anim:SetBuild(bank)
    anim:SetOrientation(ANIM_ORIENTATION.BillBoard)
    anim:SetBankAndPlayAnimation(bank,pose.."_"..code)
end

return M
