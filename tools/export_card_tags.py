"""Export the complete reviewed tag assignment, including legacy spell IDs."""
import json
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
vm = LuaRuntime(unpack_returned_tuples=True)
vm.globals().package.path = (ROOT / 'mod/scripts/?.lua').as_posix() + ';' + vm.globals().package.path
rows = vm.execute('''
local Tags=require("nw/card_tags")
local Info=require("nw/spell_info")
local Cards=require("nw/cards")
local Visual=require("nw/card_visuals").cards
local Retired=require("nw/engraved_spells").retired
local legacy={trigger_hit=true,trigger_timer=true,weak_homing=true}
local stations={}
for _,entry in ipairs(require("nw/acquisition").menu_entries) do
    if entry.card then
        stations[entry.card]=stations[entry.card] or {}
        table.insert(stations[entry.card],entry.station)
    end
end
local rows={}
for id,d in pairs(require("nw/definitions").spells) do
    local tags={}
    for _,option in ipairs(Tags.options(Tags.for_card(id))) do
        tags[#tags+1]={id=option.id,label=option.text}
    end
    rows[#rows+1]={id=id,name=Info.names[id],effect=Info.effects[id],
        class=Visual[id] and Visual[id].primary_class,kind=d.kind,tags=tags,code=Cards.codes[id],
        public=not Retired[id] and not legacy[id],stations=stations[id] or {}}
end
table.sort(rows,function(a,b) return (a.code or 100000)<(b.code or 100000) end)
return rows
''')
result=[]
for row in rows.values():
    record=dict(row)
    record['tags']=[dict(tag) for tag in row['tags'].values()]
    record['stations']=list(row['stations'].values())
    result.append(record)
meanings={
    'melee':'近战攻击，或专门强化近战伤害。',
    'area':'区域、横扫、沿途连续采收等范围效果，或改变作用范围；纯索敌半径不算。',
    'element':'火焰、寒冷与温度、电击、湿润或对潮湿目标的专门作用。',
    'planar':'实际造成位面伤害；不按外观或原武器名称推断。',
    'explosive':'爆炸、范围爆裂，或引爆已有晶体。',
    'control':'减速、冻结、击退、拉拽、嘲讽或打断敌方目标。',
    'movement':'移动施法者；移动敌人归控场。',
    'recovery':'回复生命或理智；单纯不消耗理智不算。',
    'defense':'主动阻挡投射物或承受的伤害。',
    'tool':'实际执行采集、砍挖、耕地、浇水、捕鱼等工作，也包括能破坏可工作目标的爆炸。',
    'music':'演奏音符或调整乐器音高。',
    'light':'提供实际照明；发光贴图、火焰粒子不算。',
    'damage':'仅限修饰类卡牌的增减伤害、暴击及条件增伤；基础法术自身伤害成长和施法控制类的伤害折扣不算。',
    'speed':'专门调整弹速或提供渐变加速；自带基础速度不算。',
    'lifetime':'直接调整存续时间，包括环绕的主要延寿效果；普通持续时间不算。',
    'target':'改变允许命中的对象集合。',
    'mana':'专门调整法力消耗；普通耗蓝不算。',
    'recharge':'专门调整充能等待；普通施法的成本修正不算。',
    'trajectory':'改变路径、散射、方向分布、侧向分裂，或具有抛物线、返航、环绕等特殊路径。',
    'homing':'飞行过程中持续向目标转向或推进；自动选取单个目标不算。',
    'pierce':'穿过目标后继续命中，或赋予这种能力。',
    'multicast':'额外抽取法术并组织同组施放；一个基础法术自带多枚弹体不算。',
    'copy':'复制施法输出；额外发射普通侧弹不算。',
    'trigger':'通过碰撞、定时、击破等条件释放后续法术，或赋予这种能力；普通命中特效不算。',
}
options=vm.execute('local T=require("nw/card_tags");local p={};for _,id in ipairs(T.order) do p[id]=true end;return T.options(p)')
summary=[]
assert set(meanings)=={option['id'] for option in options.values()}
for option in options.values():
    tag_id=option['id']
    members=[r for r in result if any(t['id']==tag_id for t in r['tags'])]
    summary.append(dict(id=tag_id,label=option['text'],meaning=meanings[tag_id],
        total=len(members),public=sum(r['public'] for r in members),craftable=sum(bool(r['stations']) for r in members)))
untagged=[r['id'] for r in result if not r['tags']]
output=ROOT/'test_reports/card_tags_audit.json'
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps({'spell_count':len(result),'tag_count':len(summary),'tags':summary,
    'untagged':untagged,'spells':result},ensure_ascii=False,indent=2),encoding='utf8')
lines=['法术标签核查',f'全部定义：{len(result)}；当前设计卡：{sum(r["public"] for r in result)}；可制作法术：{sum(bool(r["stations"]) for r in result)}。',
    f'标签共 {len(summary)} 个。计数按法术 ID 去重；碰撞/定时变体分别计数。',
    '标签用于细分主类，不要求每个普通法术强行拥有标签。以下计数不包含材料和法杖制作项。','',
    '标签语义与数量（当前设计卡 / 可制作法术 / 含旧档兼容定义）：']
for tag in summary:
    lines.append(f'{tag["label"]}：{tag["public"]} / {tag["craftable"]} / {tag["total"]}。{tag["meaning"]}')
lines+=['','未额外贴标签的法术（仍可在主类找到）：']
for r in result:
    if not r['tags']:
        reason='基础法术自身伤害成长，不属于伤害修饰。' if r['id']=='grow_orb' else '普通单体攻击或自动发射单体攻击，不具备上述特征。'
        lines.append(f'{r["name"]} ({r["id"]})：{reason}')
lines+=['','逐项核查：']
classes={'basic':'基础','modifier':'修饰','control':'控制'}
for r in result:
    availability='可制作' if r['stations'] else '其他获取' if r['public'] else '旧档兼容'
    tags='、'.join(t['label'] for t in r['tags']) or '无额外标签'
    lines.append(f'{r["name"]} ({r["id"]}) | {classes.get(r.get("class"),"兼容")} / {availability} | {tags}')
    lines.append('  '+(r.get('effect') or '').replace('\n',' '))
output.with_suffix('.txt').write_text('\n'.join(lines)+'\n',encoding='utf8')
print(f'Exported {len(result)} spells: {output}')
