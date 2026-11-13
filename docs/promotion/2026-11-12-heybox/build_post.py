"""Assemble a local editorial draft using existing, unmodified project media."""
from pathlib import Path
from PIL import Image, ImageSequence
import hashlib
import html
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
MEDIA = OUT / '素材'
MEDIA.mkdir(exist_ok=True)
TITLE = '把 Noita 式法杖编排做进饥荒：自制 Mod《织法之杖》'
WORKSHOP = 'https://steamcommunity.com/sharedfiles/filedetails/?id=3834454416'
GUIDE = 'https://huangxxuuu.github.io/spellwoven-wands/'
VIDEO = 'https://www.bilibili.com/video/BV1Ki4H6GEWb/'
REFERENCE = 'https://xiaoheihe.cn/app/bbs/link/a5ab72cde830'
media = [
 ('00-封面.png', 'assets_src/workshop_table_icon_v7/zh/source.png'),
 ('01-法术组合.gif', 'docs/workshop-media/2026-11-08/01-combos.gif'),
 ('02-触发载荷.gif', 'docs/workshop-media/2026-11-08/02-payloads.gif'),
 ('03-采收.gif', 'docs/workshop-media/2026-11-08/04-harvest.gif'),
 ('04-海钓.gif', 'docs/workshop-media/2026-11-08/05-ocean-fishing.gif'),
 ('05-移动星体.gif', 'docs/workshop-media/2026-11-08/06-homing-star.gif'),
 ('06-巨化星体.gif', 'docs/workshop-media/2026-11-08/07-giant-star.gif'),
 ('07-乐器演奏.jpg', 'docs/workshop-media/2026-11-08/08-music.jpg'),
 ('08-三座设施.png', 'docs/workshop-media/2026-11-10/03-stations.png'),
 ('09-卡牌收纳.jpg', 'docs/workshop-media/2026-11-08/03-cardpile.jpg'),
]
manifest = []
for name, source in media:
    src = ROOT / source
    dst = MEDIA / name
    shutil.copyfile(src, dst)
    with Image.open(dst) as im:
        row = dict(file='素材/' + name, source=source, width=im.width, height=im.height,
                   bytes=dst.stat().st_size, frames=getattr(im, 'n_frames', 1),
                   sha256=hashlib.sha256(dst.read_bytes()).hexdigest())
        if row['frames'] > 1:
            row['duration_seconds'] = round(sum(f.info.get('duration', 0) for f in ImageSequence.Iterator(im)) / 1000, 3)
    assert src.read_bytes() == dst.read_bytes()
    manifest.append(row)

