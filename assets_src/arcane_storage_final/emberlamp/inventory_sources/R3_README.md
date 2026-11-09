# R3 物品栏贴图

五种状态均由内置 image_gen 对既有独立 UI 母图进行修改；不是世界贴图缩小版。原始生成文件为 `r3_*_generated.png`，实际 Prompt 位于 `../prompts/r3_inventory_*.txt`。

`../export_inventory.py` 复用 R2 空盘图的固定灯体与接地石座，只替换统一的灯内区域，再使用共同裁剪和缩放导出 64×64 PNG。生成母图保留不变，合成后母图为 `r3_empty.png`、`r3_half.png`、`r3_full.png`、`r3_half_lit.png`、`r3_full_lit.png`。

空盘保留灯芯和固定环；半料从四周围住芯根；满料完全埋住固定环、仅露出少量芯尖。点燃时灯芯位于火焰内部，颜色与边缘弱化，前侧火焰覆盖其部分轮廓。

便携素材包内重建命令：`python3 emberlamp/export_inventory.py`。完整仓库内使用：`python assets_src/arcane_storage_final/emberlamp/export_inventory.py`。无需游戏 SDK；只需要 Pillow。与当前工作目录无关。

检查图为 `../inventory_review/r3_inventory_contact.png`（浅色和深色背景、64/32px）及 `../inventory_review/r3_contents_detail.png`（局部遮挡关系）。来源哈希、固定灯体区域、配准边界与输出列表见 `../inventory_manifest.json`。
