奥术余烬灯 · 完整美术素材
日期：2026-11-09
修订：R3，采用已确认的常驻灯芯、粉尘包围和火焰前层关系。

沿用用户确认的石底座、黄铜弯臂、挂环、黑色灯帽、紫晶灯盏与青紫火焰。
本轮“打开／关闭”已由用户明确为点燃／熄灭，不是灯盖机械开合。
所有新绘画来自内置 image_gen；原图与实际 Prompt 均保留。运行代码与玩法没有修改。

状态与动画
- 空、半满、满三种未点亮世界图；空档保留编织灯芯和固定环，半档粉尘包住芯根，满档粉尘带黑色外轮廓并埋住固定环，只露少量芯尖。
- 半满、满档分别有点燃、持续燃烧、熄灭动画；空档没有燃烧动画。
- 燃烧：8张不同火舌，30fps，每张停2帧，共约0.533秒。
- 点燃：从固定芯尖开始，逐渐向下包住露出的灯芯；6张生成过渡画加首尾静态，16帧／30fps，约0.533秒。
- 熄灭：8张新绘火舌从根部断开、分离上扬、碎焰消散，加首尾静态，20帧／30fps，约0.667秒。
- 整段熄灭共用一个画布、锚点和等比例缩放；不再逐帧压缩高度或重新贴底。
- 原版影灯使用 campfire_fire 的8张 flames_wide 火焰，参考其造型变化和节奏；本包火焰为新绘制的已确认青紫配色。
- 灯体只用一个固定母版，粉尘、灯芯和火焰分别拆层；用像素比较检查动画过程中支架、底座不跳动。
- 合成顺序为地影、灯体、常驻灯芯、包围芯根的前侧粉尘、前层火焰。燃烧时芯尖位于焰内，局部柔化及反光随火焰帧变化，不把整团火焰统一降透明度。
- 熄灭结束与对应未点燃帧逐像素一致，常驻灯芯不会随火焰一起消失。

目录与规格
- originals：生成原图，包括清楚标记为 superseded 的过程稿；最终选用情况见 generation_manifest.json。
- prompts：实际提交的世界与UI Prompt；序号缺口不代表缺少成品。
- layers：透明灯体、灯芯、粉尘、地影及逐帧火焰；均可独立调整。R3灯芯和满档粉尘提取自 originals/r3_unlit_wick_fuel.png，固定注册位置见 generation_manifest.json。
- world：256×320透明运行帧，地面锚点(128,302)，本体可见高度约285像素。
- inventory：64×64专用简化图标，三种未点亮、两种点亮及默认别名；检查图另含32像素预览。
- previews/states.png：三档存量与两档点亮预览。
- previews/r3_ignite_burn_extinguish_half.gif、r3_ignite_burn_extinguish_full.gif：本次修订的完整启灭与燃烧预览。
- previews/r3_extinguish_lamp.gif：独立熄灭预览，使用最终落地石基、地影和常驻灯芯。
- previews/r3_wick_detail.png：空、半、满及两档点燃的局部遮挡对照。
- clip_manifest.json：全部动画、帧率、图标与影子配置。
- generation_manifest.json、inventory_manifest.json：来源与提示词溯源。

阴影与分层
地影参考原版极地熊獾桶的独立 ground 短线墨影重新绘制，另存 layers/ground_shadow.png。
中央大石与两角小石共同落地；原先架空的中央缺口已由真实石体补齐。
地影由石体向地面投下的短线、贴底接触影和少量土痕构成，不再表现为悬空底座下的一大块黑影。
地影源图为 originals/r2_ground_contact.png，未沿用上一版科学机器阴影。
地影在世界动画导出时合成，接入这个动画包时不要再叠加 DynamicShadow；物品栏不含地影。
灯光由后续游戏组件控制，PNG不烘焙大面积光晕。所有镂空及背景保留真透明Alpha。
运行导出仅清理 <=8/255 的近透明杂点，并把 >=247/255 的内部覆盖规范为不透明；原图保持不变。

复建
独立解压包内（需要Pillow及numpy）：
python3 tools/build_emberlamp_art.py
python3 emberlamp/export_inventory.py
python3 tools/package_arcane_storage_art.py --preview-only

完整仓库内，把emberlamp/脚本路径替换为assets_src/arcane_storage_final/emberlamp/。
R3主构建直接读取随包的固定锚点熄灭分层，无需运行旧版export_r2_extinguish.py。
构建工具会按自身位置识别目录，无需在Mac上创建Windows路径。
跨平台默认打包：python3 tools/package_arcane_storage_art.py，校验并复用随包已编译资源。
修改运行帧、图标或动画清单后，原生资源需要在Windows Klei工具链中使用--recompile重新编译；详见包根目录BUILD.txt。

这是美术交付；三档与数量、燃料时间的映射尚未接入，没有自动引入新的容量或消耗规则。
