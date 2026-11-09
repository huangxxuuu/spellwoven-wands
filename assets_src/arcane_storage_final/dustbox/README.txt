粉尘首饰收纳盒 · 完整美术素材
日期：2026-11-09

沿用用户已确认的浅型梅紫色首饰盒：无脚、细黄铜边、双后铰链和紫晶小锁扣。
R2修正闭盖为上凸八角顶、斜切肩面、明确侧带厚度；保留已确认的打开内侧和原盒体。
R3按已确认的 concepts/lid_alignment_r3/closed_aligned.png 修正闭合后沿遮挡；紫色盖覆盖后侧金边和铰链残片，不改变凸盖结构。
全部可见绘画来自内置 image_gen，生成原图保留在 originals；实际提示词保留在 prompts。
parts 是母图拆出的原尺寸部件，world 是160×160的透明运行帧，inventory 是64×64专用图标。

状态与动作
- 空：内衬完整可见；半满：内壁上半部仍可见；满：粉尘接近金边内缘。
- 三档均有 closed、open、opened、close 动画资源。闭盖不透明，三档闭盖外观相同。
- 每次开合13帧、30fps，约0.43秒；反向使用同一组帧闭合。
- 固定盒体与两面盖分层，盖围绕同一铰链轴旋转；内容物层位于盒沿后方。
- R2将盖面投影与盖边厚度分别变换；接近侧视的中间帧仍保留侧带，不再一起压成平片。
- R3将固定盒体的后沿与前体拆层，只在0°、4°时按实际盖轮廓遮住后沿；11°及以后完整恢复原层。
- 本轮45张世界PNG全部重出；其中9张近闭合帧变化，另外36张、12张原始母图和5张UI图标的SHA256与R2完全一致。
- 空/半满/满是美术上的粉尘深度，不给无限容器引入容量上限或自动设定数量阈值。

尺寸与阴影
- 游戏帧160×160，地面锚点(80,148)，盒体约131像素宽，含地影最大宽144像素。
- 大多数母图与拆件1254×1254；R1闭盖图标源1536×1024，R2闭盖图标为1254×1254。
- 物品栏64×64，review/inventory_64_32.png同时检查64及32像素、浅深两种底色。
- R2参考原版极地熊獾桶(beargerfur_sack)的ground符号，生成不规则短线墨影，替换椭圆。
- 独立地影在parts/r2_ground_shadow.png，只向所有world帧合成一层；物品栏不含地影。
- 接入时必须关闭本物品的DynamicShadow，避免双影。当前美术任务未改mod，禁止直接混用旧影子配置。
- 地影控制在160画布内，底部保留透明安全边；preview不额外添加任何圆椭圆影子。
- 仅运行导出清理低至8/255的不可见Alpha杂点；原始生成图保持原样。

交付与验收
- clip_manifest.json：统一画布、锚点、所有动画名称/帧/帧率、图标与默认别名。
- review/states.png：闭盖与空/半/满地面外观。
- review/r3_lid_keyframes.png：0°、4°至全开的关键角度；lid_keyframes.png同为当前版本。
- review/r3_lid_volume.png：闭盖和中间角度的高分辨率体积检查。
- review/r3_rear_alignment.png：0°、4°、11°的后沿放大和真实运行帧检查。
- review/r3_open_close.gif：三档内容物依次开合的循环预览；open_close.gif同为当前版本。
- review/inventory_64_32.png：真正UI尺度的图标检查。
- generation_manifest.json：来源、实际Prompt与SHA256；qa.json：尺寸和结构检查。
- review/r3_baseline_verification.json：与修订前的哈希对照、实际变更帧、画布边距及开合互逆检查。
- originals/r2_*与prompts/r2_*：R2生成的源图和Prompt；原始R1文件保留供溯源。
- concepts/lid_alignment_r3：已批准的后沿修正效果图、实际Prompt及来源；本轮动画使用既有美术切层，不新增生图。
- parts/r3_body_front.png、r3_rear_rim.png及r3_rear_visible_00/04.png：拆出的固定层及近闭合遮挡结果。
- review/r2_*保留历史版本，当前验收请使用review/r3_*。

重新打包源帧：python3 tools/build_dustbox_jewellery_art.py（自动识别仓库或解压目录；需要Pillow及numpy）
该脚本只切分生成素材、变换盖面、合成动画和排版预览，不绘制新的物件表面。
本包为美术交付；未更改玩法、未设置粉尘数量档位、未修改或安装mod。

R3实际重新读取：AGENTS.md；docs/26_饥荒原版画风与生图基础规范.md；
docs/DST生图基础提示词.txt；docs/art/02_游戏内建筑规范.md；
物品栏未变更；原生成任务另按docs/art/03_游戏内物品栏贴图规范.md及系统imagegen/SKILL.md执行。
世界贴图以原版建筑参考板校准线条，物品栏另用原版inventory_contact.png校准简化度。
