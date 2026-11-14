local chinese = (locale and locale:lower():match("^zh") ~= nil) or locale == "chs" or locale == "cht"
local function L(zh,en) return chinese and zh or en end
name = L("织法之杖","Spellwoven Wands")
version = "1.0.7"
local release_date = "2026-11-15"
description = L("版本：", "Version: ")..version..L(" · 更新：", " · Updated: ")..release_date.."\n\n"..L(
    "【从这里开始】\n靠近炼金引擎，在「原型工具和制作站」「魔法」分类或直接搜索建筑名。\n奥术台（先建）：木板×2、石砖×2、金块×4、紫宝石×2。研磨宝石、制作法杖和卡；靠近并装备法杖即可装卡、换卡。\n武器刻印台：木板×2、石砖×2、紫宝石×1。将配方指定的武器或工具刻成卡，回奥术台装杖。\n奥术分解炉：石砖×2、紫宝石×1、奥术粉尘×4。粉尘先在奥术台制作。废卡、废杖丢炉边，右键炉子回收；要保留的散卡先收好。\n\n先建奥术台，其余按需补建。科学机器旁用草×3、木板×1制作「法术测试拳击袋」。装备法杖，点编辑框右上角「？」打开资料站。\n\n自由排列法术卡，编织连招！灵感来自《Noita》，支持中文与 English。",
    "GETTING STARTED\nNear an Alchemy Engine, find these stations under Prototypers & Stations or Magic, or search by name.\nArcane Workbench (build first): 2 Boards, 2 Cut Stone, 4 Gold Nuggets, 2 Purple Gems. Grind gems and craft wands/cards. Equip a wand nearby to edit its cards.\nWeapon Engraving Table: 2 Boards, 2 Cut Stone, 1 Purple Gem. Engrave the recipe's weapons/tools into cards; install at the workbench.\nArcane Recycler: 2 Cut Stone, 1 Purple Gem, 4 Arcane Dust (craft dust at the workbench). Drop unwanted cards/wands nearby and right-click to recycle. Store cards you want to keep safely away.\n\nAdd the last two stations as needed. At a Science Machine, craft a Spell Test Punching Bag with 3 Cut Grass and 1 Board. Equip a wand and click the editor's top-right ? for the field guide.\n\nArrange spell cards and weave combos! Inspired by Noita. Chinese and English supported."
)
author = "yuejian"
forumthread = ""
api_version = 10
dst_compatible = true
all_clients_require_mod = true
server_only_mod = false
client_only_mod = false
icon_atlas = L("modicon.xml", "modicon_en.xml")
icon = L("modicon.tex", "modicon_en.tex")
priority = 0

