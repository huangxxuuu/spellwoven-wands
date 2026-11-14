local Work=require("nw/constants/melee").work
local Garden=require("nw/constants/prefabs").garden
local P=require("nw/spell_parameter_text")
local C=require("nw/constants/melee").engraving
local Audio=require("nw/constants/audio")
local Instruments,Timing=Audio.instruments,Audio.timing
local Selector=require("nw/constants/modifiers").selector
local Bounds=require("nw/constants/limits")
local T=require("nw/locale").t
local Samples=require("nw/instrument_samples")
local M={cards={},notes={},weapons={},extra_notes={},legacy_notes={ocarina_gsharp=true,ocarina_a2=true}}
local function add(card)
    M.cards[#M.cards+1]=card
    return card
end
local worknames={NET=T("捕捉"),CHOP=T("砍树"),DIG=T("铲掘"),MINE=T("采矿"),HAMMER=T("锤击"),SCYTHE=T("收割"),TILL=T("耕地"),TERRAFORM=T("起草皮")}
M.worknames=worknames
local planar=C.planar
local pillows=C.pillows

local function weapon_tier(source,damage)
    if planar[source] or source=="nightstick" or source:find("^spear_wathgrithr_lightning") or source=="multitool_axe_pickaxe" or damage>=C.rare_damage then return 3 end
    if damage>=C.uncommon_damage or source=="lucy" or source=="merm_tool" or source=="merm_tool_upgraded" then return 2 end
    return 1
end

for _,row in ipairs(require("nw/weapon_catalog")) do
    local source,name,damage,pose,actions=unpack(row)
    local thrust=pose=="thrust"
    local info={}
    for _,action in ipairs(actions) do info[#info+1]=worknames[action] end
    local radius=thrust and C.thrust_reach or C.slash_reach
    local card=add({id="edge_"..source,name=name,kind="melee",mana=math.max(C.min_mana,math.ceil(damage*C.mana_factor)),
        delay=thrust and C.thrust_delay or C.slash_delay,tier=weapon_tier(source,damage),damage=damage*C.damage_factor,native_base_damage=damage,source_weapon=source,pose=pose,
        reach=thrust and C.thrust_reach or C.slash_reach,width=thrust and C.thrust_width or nil,arc=not thrust and C.slash_arc or nil,
        duration=C.duration,windup=C.windup,work=actions,work_radius=radius,
        effect=T("从释放点")..(thrust and T("向前突刺") or T("挥出扇形攻击"))..T("。")
            ..(#info>0 and (table.concat(info,T("、"))..T("半径 ")..radius..P.format("，效率为原工具的 {efficiency}%。",{efficiency=Work.credit*100})) or "")})
    card.planar=planar[source] and C.damage_factor*planar[source]
    card.electric=source=="nightstick" and "always" or source:find("^spear_wathgrithr_lightning") and "wet" or nil
    card.pillow=pillows[source]
    if card.planar then card.effect=card.effect..T(" 位面伤害 ")..card.planar..T("。") end
    if card.electric then card.effect=card.effect..(card.electric=="wet" and T(" 对潮湿目标使用原版电击结算。") or T(" 使用原版电武器结算。")) end
    if card.pillow then card.effect=card.effect..T(" 原版枕头基础伤害为零，命中产生击退。") end
    if source=="torch" or source=="lighter" then card.effect=card.effect..T(" 命中按原版武器概率点燃目标。") end
    if source=="nightstick" then card.effect=card.effect..T(" 出手时照亮周围。") end
    card.source_image=row[6]
    require("nw/engraved_spells").configure(card,source)
    M.weapons[card.id]=card
end
local selections={
    {"hostile",T("敌对生物")},{"neutral",T("中立生物")},{"friendly",T("友好生物")},{"building",T("建筑")},
    {"nature",T("自然物")},{"players_other",T("其他玩家")},{"self",T("自身")}}
for _,v in ipairs(selections) do
    add({id="target_"..v[1],name=T("选取")..v[2],kind="modifier",mana=Selector.mana,delay=Selector.delay,tier=Selector.tier,select_target=v[1],
        effect=T("同一施法组的命中及辅助效果选取")..v[2]..T("。各效果仍需满足自身适用条件，明确豁免的效果除外。多张选择卡取并集，明确选择其他玩家后可命中他们。")})
end
for _,inst in ipairs({"ocarina","kantele"}) do
    local notes=Instruments[inst].notes
    for _,pair in ipairs(notes) do
        local name,pitch=unpack(pair)
        local prefix=inst=="ocarina" and T("陶笛") or T("弦琴")
        local id=({ocarinaA="note_a",ocarinaC="note_c",kanteleD="chord_d"})[inst..name]
        local new=not id
        id=id or (inst.."_"..name:lower():gsub("#","sharp"))
        local label=({ocarina_a2="A",kantele_dsharp="C"})[id] or name
        M.notes[id]={instrument=inst,pitch=pitch,label=label}
        if new then
            local harp=inst=="kantele"
            add({id=id,name=prefix.." "..label,kind=harp and "note" or "projectile",tier=Instruments[inst].tier,mana=Instruments[inst].mana,
                delay=Instruments.delay,damage=not harp and 0 or nil,speed=not harp and Instruments.ocarina.speed or nil,lifetime=not harp and Instruments.ocarina.lifetime or nil,
                halfangle=not harp and Instruments.ocarina.halfangle or nil,radius=harp and Instruments.kantele.radius or nil,
                effect=harp and P.format("奏响此音，周围玩家回复 {sanity} 理智；所有弦琴音共享每人 {interval} 秒间隔。",{sanity=Garden.chord.sanity,interval=Garden.chord.cooldown})
                    or P.format("奏响此音，短程声波命中后留下 {duration} 秒标记，可用陶笛 C 引发回声。",{duration=Timing.mark_duration})})
        end
    end
end
local engraving=require("nw/engraved_spells")
for _,row in ipairs(engraving.extra) do
    local c=add({id="edge_"..row[1],name=row[2],source_weapon=row[3] or row[1],mana=C.extra.mana,delay=C.extra.delay,tier=C.extra.tier})
    engraving.configure(c,row[1])
    M.weapons[c.id]=c
end
M.notes.ocarina_g={instrument="ocarina",pitch=Instruments.ocarina_g_pitch,label="G"}
for _,row in ipairs(Instruments.extra_notes) do
    local id,label,pitch=unpack(row)
    M.notes[id]={instrument="kantele",pitch=pitch,label=label}
    M.extra_notes[#M.extra_notes+1]={id=id,name=T("弦琴").." "..label,kind="note",tier=Instruments.kantele.tier,mana=Instruments.kantele.mana,delay=Instruments.delay,radius=Instruments.kantele.radius,
        effect=P.format("奏响此音，周围玩家回复 {sanity} 理智；所有弦琴音共享每人 {interval} 秒间隔。",{sanity=Garden.chord.sanity,interval=Garden.chord.cooldown})}
end
function M.resolve_tone(id,shift,beats)
    local note=M.notes[id]
    if note then
        local pitch=note.pitch+math.max(-Bounds.max_pitch,math.min(Bounds.max_pitch,shift or 0))
        local bank=Samples[note.instrument]
        local beat=beats==Timing.half_beat and "half" or beats==Timing.double_beat and "two" or "one"
        local sample=bank.variants[beat][pitch]
        return {instrument=note.instrument,pitch=pitch,base_pitch=note.pitch,
            octave=Instruments.base_octave+math.floor(pitch/Instruments.semitones_per_octave),semitone=pitch%Instruments.semitones_per_octave,supported=sample~=nil,
            event=sample and sample.event,duration=sample and sample.duration,beats=beats==Timing.half_beat and Timing.half_beat or beats==Timing.double_beat and Timing.double_beat or Timing.normal_beat,
            range=bank.range,min_pitch=bank.min,max_pitch=bank.max}
    end
end
function M.tone(id,shift,beats)
    local tone=M.resolve_tone(id,shift,beats)
    if not tone then return nil,"unknown_note" end
    if not tone.supported then return nil,"unsupported_pitch" end
    return tone.event,{},tone.duration
end
function M.tone_description(id)
    local tone=M.resolve_tone(id,0)
    if not tone then return "" end
    local names={"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
    local base=names[tone.semitone+1]..tone.octave
    return string.format(T("基础音 %s；可调音域 %s（含全部半音），音高最多升降一个八度。默认一拍，加速半拍、减速两拍；多张先抵消，再限制为三档。"),base,tone.range)
end
return M