# Each block becomes both copyable text and a local illustrated reading preview.
blocks = [
 ('p', '大家好，来分享一下我做的《饥荒联机版》Mod：织法之杖。'),
 ('p', '灵感来自《Noita》的法杖编排：收集不同属性的法杖，把法术卡装进去，再用追踪、多重施法、碰撞触发这些效果，搭出自己的组合。打完怪换一套卡，还能收草、海钓，甚至在营地里弹琴。'),
 ('p', '工坊已经可以订阅，搜「织法之杖」即可。也把链接放在前面，方便感兴趣的盒友找：'),
 ('link', WORKSHOP, 'Steam 创意工坊：织法之杖'),
 ('image', '00-封面.png', '织法之杖 · Spellwoven Wands'),
 ('h', '制作思路：让玩家自己决定法杖怎么用'),
 ('p', '我想做的是一套可以反复折腾的法术组合玩法。同样一张火花弹，前面加追踪，就能拐弯找目标；加上多重施法，又能和其他法术一起发射。换卡、调整顺序，再试一发，这个过程本身就是乐趣。'),
 ('p', '不用玩过 Noita 也能上手，先从两三张卡的小组合开始就行。'),
 ('h', '先看看打起来是什么样'),
 ('p', '比如「追踪 → 火花弹」，或者「双重施法 → 火花弹 → 魔法箭」。后面还可以尝试三叉齐射、穿透、弹跳、环绕，慢慢往自己的搭配里加东西。'),
 ('image', '01-法术组合.gif', '换几张卡，试试不同的发射方式。'),
 ('p', '再往里玩，就能把下一道法术藏进触发效果里。比如「魔法箭·碰撞 → 旋斧攻击」，先射出箭，命中后在那个位置放出旋斧；换成定时载荷，释放时机也会改变。'),
 ('image', '02-触发载荷.gif', '碰撞与定时载荷演示；其中定时旋斧片段为 0.5 倍慢放。'),
 ('p', '法杖本身也有随机属性。槽位、法力、回蓝和施法间隔都会影响手感，非乱序杖按卡序施放，乱序杖则会洗牌。所以捡到一根新杖，也可以重新琢磨适合它的卡组。'),
 ('h', '出门干活，也能带着它'),
 ('p', '熟悉的武器和工具可以在武器刻印台做成法术卡。除了用来战斗，也保留了一些生活用途。比如暗影收割者可以沿途采收草丛和树枝，近处的收获在条件允许时会进背包。'),
 ('image', '03-采收.gif', '换上采收法术，顺路补一点营地物资。'),
 ('p', '海边则可以先用鱼食诱鱼，再用海钓竿刻印投出鱼钩，把钩中的海鱼或漂浮物朝自己这边送到附近的岸或船上。也有用于池塘的淡水钓竿和翻土用的园艺锄。'),
 ('image', '04-海钓.gif', '带法杖去海钓；这段演示包含剪接。'),
 ('h', '把星星带着走'),
 ('p', '唤星、唤月法杖刻印可以生成原版矮星或极光。搭配移动、追踪和目标选择卡，还能让星体跟着人物移动。'),
 ('image', '05-移动星体.gif', '会跟着人物移动的星体。'),
 ('p', '再加上弹体巨化，星体会变大，照明、温度和理智的作用范围也会扩大。巨化不直接增加伤害数值，星体法术仍然有自己的冷却下限。'),
 ('image', '06-巨化星体.gif', '巨化星体的外观与作用范围演示。'),
 ('h', '还有一个用途：在营地开音乐会'),
 ('p', '法杖里也能放陶笛、弦琴音符，按卡牌顺序演奏，再用升降音卡调整音高。我用弦琴卡组演示了一小段《深海少女》，下面放的是卡组截图，声音可以点视频听。'),
 ('image', '07-乐器演奏.jpg', '弦琴卡组实机截图。GIF 没有声音，演奏请看下方视频。'),
 ('link', VIDEO, '弦琴演奏《深海少女》片段（含游戏原声）'),
 ('p', '音符间隔仍受法杖属性和施法动作等因素影响，编排旋律时也需要调整节奏。'),
 ('h', '订阅之后怎么玩'),
 ('p', '房主在世界里启用 Mod，参与的玩家也需要安装。默认首次进世界会拿到一根装好火花弹的两槽入门杖，装备后右键施法。'),
 ('p', '接下来靠近炼金引擎，搜索并建造「奥术台」，就能开始制作和换卡。三座设施各有分工：奥术台负责制作与编辑，武器刻印台负责刻印，奥术分解炉负责回收附近地上的废卡和法杖。分解前记得收好要保留的东西。'),
 ('image', '08-三座设施.png', '从左到右：奥术台、武器刻印台、奥术分解炉。'),
 ('p', '卡牌除了制作和刻印，也来自生物掉落和首领战利品，部分卡只能通过掉落获得。散卡可以叠成最多 25 张的牌堆，方便收纳；想比较搭配，也可以用法术测试拳击袋测伤害。'),
 ('image', '09-卡牌收纳.jpg', '收集到的散卡可以叠成牌堆。'),
 ('p', '支持中文和 English，掉落率与多项性能限制可以在 Mod 设置里调整。复杂组合可以逐步尝试，尤其是爆炸类法术，试招时记得离自己和队友远一点。'),
 ('p', '欢迎感兴趣的盒友订阅试试，也欢迎分享自己的搭配。遇到问题可以在工坊反馈，带上 Mod 版本、卡牌顺序和复现步骤，会更方便排查。'),
 ('link', WORKSHOP, '工坊订阅'),
 ('link', GUIDE, '中文资料站与完整法术图鉴'),
 ('p', '如果是你，会先配一根打怪杖、干活杖，还是拿它来弹琴？'),
 ('note', '演示使用拍摄用测试杖，属性不代表正常获取的法杖。实机素材录制于早期正式版，部分贴图与当前版本可能略有不同。作者：yuejian；开发使用 Codex；玩法灵感来自《Noita》。'),
]
plain = [TITLE, '']
rendered = []
for block in blocks:
    kind, value, *rest = block
    v = html.escape(value)
    if kind == 'image':
        caption = rest[0]
        plain.append(f'【插入素材：{value}】\n{caption}')
        rendered.append(f'<figure><img src="素材/{v}" alt="{html.escape(caption)}"><figcaption>{html.escape(caption)}</figcaption></figure>')
    elif kind == 'link':
        plain.append(rest[0] + '：' + value)
        rendered.append(f'<p><a href="{v}">{html.escape(rest[0])}</a></p>')
    elif kind == 'h':
        plain.append(value)
        rendered.append(f'<h2>{v}</h2>')
    else:
        plain.append(value)
        rendered.append(f'<p class="{"note" if kind == "note" else "body"}">{v}</p>')
