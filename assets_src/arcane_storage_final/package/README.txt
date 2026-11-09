粉尘收纳盒与奥术余烬灯：R3 美术交付包

本包包含透明源图、分层素材、状态帧、动画预览、物品栏图标及官方工具编译的动画和纹理。
这是独立的美术包；未修改 mod 脚本、未安装到游戏，未执行实机玩法验收。
空／半满／满是美术状态。无限容器的数量到状态映射由后续接入逻辑定义，满态不代表容量上限。
地面阴影依据各 clip_manifest.json 的 shadow 配置接入；已合成地影的世界帧不再叠加 DynamicShadow。物品栏图标不含地影。

目录：
  dustbox/、emberlamp/：生成源图、Prompt、分层、世界帧、图标及清单。
  runtime/anim/：可供 AnimState 使用的原生动画包。
  runtime/images/inventoryimages/：64 像素图标图集；使用 nw_arcane_storage.xml 的元素名称。
  animation_source/：官方编译器输入 ZIP，内含 build.xml、animation.xml 和逐帧 PNG。
  tools/：分层／动画／打包脚本及读取校验工具，支持仓库与独立解压目录。
  validation/：编译日志、资源检查报告、64／32 像素浅深底预览。
  review/review_r3.html：解压后直接打开即可逐项查看动画；review.html为同内容入口。

动画：
  bank/build: nw_dustbox; canvas: [160, 160]; anchor: [80, 148]
    closed_empty: 1 frames @ 30 fps
    opened_empty: 1 frames @ 30 fps
    open_empty: 13 frames @ 30 fps
    close_empty: 13 frames @ 30 fps
    closed_half: 1 frames @ 30 fps
    opened_half: 1 frames @ 30 fps
    open_half: 13 frames @ 30 fps
    close_half: 13 frames @ 30 fps
    closed_full: 1 frames @ 30 fps
    opened_full: 1 frames @ 30 fps
    open_full: 13 frames @ 30 fps
    close_full: 13 frames @ 30 fps
    closed: 1 frames @ 30 fps
    open: 13 frames @ 30 fps
    opened: 1 frames @ 30 fps
    close: 13 frames @ 30 fps
  bank/build: nw_emberlamp; canvas: [256, 320]; anchor: [128, 302]
    off_empty: 1 frames @ 30 fps
    off_half: 1 frames @ 30 fps
    burn_half: 16 frames @ 30 fps
    on_half: 1 frames @ 30 fps
    ignite_half: 16 frames @ 30 fps
    extinguish_half: 20 frames @ 30 fps
    off_full: 1 frames @ 30 fps
    burn_full: 16 frames @ 30 fps
    on_full: 1 frames @ 30 fps
    ignite_full: 16 frames @ 30 fps
    extinguish_full: 20 frames @ 30 fps
    idle: 1 frames @ 30 fps
    on: 16 frames @ 30 fps
    off: 1 frames @ 30 fps
    turn_on: 16 frames @ 30 fps
    turn_off: 20 frames @ 30 fps

图标元素：
  nw_dustbox.tex
  nw_dustbox_open_empty.tex
  nw_dustbox_open_half.tex
  nw_dustbox_open_full.tex
  nw_dustbox_open.tex
  nw_emberlamp.tex
  nw_emberlamp_empty.tex
  nw_emberlamp_half.tex
  nw_emberlamp_full.tex
  nw_emberlamp_half_lit.tex
  nw_emberlamp_full_lit.tex

独立包（macOS / Linux / Windows）：
  python3 -m pip install -r requirements.txt
  python3 tools/package_arcane_storage_art.py
默认校验并打包随包已编译资源；原生重新编译使用 --recompile 及Windows Klei工具链。
完整说明见BUILD.txt。

各图像的真正透明 Alpha 在 PNG 源图中保留。编译结果已检查 ANIM/BILD、KTEX、图集页数、动画名称、帧数、帧率及锚点。
