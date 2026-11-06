"""Export the same data used by in-game spell descriptions."""
from pathlib import Path
import re
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parents[1]
vm=LuaRuntime(unpack_returned_tuples=True)
vm.globals().package.path=str(root/'mod/scripts/?.lua').replace('\\','/')+';'+vm.globals().package.path
cards=vm.eval('require("nw/cards")');info=vm.eval('require("nw/spell_info")');defs=vm.eval('require("nw/definitions").spells')
version=re.search(r'^version\s*=\s*"([^"]+)"',(root/'mod/modinfo.lua').read_text(encoding='utf8'),re.MULTILINE).group(1)
retired=vm.eval('require("nw/engraved_spells").retired')
lines=['# 法术说明与当前参数','',f'适用版本：{version}。此表由游戏使用的 definitions、spell_info 和 cards 模块导出；可通过 `tools/export_spell_reference.py` 更新。',
       '', '耗蓝、施法间隔修正和回充时间是分开的字段，参考 [Noita 法术页面](https://noita.wiki.gg/wiki/Spells)与[法术参数表](https://noita.wiki.gg/wiki/Spell_Information_Table)。这里的数值是本 Mod 已有平衡配置，并非声称逐项照搬 Noita 原值。',
       '', '“冷却修正 +0”表示该卡不额外增加施法间隔，不代表整根法杖没有冷却。实际施法还受杖的基础间隔、回充、同一施法块的其他卡和人物动作时间影响。',
       '', '设计卡共 182 张。退役的武器刻印仅供旧档使用。旧载体 trigger_hit、trigger_timer 和固有微弱追踪保留兼容。开启开发者选项后可用 nw_spellkit() 领取全部设计卡。',
       '', '| 法术（ID） | 法力 | 冷却修正（秒） | 回充修正（秒） | 效果 | 实战 |',
       '| --- | ---: | ---: | ---: | --- | --- |']
for id in cards.order.values():
    d=defs[id]
    if retired[id]: continue
    effect=info.effects[id].replace("\n","<br>")
    lines.append(f'| {info.names[id]}（{id}） | {d.mana:g} | {d.delay:+.2f} | {d.recharge:+.2f} | {effect} | {"可用" if info.playable[id] else "未开放"} |')
lines += ['', '当前可用弹体的参数（散射按 6° 法杖计算；碰撞和定时变体沿用基础弹的半角）：', '', '| 弹体 | 速度 | 寿命（秒） | 基础直射距离 | 随机散射半角 |', '| --- | ---: | ---: | ---: | ---: |']
for id in ('spark','arrow','scatter','heavy','fire','frost'):
    d=defs[id]
    lines.append(f'| {info.names[id]} | {d.speed:g} | {d.lifetime:g} | {d.speed*d.lifetime:g} | ±{d.halfangle:g}° |')
rules=vm.eval('require("nw/acquisition")')
rarity=vm.eval('require("nw/card_rarity")')
sources=vm.eval('require("nw/sources")')
creatures=dict(zip(
    "robin moose hound warg killerbee beequeen lightflier lightcrab moonbutterfly mutatedhound spider_warrior spiderqueen alterguardian_phase3 rocky lightninggoat deer klaus slurper crabking firehound dragonfly bishop bishop_nightmare minotaur pigman mutatedbearger worm stalker_atrium daywalker bearger rook_nightmare toadstool toadstool_dark alterguardian_phase4_lunarrift shrouden".split(),
    "红雀 麋鹿鹅 猎犬 座狼 杀人蜂 蜂王 球状光虫 发光蟹 月蛾 恐怖猎犬 蜘蛛战士 蜘蛛女王 天体英雄 石虾 伏特羊 无眼鹿 克劳斯 啜食者 帝王蟹 火焰猎犬 龙蝇 发条主教 损坏的发条主教 远古守护者 猪人 装甲熊獾 洞穴蠕虫 远古织影者 梦魇疯猪 熊獾 损坏的发条战车 毒菌蟾蜍 悲惨的毒菌蟾蜍 天体后裔 暗影憎恶".split(),strict=True))
direct={}
for prefab,entries in sorted(sources.signature.items()):
    for i in range(1,len(entries)+1):
        e=entries[i]
        direct.setdefault(e.id,[]).append(f'{creatures.get(prefab,prefab)}（`{prefab}`）{100*e.rate:g}%')
recipes={}
for row in rules.recipes.values():
    if row.card:
        recipes.setdefault(row.card,[]).append(" + ".join(f'{v[1]} ×{v[2]}' for v in row.ingredients.values()))
lines += ['', '## 生存获取与稀有度', '',
          f'共 {len(rarity.pool)} 张设计卡，其中 {len(recipes)} 张可制作。63 张招式与工具刻印在武器刻印台刻写，其余 81 张在奥术台刻写。下表列出配方和指定生物的固定概率，按默认掉卡倍率计算。', '',
          '另有材料关联掉落。能掉落配方材料的生物按卡的稀有度加权抽取，同一场最多掉一张散卡。武器卡只关联原武器或指定标志性掉落物。音符和目标选择卡跳过材料掉落池。六种基础弹的命中／定时变体还可由基础弹掉落或首领杖产生，独立触发和友方治疗修饰可由首领杖携带。', '',
          '最大生命超过 200 的合资格生物，当本次没有散卡、也没有携卡法杖时，有 0.01% 机会从除道具招牌外的设计卡中等概率抽一张。', '',
          '| 法术 ID | 法术 | 稀有度 | 制作配方（含空白卡） | 指定生物直接掉率 |', '|---|---|---|---|---|']