local payload_depth_options={{description=L("关闭（不限层数）","Off (unlimited depth)"),data=0,hover=L("不限制载荷嵌套层数。","No payload nesting depth limit.")}}
for depth=1,30 do
    payload_depth_options[#payload_depth_options+1]={description=depth..L(" 层"," layers"),data=depth,hover=L("最多触发 ","Trigger up to ")..depth..L(" 层载荷；根法术不计层数。"," payload levels; the root spell does not count.")}
end
local function ModOptions(title, hover)
    return {
        name = title,
        hover = hover,
        options = {{description = "", data = false}},
        default = false
    }
end
local function DropRateOptions()
    local options={{description=L("0 倍（关闭）","0x (Off)"),data=0}}
    local multipliers={.5,1,2,3,5,10}
    for i=1,#multipliers do
        local multiplier=multipliers[i]
        options[#options+1]={description=multiplier..L(" 倍","x"),data=multiplier}
    end
    return options
end

local function CountOptions(values, zh, en)
    local options={{description=L("不限","Unlimited"),data=0,hover=L("关闭此项上限。","Disable this limit.")}}
    for i=1,#values do options[#options+1]={description=values[i].."",data=values[i],hover=L(zh,en)..values[i]..L("。",".")} end
    return options
end
local live_options={25,50,100,200,300,400,500,600,700,800}
configuration_options = {
    {name="language",label="语言 / Language",default="auto",
      hover=L("仅影响本机显示；自动跟随游戏语言，中文环境使用中文，其余使用英文。更改后重新进入世界。", "Local display only. Auto uses Chinese for Chinese game locales, English otherwise. Rejoin the world after changing."),
      options={{description="自动 / Auto",data="auto",hover=L("跟随游戏语言：中文环境用中文，其余用英文。","Follow the game locale: Chinese for Chinese locales, English otherwise.")},{description="中文",data="zh",hover=L("本机界面使用中文。","Use Chinese for the local interface.")},{description="English",data="en",hover=L("本机界面使用英文。","Use English for the local interface.")}}},
    { name="base_damage_multiplier",label=L("基础伤害倍率","Base damage multiplier"),default=1,
      hover=L("调整法术卡的基础伤害，游戏内显示同步使用调整后的数值。", "Adjust spell cards' base damage; in-game displays use the adjusted values."),
      options={{description=L("0.5 倍","0.5x"),data=0.5,hover=L("法术卡基础伤害及游戏内显示调整为0.5倍。","Set spell card base damage and its in-game display to 0.5x.")},{description=L("0.75 倍","0.75x"),data=0.75,hover=L("法术卡基础伤害及游戏内显示调整为0.75倍。","Set spell card base damage and its in-game display to 0.75x.")},{description=L("1 倍（默认）","1x (Default)"),data=1,hover=L("保留法术卡原有基础伤害及游戏内显示。","Keep the original spell card base damage and its in-game display.")},{description=L("1.25 倍","1.25x"),data=1.25,hover=L("法术卡基础伤害及游戏内显示调整为1.25倍。","Set spell card base damage and its in-game display to 1.25x.")},{description=L("1.5 倍","1.5x"),data=1.5,hover=L("法术卡基础伤害及游戏内显示调整为1.5倍。","Set spell card base damage and its in-game display to 1.5x.")}} },
    { name="world_difficulty",label=L("世界难度","World difficulty"),default="fun",
      hover=L("爽快保留原有规则。平衡：同次施法对同一目标伤害递减，最低20%，10秒未命中重置；心神消耗增加，SAN不足以饥饿补足，两者耗尽仍可施法；新法杖基础回充延长，配卡仍可降至0。平衡·掉落限定另禁用法术卡配方；材料配方保留；兜底散卡概率为5倍。各世界独立设置，可选择不同难度；重启对应世界后生效。", "Fun keeps the original rules. Balanced: repeated hits from one cast decay to 20%, resetting after 10 seconds without a hit; increased SAN cost, with hunger covering any shortfall; empty reserves do not block casting. New wands recharge more slowly, but cards can still reduce recharge to zero. Loot Only also disables spell card recipes; material recipes remain available. Fallback loose-card chance is multiplied by 5. Each world is configured independently and may use a different difficulty. Restart the corresponding world to apply."),
      options={{description=L("爽快","Fun"),data="fun",hover=L("保留原有伤害、心神消耗、回充与制作规则。","Keep the original damage, mental cost, recharge and crafting rules.")},{description=L("平衡","Balanced"),data="balanced",hover=L("启用连击伤害递减、更高心神消耗与更慢基础回充；保留制卡。","Enable repeated-hit damage decay, higher mental cost and slower base recharge; keep card crafting.")},{description=L("平衡·掉落限定","Balanced: Loot Only"),data="balanced_loot",hover=L("基于平衡，禁用法术卡配方；兜底散卡概率5倍。","Balanced rules; disable spell card recipes. Fallback loose-card chance is 5x.")}} },
    { name="starting_wand",label=L("给予出门法杖","Starting wand"),default=true,
      hover=L("玩家首次进入这个世界时，获得一把已装有火花弹的两槽入门法杖。","Gives each player a two-slot Starter Wand with a Spark Bolt when they first enter this world."),
      options={{description=L("开启","On"),data=true,hover=L("首次入世时给予已装火花弹的入门法杖。","Give a Starter Wand with Spark Bolt on first entering this world.")},{description=L("关闭","Off"),data=false,hover=L("首次入世时不赠送法杖。","Do not give a wand on first entering this world.")}} },
    ModOptions(L("掉落率","Drop rates"),L("调整成品法术卡与法杖的掉落概率。","Adjust drop chances for spell cards and wands.")),
    { name="card_drop_rate",label=L("生物成品法术卡掉率","Creature spell card drop rate"),default=1,
      options=DropRateOptions() },
    { name="wand_drop_rate",label=L("常规首领成品法杖掉率","Regular boss wand drop rate"),default=1,
      options=DropRateOptions() },
    ModOptions(L("兼容性","Compatibility"),L("遇到功能冲突时，可单独禁用对应功能。","Disable individual features if they conflict with other mods.")),
    { name="disable_crafting_filter",label=L("禁用制作栏分类与标签","Disable crafting classes and tags"),default=false,
      options={{description=L("关闭","Off"),data=false},{description=L("开启","On"),data=true}} },
    { name="disable_dark_fog",label=L("禁用暗雾效果","Disable Dark Fog effects"),default=false,
      options={{description=L("关闭","Off"),data=false},{description=L("开启","On"),data=true}} },
    ModOptions(L("性能优化","Performance"),L("数量上限、载荷层数与实体清理；可自行调整或关闭。","Entity limits, payload depth and cleanup; adjustable or optional.")),
    { name="client_trail_limit",label=L("客户端尾焰总上限","Client trail segment limit"),default=1700,
      hover=L("作为本机初始值；向导中的个人尾焰设置保存后优先。仅影响本机显示：所有玩家的尾迹共用总额，默认1700；总数达到上限的75%时跳过其他玩家或无归属的新尾段，达到完整上限时也跳过自己的新尾段。已有尾段自然消散，不删除旧尾段腾位置。不影响弹体和伤害。更改后重新进入世界。","Initial client default; a saved personal choice in the guide takes priority. Local display only: all trails share one budget. Default: 1700; skips other players' or unowned new tails at 75% of the total limit, and your own new tails at the full limit. Existing tails fade naturally without eviction. Does not affect projectiles or damage. Rejoin after changing."),
      options=CountOptions({100,500,900,1300,1700,2100,2500,2900,3300},"本机所有尾迹共用的尾段总上限：","Total local trail segment budget: ") },
    { name="limit_projectiles",label=L("玩家活动弹体上限","Live projectiles per player"),default=600,
      hover=L("默认600。只统计实际活动弹体及近战攻击实体，不预留未触发载荷。每次生成前判断，满额时只跳过该实体，整次施法照常消耗法力并进入冷却。无额外固定分片上限。", "Default: 600. Counts live projectiles and melee attack entities, never future payloads. At capacity, skips only the next emission; casting still spends mana and enters cooldown. No additional fixed shard cap."),
      options=CountOptions(live_options,"每位玩家最多保留的活动弹体及近战攻击实体：","Live projectile and melee entity limit per player: ") },
    { name="limit_fields",label=L("玩家限时驻留实体上限","Timed spell entities per player"),default=200,
      hover=L("默认200。哨株、雷云、残光、星体等限时驻留法术共享额度。满额跳过新增，已有实体自然结束。", "Default: 200. Sentries, clouds, lingering lights, stars and other timed placements share this budget. Skip new spawns at capacity; existing entities expire normally."),
      options=CountOptions(live_options,"每位玩家限时驻留法术共用的实体上限：","Shared timed spell entity limit per player: ") },
    { name="limit_permanent_fields",label=L("玩家不限时驻留实体上限","Permanent spell entities per player"),default=100,
      hover=L("默认100。晶体和载荷卵共用独立额度。满额静默移除该玩家最早创建的实体，再生成新的；不引爆、不释放载荷。读档保留创建顺序。", "Default: 100. Crystals and payload eggs share a separate budget. At capacity, silently replace this player's oldest placement without detonation or payload release. Saves retain creation order."),
      options=CountOptions(live_options,"每位玩家永久晶体与载荷卵共用的实体上限：","Shared permanent crystal and payload egg limit per player: ") },
    { name="limit_range",label=L("子弹累计射程限制","Projectile travel limit"),default=0,
      hover=L("默认关闭，飞行距离由弹速和寿命决定。开启后限制每枚飞行子弹的累计路程，载荷子弹单独计算；不限制永久场与星体。","Off by default: speed and lifetime determine travel. When enabled, caps each projectile's total path length; payload projectiles count separately. Does not limit permanent fields or stars."),
      options=CountOptions({60,120,240,480,960},"每枚飞行子弹的累计路程上限（世界单位）：","Total travel limit per flying projectile (world units): ") },
    { name="limit_depth",label=L("载荷嵌套层数限制","Payload nesting limit"),default=5,
      hover=L("默认5层。根法术不计层数；触发时超过层数就跳过该载荷，不阻止根施法，也不影响已经生成的弹体。","Default: 5 levels. The root does not count. Payloads beyond the selected depth are skipped when triggered; the root cast and existing projectiles continue."),
      options=payload_depth_options },
    { name="boundary_cleanup",label=L("越界法术实体清理","Out-of-bounds cleanup"),default=true,
      hover=L("仅清理本 Mod 法术实体：无天然边界墙时，离开有效陆地或海洋边界 5 单位后移除；有天然边界墙时到达即移除。清理不释放载荷或终结效果。","Only affects this mod's spells. Removes them 5 units beyond valid land/ocean, or on reaching a natural boundary wall. Cleanup does not release payloads or final effects."),
      options={{description=L("开启","On"),data=true,hover=L("移除越过有效地图边界的法术实体，不触发载荷。","Remove spells beyond valid map boundaries without triggering payloads.")},{description=L("关闭","Off"),data=false,hover=L("不按地图边界自动清理法术实体。","Do not automatically remove spells at map boundaries.")}} },
    { name="permanent_motion_cleanup",label=L("永久移动实体自动清理","Permanent motion cleanup"),default=true,
      hover=L("按原版活跃／休眠区域独立计时，不足 21 个也累计。分片永久移动晶体与载荷卵超过 20 个时，清理连续 16 分钟处于休眠区域的实体。累计最多 20 分钟，回到活跃区域重置；静止机关与有寿命的星体不计入。","Uses native active/sleep regions. Absence counts even below 21 entities. Above 20 moving permanent crystals/eggs in a shard, removes those asleep for 16 continuous minutes. Timer caps at 20 minutes and resets on waking. Excludes static traps and finite-lived stars."),
      options={{description=L("关闭","Off"),data=false,hover=L("不按休眠时长自动清理永久移动实体。","Do not clean up moving permanent entities based on sleep duration.")},{description=L("开启","On"),data=true,hover=L("超过20个时清理连续休眠16分钟的永久移动晶体与载荷卵。","Above 20 moving permanent crystals/eggs, remove those asleep for 16 continuous minutes.")}} },
    { name="sync_performance",label=L("跨世界同步性能配置","Sync performance across worlds"),default=true,
      hover=L("仅同步游戏内可调整的全局性能参数：实体上限、射程、载荷层数和清理开关。个人尾焰、世界难度、掉落率等不参与同步。默认开启，各世界独立设置；关闭后本世界不发送、不应用同步修改。重启恢复模组配置，不回放历史临时值。","Only syncs global performance settings adjustable in-game: entity limits, travel range, payload depth and cleanup switches. Personal trails, world difficulty, drop rates and other settings are excluded. On by default; each world opts in independently. Off: neither sends nor applies shared edits. Restart restores mod configuration without replaying old edits."),
      options={{description=L("关闭","Off"),data=false,hover=L("本世界不发送或应用运行时性能配置同步。","This world neither sends nor applies runtime performance setting updates.")},{description=L("开启","On"),data=true,hover=L("与其他已开启同步的世界共享新的运行时性能修改。","Share new runtime performance edits with other worlds that enable syncing.")}} },
    ModOptions(L("开发者设置","Developer settings"),L("开发者命令与自动自检。","Developer commands and automated checks.")),
    { name="developer_options",label=L("开发者选项","Developer options"),default=false,
      hover=L("开启后，管理员可在向导的全局性能设置页临时调整运行参数，也可在远程控制台输入 nw_help() 使用开发者命令。","Lets admins temporarily adjust runtime performance settings in the field guide, and use nw_help() and developer commands in the remote console."),
      options={{description=L("关闭","Off"),data=false,hover=L("关闭开发者命令及向导内管理员运行参数调节。","Disable developer commands and admin runtime adjustments in the guide.")},{description=L("开启","On"),data=true,hover=L("管理员可使用开发者命令及向导内运行参数调节。","Allow admins to use developer commands and runtime adjustments in the guide.")}} },
    { name = "development_smoke", label = L("开发加载自检","Development load check"), default = false,
      options = { {description = L("关闭","Off"), data = false, hover=L("启动时不运行开发加载自检。","Do not run a development load check at startup.")}, {description = L("开启","On"), data = true, hover=L("启动后运行通用法杖加载与施法自检。","Run the general wand loading and casting check after startup.")}, {description = L("仅边界自检","Boundary check only"), data = "bounds", hover=L("启动后仅运行地图边界清理自检。","Run only the map boundary cleanup check after startup.")}, {description = L("仅休眠清理自检","Sleep cleanup check only"), data = "cleanup", hover=L("启动后仅运行永久移动实体休眠清理自检。","Run only the moving permanent entity sleep cleanup check after startup.")}, {description = L("仅平衡自检","Balance check only"), data = "balance", hover=L("启动后仅运行平衡规则自检。","Run only the balance rules check after startup.")} } },
}