plain_text = '\n\n'.join(plain).strip() + '\n'
(OUT / '帖子正文.txt').write_text(plain_text, encoding='utf-8-sig')
css = '''*{box-sizing:border-box}body{margin:0;background:#f4f4f4;color:#262626;font:17px/1.85 "Microsoft YaHei",sans-serif}main{max-width:760px;margin:32px auto;padding:40px 44px;background:white}h1{font-size:28px;line-height:1.5;margin:0 0 24px}h2{font-size:22px;margin:38px 0 14px}p{margin:18px 0;overflow-wrap:anywhere}figure{margin:24px 0}img{display:block;width:auto;max-width:100%;height:auto;margin:auto}figure:first-of-type img{max-height:540px}figcaption{font-size:13px;color:#777;line-height:1.6;margin:10px 0;text-align:center}a{color:#2475bd}.note{font-size:13px;color:#777;border-top:1px solid #eee;padding-top:20px}.draft{font-size:12px;color:#777;margin-bottom:20px}@media(max-width:600px){main{margin:0;padding:24px 20px}h1{font-size:24px}body{font-size:16px}}'''
(OUT / '图文预览.html').write_text('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>' + html.escape(TITLE) + '</title><style>' + css + '</style></head><body><main><div class="draft">本地图文草稿 · GIF 可播放 · 尚未发布</div><h1>' + html.escape(TITLE) + '</h1>' + ''.join(rendered) + '</main></body></html>', encoding='utf-8')
(OUT / '素材清单.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
instructions = f'''小黑盒帖子草稿与素材包

主标题：{TITLE}
备用标题：做了一个能配法术、海钓、弹琴的饥荒 Mod：织法之杖

用法
1. 打开「图文预览.html」查看完整排版与动图。
2. 将「帖子正文.txt」分段粘贴到小黑盒编辑器；遇到【插入素材】标记时上传同名文件，并删除标记。下面一行是对应图注，可保留。
3. 封面选「00-封面.png」；其余文件已按正文插入顺序编号。共 4 张静态图、6 个 GIF，均为已有素材的原文件副本。
4. 发布到饥荒联机版相关社区。具体图片数量、GIF大小与压缩行为以当时编辑器为准，本任务未登录或测试小黑盒发布端。
5. 若编辑器限制篇幅或图片数，可先省略 06-巨化星体.gif 与 09-卡牌收纳.jpg，保留相应简短文字。不要删掉测试杖、慢放与剪接说明。
6. GIF 无声，音乐部分保留 B 站链接；也可自行在平台编辑器内关联已有视频。

参考与事实核对
参考帖：改进懒人传送塔mod，作者「乱杀的王」。
链接：{REFERENCE}
读取方式：2026-11-12 用无头 Edge 渲染公开分享页，已读正文。采用作者自荐、制作想法、具体玩法、订阅与反馈的结构，未挪用对方正文或媒体。
功能事实：docs/Steam创意工坊介绍.txt、README.md、docs/releases/1.0.5-public.txt。
设施图：使用 docs/workshop-media/2026-11-10/03-stations.png。
其余实机图与GIF：docs/workshop-media/2026-11-08/；保留拍摄用测试杖、0.5倍慢放、海钓剪接的说明。
封面：assets_src/workshop_table_icon_v7/zh/source.png；复用现有图片，本次未重新生图或修改图片。
本包为待审阅草稿，不代表已经发布或用户确认对外文案。没有修改 Mod、工坊页面、版本号或发布记录。

完整来源、尺寸、时长与 SHA-256 见「素材清单.json」。
'''
(OUT / '使用说明.txt').write_text(instructions, encoding='utf-8-sig')
zip_path = OUT / '织法之杖-小黑盒图文素材包.zip'
with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for name in ['帖子正文.txt', '图文预览.html', '素材清单.json', '使用说明.txt']:
        archive.write(OUT / name, name)
    for name, _ in media:
        archive.write(MEDIA / name, '素材/' + name)
print(json.dumps({'output':str(OUT),'media_count':len(manifest),'zip_bytes':zip_path.stat().st_size,'text_characters':len(plain_text)},ensure_ascii=True))
