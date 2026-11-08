local chinese = (locale and locale:lower():match("^zh") ~= nil) or locale == "chs" or locale == "cht"
local function L(zh,en) return chinese and zh or en end
name = L("织法之杖","Spellwoven Wands")
version = "1.0.2"
local release_date = "2026-11-08"
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
icon_atlas = "modicon.xml"
icon = "modicon.tex"
-- Keep normal load order; this mod does not require Smart Chest's priority override.
priority = 0

local payload_depth_options={{description=L("关闭（不限层数）","Off (unlimited depth)"),data=0}}
for depth=1,30 do
    payload_depth_options[#payload_depth_options+1]={description=depth..L(" 层"," layers"),data=depth}
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
    -- modinfo runs without standard globals such as ipairs and tostring.
    local multipliers={.5,1,2,3,5,10}
    for i=1,#multipliers do
        local multiplier=multipliers[i]
        options[#options+1]={description=multiplier..L(" 倍","x"),data=multiplier}
    end
    return options
end

configuration_options = {
    {name="language",label="语言 / Language",default="auto",
      hover=L("仅影响本机显示；自动跟随游戏语言，中文环境使用中文，其余使用英文。更改后重新进入世界。", "Local display only. Auto uses Chinese for Chinese game locales, English otherwise. Rejoin the world after changing."),
      options={{description="自动 / Auto",data="auto"},{description="中文",data="zh"},{description="English",data="en"}}},
    { name="starting_wand",label=L("给予出门法杖","Starting wand"),default=true,
      hover=L("玩家首次进入这个世界时，获得一把已装有火花弹的两槽入门法杖。","Gives each player a two-slot Starter Wand with a Spark Bolt when they first enter this world."),
      options={{description=L("开启","On"),data=true},{description=L("关闭","Off"),data=false}} },
    { name="crafting_class_filter",label=L("制作栏分类与标签筛选","Crafting class and tag filters"),default=true,
      hover=L("仅影响本机：在奥术台和武器刻印台按分类和标签筛选，多选标签须同时满足。关闭制作栏后重置。与其他制作栏 Mod 冲突时可关闭；更改后重新进入世界。保留原版搜索。","Local display only: filter station recipes by class and tags; all selected tags must match. Resets when the drawer closes. Disable if another crafting-menu mod conflicts; rejoin after changing. Keeps native search."),
      options={{description=L("开启","On"),data=true},{description=L("关闭","Off"),data=false}} },
    ModOptions(L("掉落率","Drop rates"),L("调整成品法术卡与法杖的掉落概率。","Adjust drop chances for spell cards and wands.")),
    { name="card_drop_rate",label=L("生物成品法术卡掉率","Creature spell card drop rate"),default=1,
      hover=L("原有掉落概率乘以所选倍率，最高为 100%；不增加单次掉落数量。", "Multiplies the original drop chance, capped at 100%; does not increase the number of drops per reward."),
      options=DropRateOptions() },
    { name="wand_drop_rate",label=L("常规首领成品法杖掉率","Regular boss wand drop rate"),default=1,
      hover=L("原有掉落概率乘以所选倍率，最高为 100%；不增加单次掉落数量。", "Multiplies the original drop chance, capped at 100%; does not increase the number of drops per reward."),
      options=DropRateOptions() },
    ModOptions(L("性能优化","Performance"),L("可选的数量上限与清理机制，默认全部关闭。","Optional limits and cleanup mechanisms; all disabled by default.")),
    { name="limit_projectiles",label=L("玩家子弹数量上限","Projectile budget"),default=false,
      hover=L("开启后，同时活动或预留的攻击实体最多每位玩家 24 个、每个世界分片 160 个。","Limits active or reserved attack entities to 24 per player and 160 per shard."),
      options={{description=L("关闭","Off"),data=false},{description=L("开启","On"),data=true}} },
    { name="limit_cast",label=L("单次施法攻击实体上限","Attack entities per cast"),default=0,
      options={{description=L("不限","Unlimited"),data=0},{description="12",data=12},{description="24",data=24},{description="60",data=60},{description="120",data=120}} },
    { name="crystal_limit",label=L("每位玩家的晶体数量上限","Crystals per player"),default=0,
      hover=L("近感晶雷与休眠晶体合计，达到上限后新晶体替换最早的一枚。","Combined cap for Proximity Crystal Mines and Dormant Crystals. New crystals replace the oldest when full."),
      options={{description=L("不限","Unlimited"),data=0},{description=L("30 枚","30"),data=30},{description=L("60 枚","60"),data=60},{description=L("120 枚","120"),data=120}} },
    { name="limit_sentries",label=L("每位玩家的荚刺哨株上限","Pod Sentries per player"),default=0,
      options={{description=L("不限","Unlimited"),data=0},{description="2",data=2},{description="8",data=8},{description="30",data=30},{description="60",data=60}} },
    { name="limit_storms",label=L("每位玩家的雷云上限","Stormclouds per player"),default=0,
      options={{description=L("不限","Unlimited"),data=0},{description="2",data=2},{description="8",data=8},{description="30",data=30},{description="60",data=60}} },
    { name="limit_world_storms",label=L("每个分片的雷云上限","Stormclouds per shard"),default=0,
      options={{description=L("不限","Unlimited"),data=0},{description="12",data=12},{description="30",data=30},{description="60",data=60},{description="120",data=120}} },
    { name="limit_lights",label=L("每位玩家的残光上限","Lingering lights per player"),default=0,
      options={{description=L("不限","Unlimited"),data=0},{description="4",data=4},{description="12",data=12},{description="30",data=30},{description="60",data=60}} },
    { name="limit_range",label=L("子弹累计射程限制","Projectile travel limit"),default=0,
      hover=L("默认关闭，飞行距离由弹速和寿命决定。开启后限制每枚飞行子弹的累计路程，载荷子弹单独计算；不限制永久场与星体。","Off by default: speed and lifetime determine travel. When enabled, caps each projectile's total path length; payload projectiles count separately. Does not limit permanent fields or stars."),
      options={{description=L("关闭","Off"),data=0},{description=L("30 单位","30 units"),data=30},{description=L("60 单位","60 units"),data=60},{description=L("120 单位","120 units"),data=120}} },
    { name="limit_depth",label=L("载荷嵌套层数限制","Payload nesting limit"),default=0,
      hover=L("默认关闭。开启后可选 1～30 层；根法术不计层数，每次载荷嵌套计一层。","Off by default. Choose 1–30 levels. The root spell does not count; each nested payload adds one level."),
      options=payload_depth_options },
    { name="boundary_cleanup",label=L("越界法术实体清理","Out-of-bounds cleanup"),default=false,
      hover=L("仅清理本 Mod 法术实体：无天然边界墙时，离开有效陆地或海洋边界 5 单位后移除；有天然边界墙时到达即移除。清理不释放载荷或终结效果。","Only affects this mod's spells. Removes them 5 units beyond valid land/ocean, or on reaching a natural boundary wall. Cleanup does not release payloads or final effects."),
      options={{description=L("开启","On"),data=true},{description=L("关闭","Off"),data=false}} },
    { name="permanent_motion_cleanup",label=L("永久移动实体自动清理","Permanent motion cleanup"),default=false,
      hover=L("按原版活跃／休眠区域独立计时，不足 21 个也累计。分片永久移动晶体与载荷卵超过 20 个时，清理连续 16 分钟处于休眠区域的实体。累计最多 20 分钟，回到活跃区域重置；静止机关与有寿命的星体不计入。","Uses native active/sleep regions. Absence counts even below 21 entities. Above 20 moving permanent crystals/eggs in a shard, removes those asleep for 16 continuous minutes. Timer caps at 20 minutes and resets on waking. Excludes static traps and finite-lived stars."),
      options={{description=L("关闭","Off"),data=false},{description=L("开启","On"),data=true}} },
    ModOptions(L("开发者设置","Developer settings"),L("开发者命令与自动自检。","Developer commands and automated checks.")),
    { name="developer_options",label=L("开发者选项","Developer options"),default=false,
      hover=L("开启后，房主或管理员可在远程控制台输入 nw_help() 查看并使用开发者命令。","Lets hosts and admins use nw_help() and developer commands in the remote console."),
      options={{description=L("关闭","Off"),data=false},{description=L("开启","On"),data=true}} },
    { name = "development_smoke", label = L("开发加载自检","Development load check"), default = false,
      options = { {description = L("关闭","Off"), data = false}, {description = L("开启","On"), data = true}, {description = L("仅边界自检","Boundary check only"), data = "bounds"}, {description = L("仅休眠清理自检","Sleep cleanup check only"), data = "cleanup"} } },
}
