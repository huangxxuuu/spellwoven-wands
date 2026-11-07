local T=require("nw/locale").t
local Samples=require("nw/instrument_samples")
local M={cards={},notes={},weapons={}}
local function add(card)
    M.cards[#M.cards+1]=card
    return card
end
local worknames={NET=T("捕捉"),CHOP=T("砍树"),DIG=T("铲掘"),MINE=T("采矿"),HAMMER=T("锤击"),SCYTHE=T("收割"),TILL=T("耕地"),TERRAFORM=T("起草皮")}
M.worknames=worknames
local planar={pickaxe_lunarplant=10,shovel_lunarplant=10,sword_lunarplant=30,voidcloth_scythe=18,
    shadow_battleaxe=10,spear_wathgrithr_lightning_charged=20}
local pillows={handpillow_petals=1,handpillow_kelp=1.4,handpillow_beefalowool=1.8,handpillow_steelwool=2.2}

local function weapon_tier(source,damage)
    if planar[source] or source=="nightstick" or source:find("^spear_wathgrithr_lightning") or source=="multitool_axe_pickaxe" or damage>=80 then return 3 end
    if damage>=34 or source=="lucy" or source=="merm_tool" or source=="merm_tool_upgraded" then return 2 end
    return 1
end

for _,row in ipairs(require("nw/weapon_catalog")) do
    local source,name,damage,pose,actions=unpack(row)
    local thrust=pose=="thrust"
    local info={}
    for _,action in ipairs(actions) do info[#info+1]=worknames[action] end
    local radius=thrust and 2.4 or 2
    local card=add({id="edge_"..source,name=name,kind="melee",mana=math.max(4,math.ceil(damage*.32)),
        delay=thrust and .04 or .10,tier=weapon_tier(source,damage),damage=damage*.8,native_base_damage=damage,source_weapon=source,pose=pose,
        reach=thrust and 2.4 or 2,width=thrust and 1 or nil,arc=not thrust and 110 or nil,
        duration=.30,windup=.13,work=actions,work_radius=radius,
        effect=T("从释放点")..(thrust and T("向前突刺") or T("挥出扇形攻击"))..T("。")
            ..(#info>0 and (table.concat(info,T("、"))..T("半径 ")..radius..T("，效率为原工具的 75%。")) or "")})
    card.planar=planar[source] and .8*planar[source]
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
    add({id="target_"..v[1],name=T("选取")..v[2],kind="modifier",mana=2,delay=0,tier=1,select_target=v[1],
        effect=T("同一施法组可命中")..v[2]..T("。多张选择卡取并集，明确选择其他玩家后可命中他们。")})
end
-- Absolute semitones above C3; kantele uses the supplied lyre samples.
for _,inst in ipairs({"ocarina","kantele"}) do
    local notes=inst=="ocarina" and {{"A",21},{"B",23},{"C",24},{"D",26},{"E",28},{"F",29},{"G#",32},{"A2",33}}
        or {{"A",9},{"D",14},{"D#",12},{"E",16},{"G",19}}
    for _,pair in ipairs(notes) do
        local name,pitch=unpack(pair)
        local prefix=inst=="ocarina" and T("陶笛") or T("弦琴")
        local id=({ocarinaA="note_a",ocarinaC="note_c",kanteleD="chord_d"})[inst..name]
        local new=not id
        id=id or (inst.."_"..name:lower():gsub("#","sharp"))
        -- Keep legacy IDs; the former D# card is now the selected C4 base note.
        local label=({ocarina_a2="A5",kantele_dsharp="C"})[id] or name
        M.notes[id]={instrument=inst,pitch=pitch,label=label}
        if new then
            local harp=inst=="kantele"
            add({id=id,name=prefix.." "..label,kind=harp and "note" or "projectile",tier=harp and 2 or 1,mana=harp and 10 or 6,
                delay=.03,damage=not harp and 0 or nil,speed=not harp and 14 or nil,lifetime=not harp and .45 or nil,
                halfangle=not harp and 1 or nil,radius=harp and 3 or nil,
                effect=harp and T("奏响此音，周围玩家回复 1 理智；所有弦琴音共享每人 3 秒间隔。")
                    or T("奏响此音，短程声波命中后留下 2 秒标记，可用陶笛 C 引发回声。")})
        end
    end
end
local engraving=require("nw/engraved_spells")
for _,row in ipairs(engraving.extra) do
    local c=add({id="edge_"..row[1],name=row[2],source_weapon=row[3] or row[1],mana=18,delay=.12,tier=3})
    engraving.configure(c,row[1])
    M.weapons[c.id]=c
end
M.notes.ocarina_g={instrument="ocarina",pitch=31,label="G"}
function M.resolve_tone(id,shift)
    local note=M.notes[id]
    if note then
        local pitch=note.pitch+(shift or 0)
        local bank=Samples[note.instrument]
        local sample=bank.samples[pitch]
        return {instrument=note.instrument,pitch=pitch,base_pitch=note.pitch,
            octave=3+math.floor(pitch/12),semitone=pitch%12,supported=sample~=nil,
            event=sample and sample.event,duration=sample and sample.duration,
            range=bank.range,min_pitch=bank.min,max_pitch=bank.max}
    end
end
function M.tone(id,shift)
    local tone=M.resolve_tone(id,shift)
    -- Select an exact recorded note. Never substitute a boundary note or alter playback speed.
    if not tone then return nil,"unknown_note" end
    if not tone.supported then return nil,"unsupported_pitch" end
    return tone.event,{},tone.duration
end
function M.tone_description(id)
    local tone=M.resolve_tone(id,0)
    if not tone then return "" end
    local names={"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
    local base=names[tone.semitone+1]..tone.octave
    return string.format(T("基础音 %s；可调音域 %s（含全部半音）。超出音域时静音，法术效果照常。"),base,tone.range)
end
return M