for id in rarity.pool.values():
    lines.append(f'| `{id}` | {info.names[id]} | {rarity.names[rarity.tiers[id]]} | {" 或 ".join(recipes.get(id,[])) or "—"} | {"、".join(direct.get(id,[])) or "—"} |')
arsenal=vm.eval('require("nw/arsenal")')
lines += ['', '## 武器刻印、目标选择与音符', '',
          '多数近战卡按原版武器的基础物理伤害乘 0.8，火腿棒使用满新鲜度伤害。有位面伤害的武器单独列出基础位面值，晨星和奔雷矛走游戏的电武器结算。随新鲜度、等级、温度或环境变化的武器取标准基础档。', '',
          '| 法术 ID | 法术名 | 原物品 | 物理 / 位面 | 工作动作 | 工作半径 |', '|---|---|---|---:|---|---:|']
for id in ['thrust','slash','whirl']+[c.id for c in arsenal.cards.values() if c.source_weapon and rarity.tiers[c.id]]:
    d=defs[id]
    source=d.source_weapon or {'thrust':'spear','slash':'glasscutter'}.get(id)
    jobs='、'.join(arsenal.worknames[k] for k in d.work.values()) if d.work else ''
    lines.append(f'| `{id}` | {info.names[id]} | `{source}` | {d.damage:g} / {d.planar or 0:g} | {jobs or "—"} | {d.work_radius if jobs else "—"} |')
lines.extend(['','制作沿用空白卡、两件对应武器和一份魔法材料。新增近战卡使用噩梦燃料；道具招牌仅由猪人掉落，默认 0.5%，不参与全卡兜底。武器卡的怪物掉落关联取对应武器本体或标志性材料（如蝙蝠翅膀、伏特羊角）；配方的通用魔法材料仅用于制作。', '',
              '| 音符 ID | 乐器及音高 |','|---|---|'])
for id,n in sorted(arsenal.notes.items(),key=lambda pair:(pair[1].instrument,pair[1].pitch)):
    pitch=int(n.pitch)
    note=('C','C#','D','D#','E','F','F#','G','G#','A','A#','B')[pitch%12]+str(3+pitch//12)
    lines.append(f'| `{id}` | {info.names[id]} · {note} |')
lines += ['', '飞行弹体寿命没有上限，增减寿命倍率同组相乘，最低 0.1 秒。普通弹默认不限制累计路程；世界设置可选择 30／60／120 单位，载荷子弹各自重新计算。环绕仍受施法者位置约束。载荷层数默认不限，开启后可选 1～30 层，根法术不计层数。越界清理默认关闭，开启后：无天然边界墙时超出有效陆地或海洋 5 单位移除，有天然边界墙时到达即移除；不会补发载荷或触发终结效果。移动晶体、载荷卵、星体与原版衍生弹体也参与清理，普通玩家建筑不在清理范围。永久移动实体自动清理同样默认关闭；开启后每秒检查，同一分片移动晶体与载荷卵超过 20 时，清除本轮所有连续 16 分钟处于原版休眠区域的实体。按游戏原有活跃／休眠判定，不使用固定距离；进入活跃区域重置计时，计时与数量独立，总数不超过 20 时仍累计。累计最多 20 分钟，达到后停止增长，重置后重新累计；运行与存档均使用此上限。超过 20 是检查门槛而不是数量上限，静止机关和有寿命的星体不计入；计时随存档保存，服务器关闭期间不累计。载荷分支数量不增加额外限制。不同弹道的基础延寿每种 +8%，合计最多 +24%，这是额外加成，不是最终寿命上限。环绕先将该基础寿命乘 4、至少取 4 秒，再应用增减寿命倍率。星体、静态场与永久机关维持各自存续规则。碰撞和定时载体正常结束时，若此前未释放过载荷，会在结束处补发一次；已释放则不再补发。穿透弹的多次有效碰撞仍可分别释放碰撞载荷。散弹每枚独立拥有碰撞或定时载荷。寿命修正不改变原定时点，但提前结束可提前补发。施法者失效、世界边界保护清理和系统直接移除不补发。抛物线弹体在空中到期时直接消失，不产生落地效果；龙卷风的修正作用于定向飞行阶段，之后的原版游荡阶段保持原时长。普通追踪与短距离追踪施加推进和阻尼，转向敌人只调整方向。移动晶体、载荷卵与星体共用普通弹的弹道和碰撞逻辑，接触结束时停下并保留。永久实体无外力时速度每 4 秒减半，低于 0.1 单位/秒停止；持续追踪可抵消阻力，星体不额外施加此阻力。风压弹向载荷卵叠加自身弹速一半的速度，不触发载荷，不能推动晶体。目标选择不跨载荷分组继承。载荷卵归触发者施法，放置者离线不妨碍他人触发，无有效攻击者时使用临时中立施法源。游戏内卡牌保留伤害、耗蓝、施放与充能等属性栏，效果说明使用简述；资料站同样默认展示属性栏，详细机制说明按按钮展开。', '', '[测试命令与组合](11_法术卡测试指南.md) · [库存图标预览](../assets_src/art_v1/inventory_64_review.png)', '']
(root/'docs/07_法术说明与参数.md').write_text('\n'.join(lines),encoding='utf8')
print('Exported spell reference:', len(cards.order), 'entries')
