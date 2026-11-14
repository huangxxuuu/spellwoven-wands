local Bounds=require("nw/constants/limits")
local P=require("nw/spell_parameter_text")
local C=require("nw/constants/audio")
local T=require("nw/locale").t
local M={cards={},by_id={}}
for _,row in ipairs(C.pitch_cards) do
    local card={id=row[1],name=T(row[2]),kind="modifier",mana=C.pitch_cost.mana,delay=C.pitch_cost.delay,tier=C.pitch_cost.tier,pitch_shift=row[3],
        effect=P.format("同组乐器音高偏移 {shift} 半音，多张先相加抵消，再限制在上下各 {limit} 半音；载荷独立计算。两种乐器基础音均为 C4–B4，可调音域 C3–B5，含全部半音。只改变声音，不改变弹速、寿命和音符玩法身份。",{shift=string.format("%+d",row[3]),limit=Bounds.max_pitch})}
    M.cards[#M.cards+1]=card;M.by_id[card.id]=card
end
return M
