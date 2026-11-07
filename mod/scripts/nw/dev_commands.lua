local Kit = require("nw/spellkit")
local Cast = require("nw/cast_action")
local report = require("nw/dev_output").report
local M = {}
local commands

local function help()
    local lines = {"织法之杖 · 开发者命令（房主或管理员远程控制台）"}
    for _, cmd in ipairs(commands) do
        lines[#lines+1] = cmd.name.."("..cmd.args..")  "..cmd.description
    end
    local listing = table.concat(lines, "\n")
    report(listing)
    return listing
end

local function editkit(player)
    player = player or ConsoleCommandPlayer()
    if not player or not player.components.inventory then return end
    local ids = require("nw/cards").order
    for i=1,math.min(10,#ids) do
        local card = SpawnPrefab("nw_spellcard")
        card:SetSpell(ids[i])
        player.components.inventory:GiveItem(card)
    end
    local x,_,z = player.Transform:GetWorldPosition()
    SpawnPrefab("nw_workbench").Transform:SetPosition(x-2,0,z)
    print("NW_EDITKIT: ten cards and one workbench created")
end

local function testkit(player)
    player = player or ConsoleCommandPlayer()
    if not player or not player.components.inventory then return end
    for _,mode in ipairs({"spark","double","wrap","fast"}) do
        local wand = SpawnPrefab("nw_wand")
        wand.components.nw_wand:SetTestLoadout(mode)
        wand.components.named:SetName("测试法杖 · "..mode)
        player.components.inventory:GiveItem(wand)
    end
    local x,_,z = player.Transform:GetWorldPosition()
    SpawnPrefab("nw_target_dummy").Transform:SetPosition(x+5,0,z)
    print("NW_TESTKIT: four wands and one target created")
end

local function manaprobe(player)
    local wand = Cast.hand(player or ConsoleCommandPlayer())
    if not wand then return end
    local cmp = wand.components.nw_wand
    cmp:UpdateTime()
    cmp.data.runtime.mana = 0
    cmp:Sync()
    print("NW_MANA_PROBE: equipped wand mana set to zero; stats, cards and cooldown unchanged")
end

local function saveprobe(player)
    local wand = Cast.hand(player or ConsoleCommandPlayer())
    if not wand then return end
    local cmp = wand.components.nw_wand
    cmp:UpdateTime()
    cmp.data.runtime.remaining_recharge = 30
    cmp.cool_total = 30
    cmp:Sync()
    print("NW_SAVE_PROBE: 30 second diagnostic cooldown; slots and wand stats unchanged")
end

commands = {
    {name="nw_help", args="", description="列出当前所有开发者命令和用法。", run=help},
    {name="nw_journal",args='["法术ID"]',description='查看个人法术收集与伤害统计；提供 ID 时查看单卡。',run=require("nw/spelljournal").report},
    {name="nw_dropkit",args="",description="将所有当前不能制作的可用法术卡放入箱子。",run=Kit.dropkit},
    {name="nw_spellkit", args="", description="放置全套分类法术卡箱、奥术台，并领取一把 12 格空杖。", run=Kit.all},
    {name="nw_testscene",args='["场景ID"]',description='列出测试场景；"all" 生成全部箱牌，"duo" 生成双人 A/B 分箱套装。',run=require("nw/test_scene_kit").spawn},
    {name="nw_testcleanup",args="[数量]",description="生成休眠清理测试用追踪卵，默认 20 个；另处再生成 1 个测试数量门槛。",run=require("nw/test_scene_kit").cleanup},
    {name="nw_card", args='"法术ID"', description='领取一张指定法术卡，例如 nw_card("spark")。', run=Kit.give},
    {name="nw_combo", args="...", description='领取预设组合杖，或按顺序装入最多 12 张卡。无参数给空杖，例如 nw_combo("burst") 或 nw_combo("arrow_hit","chain")。', run=Kit.wand},
    {name="nw_rollwand", args="稀有度[, 种子]", description="领取装满火花弹的随机杖；稀有度 1～4，例如 nw_rollwand(4,1062)。", run=Kit.rollwand},
    {name="nw_range", args="", description="在前方布置一排测试靶、侧靶和半血友方治疗靶。", run=Kit.range},
    {name="nw_lookkit", args='[颜色[, 杖身编号]]', description='领取六把外观试杖、三张卡和奥术台。颜色选 red/blue/green，杖身选 1～9，例如 nw_lookkit("blue",5)。', run=Kit.lookkit},
    {name="nw_hudkit", args="", description="领取 2、7、12 格 HUD 试杖、火焰弹卡和奥术台。", run=Kit.hudkit},
    {name="nw_editkit", args="", description="领取前十种法术卡并放置奥术台，用于测试编辑。", run=editkit},
    {name="nw_testkit", args="", description="领取基础、双重、回绕、加速四把试杖，并放置一个测试靶。", run=testkit},
    {name="nw_manaprobe", args="", description="清空手持法杖的法力，用于观察回蓝和缺蓝状态。", run=manaprobe},
    {name="nw_saveprobe", args="", description="将手持法杖的剩余充能设为 30 秒，用于测试冷却显示与存档。", run=saveprobe},
}

function M.install(globals, world)
    -- DST's strict global table rejects new names assigned inside a callback.
    for _, cmd in ipairs(commands) do rawset(globals, cmd.name, cmd.run) end
    world:ListenForEvent("onremove", function()
        for _, cmd in ipairs(commands) do
            if rawget(globals, cmd.name) == cmd.run then rawset(globals, cmd.name, nil) end
        end
    end)
end

return M
