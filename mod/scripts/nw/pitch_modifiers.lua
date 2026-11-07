local T=require("nw/locale").t
local M={cards={},by_id={}}
for _,row in ipairs({
    {"pitch_octave_up","升八度",12},
    {"pitch_octave_down","降八度",-12},
    {"pitch_semitone_up","升半音",1},
    {"pitch_semitone_down","降半音",-1},
}) do
    local card={id=row[1],name=T(row[2]),kind="modifier",mana=1,delay=0,tier=1,pitch_shift=row[3],
        effect=string.format(T("同组乐器音高偏移 %+d 半音，多张先相加抵消，再限制在上下各 12 半音；载荷独立计算。两种乐器基础音均为 C4–B4，可调音域 C3–B5，含全部半音。只改变声音，不改变弹速、寿命和音符玩法身份。"),row[3])}
    M.cards[#M.cards+1]=card;M.by_id[card.id]=card
end
return M
