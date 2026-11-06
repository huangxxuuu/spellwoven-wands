-- Shared data for in-world signs, supply boxes and the manual test reference.
local function wand(name,ids,capacity) return {name=name,wand=ids,capacity=capacity} end
local function item(prefab,count) return {prefab=prefab,count=count or 1} end
local function card(id) return {card=id} end
local function duo(id,name,steps,supplies,checks)
    local rows={}
    assert(#supplies==9,"each player gets one nine-slot box")
    for _,role in ipairs({"A","B"}) do for _,row in ipairs(supplies) do
        local copy={};for k,v in pairs(row) do copy[k]=v end
        if copy.name then copy.name=role.." · "..copy.name end
        rows[#rows+1]=copy
    end end
    return {id=id,name=name,steps=steps,items=rows,duo=true,boxlabels={"A 玩家用品","B 玩家用品"},checks=checks}
end
return {
    {id="ui",name="检查、改名与界面",steps={
        "检查卡和杖：只朗读名称；悬停显示作用简述和鼠标动作。",
        "羽毛笔右键背包或地上的杖：改中文名；确认耗一支，取消、空白、同名不消耗。",
        "换卡、施法、装箱、重进后名称保留；另一玩家也能看到。拖动法杖栏，检查 2/7/12 格。"},
        items={wand("改名用两格杖",{"spark"},2),wand("七格界面杖",{"spark","arrow"},7),wand("十二格界面杖",{},12),
            item("featherpencil",6),card("spark"),card("fire"),card("homing")}},
    {id="casting",name="施法、法力与编辑",steps={
        "空地 nw_range()。单击一组，按住连发、松手停止；冷却有效。分别在出手前、后移动打断。",
        "手持杖 nw_manaprobe()：缺蓝不射、不抽卡；松手后回蓝不自发。按住时走停应正常续发。",
        "奥术台旁换卡、满包换卡；离开后只读。手持执行 nw_saveprobe()，重进检查冷却。"},
        items={wand("基准火花",{"spark"}),wand("双重弹",{"double","spark","arrow"}),wand("节能连射",{"mana_reduce","recharge_down","spark"}),
            card("fire"),card("frost"),card("double"),item("twigs",40)}},
    {id="guidance",name="追踪与速度",steps={
        "空地执行 nw_range()，分别比较基准、追踪、短追、转向。短追只在 3 单位内启动，普通范围 8。",
        "追踪晶体能从静止出发，纯转向晶体不能；加速后转向可用。",
        "追踪起步应渐进，短追更快；50 是持续同向推进的趋近速度，不保证在撞靶前达到。"},
        items={wand("基准火花",{"long_life","long_life","spark"}),wand("普通追踪",{"homing","long_life","long_life","spark"}),
            wand("短距离追踪",{"near_homing","long_life","long_life","spark"}),wand("只转向",{"homing_rotate","long_life","long_life","spark"}),
            wand("零速追踪晶体",{"homing","sleep_crystal"}),wand("零速转向晶体",{"homing_rotate","sleep_crystal"}),
            wand("加速转向晶体",{"speed_up","homing_rotate","sleep_crystal"})}},
    {id="paths",name="弹道、碰撞与星体",steps={
        "在远离箱牌的空地建墙并执行 nw_range()。比较正弦卵、螺旋星与普通弹。",
        "移动晶体碰撞后停下且保留；反弹墙、穿墙、穿透多靶分别生效。",
        "星体移动后仍提供照明和温度；注意星体本身有长冷却。"},
        items={wand("正弦载荷卵",{"speed_up","sine","payload_egg","arrow"}),wand("螺旋星体",{"speed_up","spiral","edge_yellowstaff"}),
            wand("碰撞停车晶体",{"speed_up","sleep_crystal"}),wand("反弹晶体",{"speed_up","bounce","sleep_crystal"}),
            wand("穿墙晶体",{"speed_up","phase_wall","sleep_crystal"}),wand("穿透晶体",{"speed_up","pierce","sleep_crystal"}),
            wand("反弹普通弹",{"bounce","heavy"}),item("wall_stone_item",12)}},
    {id="gust",name="风压推动与阻力",steps={
        "分开放卵与两种晶体。风压击中卵只推动，不释放；不能推动或击破晶体。",
        "连续同向吹卵应叠加速度，反向吹可减速；无持续推进时速度约每 4 秒减半。",
        "卵停下后可再次吹动。用普通弹击破，应从卵的当前位置释放载荷。"},
        items={wand("空心载荷卵",{"payload_egg","arrow"}),wand("风压",{"gust"}),wand("加速风压",{"speed_up","gust"}),
            wand("近感晶雷",{"crystal_mine"}),wand("休眠晶体",{"sleep_crystal"}),wand("击破用火花",{"spark"})}},
    {id="revision",name="新法术与命中修饰",steps={
        "先用爆炸箭和穿透爆炸箭攻击测试靶：每次命中爆炸，周围敌友都可能受伤；单纯到期和穿墙不爆炸。",
        "定时散弹应留下三堆燃烧火药；单独火药等引线爆炸，再用水球扑灭另一堆，确认消失且不能拾取。",
        "分别用玩家武器、生物攻击、晶雷爆炸击破载荷卵；移动卵在岸边或船边停下，在海上生成会落水。"},
        items={wand("命中爆炸",{"explosion","arrow"}),wand("穿透爆炸",{"explosion","pierce","arrow"}),
            wand("三枚独立定时",{"scatter_timer","gunpowder"}),wand("燃烧火药",{"gunpowder"}),
            wand("载荷卵",{"payload_egg","spark"}),wand("移动载荷卵",{"speed_up","payload_egg","spark"}),
            wand("晶雷",{"crystal_mine"}),item("spear"),item("waterballoon",5)}},
    {id="payload",name="触发与分组",steps={
        "空地执行 nw_range()：碰撞载荷命中时释放，定时载荷到点释放，提前消失只补发一次。",
        "穿透碰撞载荷可多次触发，定时散弹每枚独立释放，合计三次。嵌套卵逐次击破。",
        "目标选择只管当前组：外层选自然物后，内层默认弹仍可攻击生物；内层选择卡需另放。"},
        items={wand("碰撞爆炸",{"explosion","arrow"}),wand("定时旋斩",{"arrow_timer","whirl"}),
            wand("提前消失",{"short_life","short_life","spark_timer","chain"}),wand("穿透碰撞",{"pierce","arrow_hit","chain"}),
            wand("定时散弹",{"scatter_timer","chain"}),wand("嵌套载荷卵",{"payload_egg","payload_egg","arrow"}),
            wand("外层自然物选择",{"target_nature","arrow_hit","arrow"}),item("pinecone",3)}},
    duo("multiplayer","双人：载荷归属与 PvP",{
        "各拿 A/B 箱。A 放归属卵，B 脱甲贴近后击破，只有 B 承受自身载荷；交换角色复测。",
        "A 放嵌套卵，B 开第一层、A 开第二层；最终自身载荷只伤 A。",
        "PvP 关/开分两轮测：指定其他玩家的箭只在开启时伤对方；默认箭不伤玩家。操作前恢复生命。"},
        {wand("归属验证卵",{"payload_egg","target_self","chain"}),wand("嵌套归属卵",{"payload_egg","payload_egg","target_self","chain"}),
         wand("击破火花",{"spark"}),wand("指定其他玩家",{"target_players_other","arrow"}),wand("默认箭",{"arrow"}),wand("风压",{"gust"}),
         item("spear"),item("healingsalve",6),card("target_self")},
        {
            {"归属切换","PvP 关闭，双方脱甲且血量足够；记录生命。","放一只归属验证卵，站在闪电搜索范围外。","靠近卵至 3 单位内，用长矛击破。","自身载荷只伤 B；A 不受伤。两人交换操作者后重测。"},
            {"嵌套换主","每轮新放一只嵌套归属卵。","放卵；B 打开第一层后，自己贴近并打开第二层。","贴近打第一层，第二层出现后退到 6 单位外。","最终自身载荷只伤 A；归属随每次触发者切换。"},
            {"PvP 矩阵","分别使用 PvP 关闭、开启的测试世界/配置。","先用默认箭，再用指定其他玩家箭射 B。","观察并记录血量，然后与 A 交换角色。","默认箭两轮都不伤玩家；指定其他玩家箭仅 PvP 开启时生效。"},
            {"竞争触发","新放一只归属卵，双方站在范围内并记录血量。","与 B 同时报数攻击卵。","与 A 同时攻击同一只卵。","仅释放一次、仅实际触发者承受自身载荷；可多轮重复，不应重复爆炸或报错。"},
        }),
    {id="persistence",name="永久实体与存档",steps={
        "放置静止机关、移动卵、追踪晶体和星体，保存重进。永久机关应仍在，速度/弹道状态保留。",
        "放置者离线、变幽灵或换分片时移动暂停，返回继续；卵仍可由别人触发。",
        "晶体移动后停下再引爆，应在停下位置生效。星体剩余寿命保存，不因重进重置。"},
        items={wand("静止晶雷",{"crystal_mine"}),wand("静止晶体",{"sleep_crystal"}),wand("移动卵",{"speed_up","payload_egg","arrow"}),
            wand("追踪晶体",{"homing","sleep_crystal"}),wand("移动矮星",{"speed_up","edge_yellowstaff"}),
            wand("移动极光",{"speed_up","edge_opalstaff"}),wand("晶体引爆",{"detonate"})}},
    {id="limits",name="射程、载荷层数与边界",steps={
        "默认限制关闭：长寿命弹可超过 30 单位；开启射程 30 后在累计路程达到时结束。",
        "嵌套卵测试载荷层数限制 1 与默认关闭；分支不另设限制。",
        "边界清理需单独开启：地图外缘再外 5 单位移除，天然屏障处立即移除，不释放载荷。海岸不是地图边界。"},
        items={wand("远射弹",{"speed_up","long_life","long_life","long_life","long_life","spark"}),
            wand("三层载荷卵",{"payload_egg","payload_egg","payload_egg","arrow"}),
            wand("分支载荷",{"payload_egg","triple","spark","arrow","heavy"}),
            wand("越界移动卵",{"speed_up","payload_egg","chain"}),item("boat_item"),item("oar")}},
    {id="cleanup",name="休眠计时与自动清理",steps={
        "独立测试世界开启永久移动实体清理。空地 nw_testcleanup(20)，离开所有玩家的活跃区域。",
        "16 分钟后 20 个应仍在；另处 nw_testcleanup(1)，旧实体应清理，新实体保留。",
        "另测中途进入活跃区重置；关闭设置不清理。20 分钟封顶、存档及数量独立计时见测试指南。"},
        items={wand("无目标待机卵",{"target_hostile","homing","payload_egg"}),wand("击破用火花",{"spark"})}},
    {id="tools",name="原版工具与海岸回归",steps={
        "岸边与船上互射测试靶；海钓鱼钩命中海鱼后，鱼应回到最近船上。鱼食落海产生诱饵。",
        "园艺锄落地耕作；镰刀收获草与作物；巨化星体的光照/温度范围扩大。",
        "逐项使用对应场景；海钓是当前全量实机回归中需要重点复核的项目。"},
        items={wand("海钓鱼钩",{"edge_oceanfishingrod"}),wand("鱼食",{"edge_chum"}),wand("园艺锄",{"edge_farm_hoe"}),
            wand("镰刀",{"target_nature","edge_voidcloth_scythe"}),wand("巨化矮星",{"giant_shot","edge_yellowstaff"}),
            item("boat_item"),item("oar"),item("dug_grass",4)}},
    {id="crafting",name="制作、卡堆与分解",steps={
        "右键合并卡片为牌堆；异种最多 25 格，同种卡可堆叠 40。满包时装卡、取卡不得丢失或复制。",
        "检查科学解锁、奥术台配方及刻印台消耗；离站后换卡不可用。",
        "分解炉 4 单位内放测试物品，中途走开应停止；完成后检查粉尘与法杖内卡片退回。"},
        items={item("nw_blank",8),card("spark"),card("arrow"),card("fire"),card("frost"),wand("分解试杖",{"spark","arrow"}),
            item("spear"),item("spear"),item("goldnugget",20),item("flint",20)}},
    duo("duo_ui","双人：改名、交接与编辑",{
        "各拿 A/B 箱。A 用笔改名，B 看地面和悬停名称；A 装箱、B 取出再改名，双方检查只读名称。",
        "两人同时用笔给同一根地面杖改名：只能一人编辑，取消不耗笔；换角色重测。",
        "奥术台旁交换杖、换卡；打开界面时把杖交给另一人，旧界面不能改对方物品。重进后复查名称和卡序。"},
        {wand("两格杖",{"spark"},2),wand("七格杖",{"spark","arrow"},7),wand("十二格杖",{},12),
         item("featherpencil",6),card("spark"),card("fire"),card("arrow"),card("homing"),card("damage_up")},
        {
            {"名称同步","先 A=房主、B=远端；专服则两人均为客户端。","在背包改中文名，再放箱；取 B 改过的杖检查。","从箱中取杖，检查名称和详情，再改英文名交回。","地面、背包、检查对白和悬停名称一致；确认各耗一支，取消/同名不消耗。"},
            {"同时改名","同一根杖放地上，两人都持羽毛笔。","先打开窗口保持不提交；随后取消。","A 编辑时尝试改名；A 取消后再尝试。","不应同时占用编辑窗口；取消释放占用，未成功改名者不耗笔。交换角色复测。"},
            {"交接与旧界面","靠近奥术台，两人记录自己卡片数。","打开改名/换卡界面后，将杖转交 B，再操作旧界面。","拿到杖检查卡序和名称，再装入自己的卡。","旧请求不能改 B 持有的杖；不丢卡、不复制卡；B 正常编辑，所有者更新后原界面关闭或失效。"},
            {"远端面板与存档","2/7/12 格杖分别测试。","拖动自己的法杖栏，装箱保存，正常重启世界。","拖动自己的栏，与 A 对比槽位和属性；重新加入后取杖。","布局只影响本人；名字、卡序、属性保存且双方一致；悬停仍有详情、检查只说名字。"},
            {"中英混合联机","两人分别选中文/English 后重进；另做自动模式且游戏语言不同的一轮。默认杖可由管理员 c_give(\"nw_wand\") 生成。","中文检查同一张卡和默认入门杖，打开制作栏、悬停和改名窗口。","英文做相同步骤；将默认名称原样确认，再改为自定义中文名交回 A。","双方各自显示本机语言，包含分类文字图标和检查对白；原样确认不耗笔，自定义名两端保持原文。交换语言后存档重进复测。"},
        }),
    duo("duo_motion","双人：施法、弹道与风压",{
        "空地 nw_range()。A 射击、B 从侧面看；单击、按住、走停、松手分别测，再换角色。",
        "A 放移动卵/星体，B 看曲线与撞墙停下；B 吹 A 的卵，双方看到同样位移，卵不释放载荷。",
        "B 继续守在远处靶旁，A 远离；A 的远射弹到达后 B 仍应看到命中效果。避免射向准备箱牌。"},
        {wand("普通追踪",{"homing","long_life","spark"}),wand("短距离追踪",{"near_homing","long_life","spark"}),
         wand("正弦卵",{"speed_up","sine","payload_egg","arrow"}),wand("螺旋矮星",{"speed_up","spiral","edge_yellowstaff"}),
         wand("停车晶体",{"speed_up","sleep_crystal"}),wand("风压",{"gust"}),
         wand("远射弹",{"speed_up","long_life","long_life","long_life","long_life","spark"}),item("wall_stone_item",12),item("spear")},
        {
            {"远端输入与命中","一人操作，一人侧面观察，记录延迟及移动预测开关。","单击、按住连发、走停、松手；分别在出手前后移动取消。","观察动作、出弹数和命中血量，再与 A 互换。","无双发、松手补发或明显回拉；双方看到同一弹道与命中，移动优先。"},
            {"移动场地实体","墙和靶放在远离箱牌的空地；星体有原生长冷却。","依次放正弦卵、螺旋星体、停车晶体。","在侧面观察，再用风压推动 A 的卵。","两人都看见曲线和撞墙停车；星体场地功能保留，风压仅推动卵且不释放载荷。"},
            {"远离发射者","射程限制关闭，直线通道约 40 单位，B 留在靶旁。","朝 B 所在靶区发射远射弹后向反方向离开。","持续观察来弹和目标生命，不离开靶区。","弹体离开发射者附近后继续移动，能在 B 附近命中；这不等于证明无任何玩家附近时的计时。"},
        }),
    duo("duo_presence","双人：离线、幽灵与分片",{
        "A 新放移动晶体、星体和归属卵，B 留守。A 去洞穴或变幽灵：移动暂停，实体保留，返回可继续。",
        "A 不在本分片时，B 贴近击破卵：自身载荷归 B。另放嵌套卵逐层换人检查。",
        "断线轮让客机担任 A，房主保持世界运行。保存重进后两人再检查实体与名称；每项新放实体，别先吹卵。"},
        {wand("移动晶体",{"speed_up","sleep_crystal"}),wand("移动矮星",{"speed_up","edge_yellowstaff"}),
         wand("移动极光",{"speed_up","edge_opalstaff"}),wand("归属卵",{"payload_egg","target_self","chain"}),
         wand("嵌套归属卵",{"payload_egg","payload_egg","target_self","chain"}),wand("火花",{"spark"}),
         item("spear"),item("healingsalve",6),item("reviver")},
        {
            {"客机断线与重连","让客机担任放置者 A，房主 B 留在线；专服可交换两人。","新放移动晶体/星体/卵后断线；随后重新加入同分片。","留守观察暂停，再贴近击破卵；保留其余实体等 A 回来。","实体保留、无效施法者时暂停；B 可释放归自己所有的载荷；重连后未停下的实体继续。"},
            {"跨分片","世界开启洞穴，每项新放实体，星体检查自身剩余寿命。","从地表进洞穴，稍后回地表。","留地表观察并击破另一只卵，记录效果。","A 离开本分片后移动暂停，B 触发载荷有效；A 返回后恢复。交换角色复测。"},
            {"幽灵与复活","按正常死亡/复活流程，测试前清空其他贵重物品。","新放实体后死亡成为幽灵，尝试操作卵，再由 B 复活。","观察暂停，保留一只卵自用触发；用告密的心复活 A。","幽灵不能作为有效触发者消耗卵；B 仍可触发；复活后符合条件的移动恢复。"},
            {"世界保存","两人都在线完成一轮后正常保存退出。","重开世界后检查自己放置的实体和法杖。","重新加入，检查载荷并触发一只旧卵。","实体状态、卡序和名字保存；星体不重置寿命，旧卵载荷属于这次触发者。"},
        }),
    duo("duo_cleanup","双人：活跃区与休眠清理",{
        "独立分片开启清理，管理员 nw_testcleanup(20)。A 离开、B 留守超过 16 分钟：旧卵必须保留。",
        "B 也离开，双方都不靠近，等 16 分钟；远处 nw_testcleanup(1)，旧卵才清除。勿另放永久移动实体。",
        "另起一轮：休眠途中仅 B 返回，再离开；计时应重置。按原版活跃区判定，不量 64 单位；换角色复测。"},
        {wand("待机卵",{"target_hostile","homing","payload_egg"}),wand("检查用火花",{"spark"}),
         item("torch"),item("lantern"),item("healingsalve",6),item("twigs",40),item("log",20),item("cutgrass",40),item("featherpencil",3)},
        {
            {"任一玩家保持活跃","分片无其他永久移动实体；开启清理，生成 20 个待机卵，附近无敌人。","远离测试区，全程不要返回。","留在卵附近超过 16 分钟，然后也离开。","只有 A 离开时不累计连续休眠；B 也离开后才开始。不得按放置者是否附近判断。"},
            {"数量与计时独立","双方都远离，保持服务器运行，不暂停、不关闭世界。","满 16 分钟后在远处执行 nw_testcleanup(1)。","留在远处，不为查看结果走回旧卵位置。","20 个时旧卵保留；第 21 个使门槛满足，旧卵清除，新卵保留。使用服务端统计确认。"},
            {"另一玩家重置计时","另起干净一轮，双方离开一段不足 16 分钟的时间。","始终留在远处；B 再次离开后重新计时。","独自进入卵所在活跃区，再离开。","旧计时重置，从最后一位玩家离开活跃区后重算；不得沿用最初 A 离开的时间。"},
        }),
}
