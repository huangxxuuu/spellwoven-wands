"""Document the live generation tables and audit their seeded distributions."""
import json
from collections import Counter
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
vm = LuaRuntime(unpack_returned_tuples=True)
vm.globals().package.path = (ROOT / 'mod/scripts/?.lua').as_posix() + ';' + vm.globals().package.path
rules = vm.eval('require("nw/wand_generation")')
generator = vm.eval('require("nw/generator")')
definition = vm.eval('require("nw/definitions")')
rng = vm.eval('require("nw/rng").new(194783)')
keys = list(rules['keys'].values())
kinds = list(definition.archetypes.values())
names = dict(zip(keys, ['容量', '法力上限', '回蓝 / 秒', '施放间隔 / 秒', '充能 / 秒', '散射 / 度']))
kindnames = dict(zip(kinds, ['萌芽', '速射', '蓄能', '复苏', '编织', '混沌']))
tiers = ['普通', '精良', '稀有', '史诗']
report = {}
for tier, title in enumerate(tiers, 1):
    values = {key: [] for key in keys}
    outliers = 0
    for index in range(12000):
        kind = kinds[index % len(kinds)]
        data = generator.generate(rng.int(rng, 1073741823), tier, kind)
        extreme = False
        for key in keys:
            value = data.stats[key]
            values[key].append(value)
            lo, hi, centre, sigma, step = rules.distribution(tier, kind, key)
            extreme |= abs(value - centre) > 2 * sigma
        outliers += extreme
    report[title] = {'samples': 12000, 'means': {key: round(sum(v) / len(v), 3) for key, v in values.items()},
        'capacity_counts': dict(sorted(Counter(values['capacity']).items())),
        'any_two_sigma_outlier_pct': round(outliers / 120, 2)}
(ROOT / 'test_reports/wand_generation_v3.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')

lines = ['## 确定性的属性生成 v3（0.25.1）', '',
    '不再使用属性点或总预算。先确定稀有度与类型，再分别按离散截断正态权重抽取属性。候选值权重为 `exp(-0.5*((x-中心)/标准差)^2)`，只对合法候选归一化，不把越界值压到端点。随机流使用 Park–Miller；同种子、阶级、类型和生成版本可复现。', '',
    '全局兼容边界包含旧存档和固定入门杖；新随机杖使用下面更窄的分阶范围。旧杖不重抽，继续保存原有数值、卡牌、名字和外观。', '',
    '| 属性 | 全局下限 | 全局上限 | 新生成精度 |', '|---|---:|---:|---:|']
for key in keys + ['draw_count']:
    row = rules.bounds[key]
    lines.append(f'| {names.get(key, "基础同发")} | {row[1]:g} | {row[2]:g} | {row[3]:g} |')
lines += ['', 'SAN 转化率固定 20；乱序为布尔值。随机生成的基础施放间隔仍不低于 0.20 秒，这是生成分布限制；卡牌修正后的施放间隔和充能时间均可降到零，实际速度仍受原版攻击动作、角色战斗冷却和法术专属冷却约束。', '',
    '每格格式为 **下限～上限；中心 / 标准差**。中心是类型修正前的分布峰值，不是截断后样本的精确均值。', '',
    '| 属性 | 普通 | 精良 | 稀有 | 史诗 |', '|---|---|---|---|---|']
for key in keys:
    cells = []
    for tier in range(1, 5):
        r = rules.tiers[tier][key]
        cells.append(f'{r[1]:g}～{r[2]:g}；{r[3]:g} / {r[4]:g}')
    lines.append('| ' + names[key] + ' | ' + ' | '.join(cells) + ' |')
lines += ['', '类型仅移动中心，不突破该阶上下限。下面偏移以该阶原始标准差为单位；施放、充能、散射的负偏移表示改善。萌芽保持中心，标准差缩为 0.75 倍；其他类型保持标准差。', '',
    '| 类型 | 中心偏移 | 同发 1～6 的抽取权重 | 乱序 |', '|---|---|---|---|']
for kind in kinds:
    r = rules.types[kind]
    shifts = '、'.join(f'{names[key]} {r.offset[key]:+g}σ' for key in keys if r.offset[key] is not None) or '无；分布更集中'
    shuffle = '固定乱序' if r.shuffle is True else '固定非乱序' if r.shuffle is False else '随阶级'
    lines.append(f'| {kindnames[kind]} | {shifts} | {" / ".join(f"{x:g}" for x in r.draw.values())} | {shuffle} |')
lines += ['', '同发抽取先排除超过容量的候选，再归一化其余权重；单发作为独立风格保留，不视为低阶惩罚。速射各阶的回蓝下限足以覆盖最快基础间隔下一发火花的消耗，复杂卡组仍由玩家搭配。', '',
    '随阶级的乱序概率为普通 50%、精良 35%、稀有 20%、史诗 10%。普通与精良没有固有法术；稀有 10%、史诗 25% 获得加速或精准，等概率选择，不扣除其他属性。无主题来源时六种类型等概率；Boss 来源仍可偏向特定类型。', '',
    '入门杖固定两格、非乱序、同发 1、法力 120、回蓝 18、施放 0.65 秒、充能 1.4 秒、散射 6°，内置火花弹。制作随机杖为空槽，Boss 掉落继续使用原来源卡组规则。外观根据最终容量、乱序、同发等属性生成。', '',
    '本表由 `tools/export_wand_generation.py` 从实际配置生成。每阶 12,000 个等比例类型样本；“极端”统计定义为六项中任一项偏离自身类型中心超过两倍标准差，类型预设弱项不另视为极端。', '',
    '| 稀有度 | 平均容量 | 平均法力 | 平均回蓝 | 平均施放 | 平均充能 | 整杖极端比例 |', '|---|---:|---:|---:|---:|---:|---:|']
for title in tiers:
    r = report[title];m = r['means']
    lines.append(f'| {title} | {m["capacity"]:g} | {m["mana_max"]:g} | {m["mana_regen"]:g} | {m["cast_delay"]:g} | {m["recharge"]:g} | {r["any_two_sigma_outlier_pct"]:g}% |')
path = ROOT / 'docs/04_开发执行规格.md'
text = path.read_text(encoding='utf8')
start = text.index('## 确定性的属性生成')
end = text.index('## 首版法术参数表', start)
path.write_text(text[:start] + '\n'.join(lines) + '\n\n' + text[end:], encoding='utf8')
print(json.dumps({title: {'means': r['means'], 'outlier_pct': r['any_two_sigma_outlier_pct']} for title, r in report.items()}, ensure_ascii=False, indent=2))
