# 当前使用：奥术台 B2，武器刻印台与分解炉 B1（2026-11-10）

奥术台采用 `assets_src/stations_art_directions_20261110/B_round_2/workbench.png`；武器刻印台和奥术分解炉继续采用同级 `B_round_1/` 中的源图。`selected.json` 记录三张原始源图、固定运行尺寸及 B1 炉体的发光定位；原始源图与实际生成 Prompt 保留在各轮目录。

运行 `.venv/Scripts/python.exe tools/build_station_art.py` 编译世界本体、分解炉 8 帧工作循环与 3 帧分解脉冲，以及三座建筑的制作图标和两个制作站页签图标。然后运行 `.venv/Scripts/python.exe tools/build_guide_art.py` 更新指南插图。编译保留原有动画名、实体缩放、碰撞与锚点；复用原版接地影和脚边土纹。所有分解状态基于同一 B1 炉体，不需要追加生图。

`build_report.json` 保存本次构建的源图哈希及输出信息。仅本地测试安装使用 `tools/install_mod.py`；本次不提升版本或发布。

## 历史：A3 武器刻印台与 B2 奥术分解炉

`stations.png` 是使用内置 imagegen 生成的透明母图。第一张参考图是已选方案板，第二张是奥术台的运行贴图。制作菜单、地图与场景资源均由 `tools/build_station_art.py` 从母图编译。下方为实际生成提示词。

> Create game-ready transparent sprite atlas. FIRST IMAGE design reference and SECOND IMAGE brush style reference. TWO individual isolated full objects left and right, separated by generous empty vertical gutter at center. Left: faithfully recreate TOP RIGHT design A3 weapon inscribing bench, spear and axe crossed behind dark timber sloping desk with old copper corners, parchment at front, articulated purple crystal stylus on right. Right: faithfully recreate CENTER idle B2, crescent aged dark bronze cradle, teal white faceted hanging diamond crystal aligned directly above dark hollow opening of round rough stone kiln. No flames, no ring on the ground, no labels, no letters, no panel borders, no ground planes, subtle foot contact shadows only. Consistent with SECOND IMAGE existing DST workbench: hand-inked, chunky but delicate angular wood grain, dark irregular linework, slightly gothic, muted hardware edge highlights. Equal screen size, centered in respective halves; horizontal landscape canvas; entire object including spear tips and crescent visible. Both front three-quarter DST inventory world sprite view. Transparent negative spaces and hollow spaces.
