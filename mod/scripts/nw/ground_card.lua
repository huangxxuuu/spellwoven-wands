local Cards=require("nw/cards")
local Visual=require("nw/card_visuals")
local M={}

function M.assets()
    local assets={Asset("ANIM","anim/nw_card_piles.zip")}
    local pages={}
    for _,id in ipairs(Cards.order) do
        local page=math.floor((Cards.codes[id]-1)/Visual.page_size)
        if not pages[page] then
            pages[page]=true
            assets[#assets+1]=Asset("ANIM","anim/nw_card_faces_"..page..".zip")
        end
    end
    return assets
end

-- Base-3 digits preserve the second/third real shapes; higher bits describe
-- hexagons strictly below the first three cards. Container slot order is unchanged.
function M.surface(box)
    local top,layout,seen,hexes=nil,0,0,0
    for slot=1,box:GetNumSlots() do
        local card=box:GetItemInSlot(slot)
        if card then
            seen=seen+1
            if seen==1 then top=Cards.codes[card.spell_id]
            elseif seen<=3 then
                local row=Visual.cards[card.spell_id]
                local digit=row and (row.shape=="H" and 1 or row.shape=="N" and 2) or 0
                layout=layout+digit*(seen==2 and 1 or 3)
            elseif Visual.cards[card.spell_id] and Visual.cards[card.spell_id].shape=="H" then
                hexes=hexes+1
            end
        end
    end
    return top,layout+math.min(hexes,2)*9
end

function M.sequence(count,layout)
    layout=layout or 0
    local shapes={"R","H","N"}
    local first=shapes[layout%3+1]
    return count==2 and first or first..shapes[math.floor(layout/3)%3+1]
end

function M.pose(code,count,layout,separated)
    -- Resolve the retired spell code exactly as the save/load and inventory paths do.
    local id=Cards.bycode[code] or "spark"
    local shape=Visual.cards[id].shape
    if count<=1 then return "single_"..shape,id end
    local prefix=shape..M.sequence(count,layout)
    if count==2 then return "two_"..prefix,id end
    if count==3 then return "three_"..prefix,id end
    local hexes=math.floor((layout or 0)/9)
    if count<=8 then return "medium_"..prefix..(hexes>0 and "_hex" or "_plain"),id end
    local style=hexes==0 and "plain" or hexes==1 and "one_hex" or separated and "hex_separated" or "hex_adjacent"
    return "large_"..prefix.."_"..style,id
end

function M.show(inst,code,count,layout,separated)
    local pose,id=M.pose(code,count,layout,separated)
    -- Temporary native-art alias until the new card face is approved/compiled.
    id=Visual.cards[id].art_id or id
    local bank="nw_card_faces_"..math.floor((Cards.codes[id]-1)/Visual.page_size)
    local anim=inst.AnimState
    anim:SetBuild("nw_card_piles")
    anim:SetOrientation(ANIM_ORIENTATION.BillBoard)
    -- The texture already includes perspective; only its draw layer is grounded.
    anim:SetLayer(LAYER_BACKGROUND)
    anim:SetSortOrder(3)
    anim:OverrideSymbol("face",bank,"face_"..id)
    anim:SetBankAndPlayAnimation("nw_card_piles",pose)
end

return M
