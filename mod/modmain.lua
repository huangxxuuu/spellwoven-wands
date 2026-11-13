local T=GLOBAL.require("nw/locale").t
GLOBAL.require("nw/locale").install(env,GLOBAL)
GLOBAL.require("nw/balance").install(env,GLOBAL)
GLOBAL.require("nw/trail_budget").install(env,GLOBAL)
GLOBAL.require("nw/limit_feedback").install(env,GLOBAL)
GLOBAL.require("nw/dummy_trials").install(env)
PrefabFiles = { "nw_wand", "nw_wand_visual", "nw_projectile", "nw_elemental_hit_fx", "nw_tool_land_fx", "nw_field_stage_fx", "nw_target_dummy", "nw_spell_punchingbag", "nw_spellcard", "nw_spellpile", "nw_workbench", "nw_disassembler", "nw_materials", "nw_dustbox", "nw_emberlamp", "nw_spell_fx", "nw_garden", "nw_expansion_fx", "nw_staff_stars", "nw_gunpowder", "nw_dark_fog" }
Assets={Asset("ATLAS","images/nw_guide.xml"),Asset("IMAGE","images/nw_guide.tex"),Asset("ATLAS","images/inventoryimages/nw_stations.xml"),Asset("IMAGE","images/inventoryimages/nw_stations.tex"),
    Asset("SOUNDPACKAGE","sound/nw_instruments.fev"),Asset("SOUND","sound/nw_instruments.fsb"),
    Asset("ATLAS","images/nw_hud.xml"),Asset("IMAGE","images/nw_hud.tex"),
    Asset("ATLAS","images/nw_frame.xml"),Asset("IMAGE","images/nw_frame.tex")}
local limits=GLOBAL.require("nw/spell_limits")
for _,key in GLOBAL.ipairs({"range","depth"}) do
    limits[key]=GetModConfigData("limit_"..key) or 0
end
if limits.range==30 then limits.range=60 end
limits.boundary_cleanup=GetModConfigData("boundary_cleanup") == true
limits.permanent_motion_cleanup=GetModConfigData("permanent_motion_cleanup") == true
GLOBAL.require("nw/executor").set_projectile_limit(GetModConfigData("limit_projectiles"))
GLOBAL.require("nw/entity_limits").configure("fields",GetModConfigData("limit_fields"))
GLOBAL.require("nw/entity_limits").configure("permanent_fields",GetModConfigData("limit_permanent_fields"))
GLOBAL.require("nw/performance_settings").install(env,GLOBAL)
RegisterInventoryItemAtlas("images/inventoryimages/nw_icons.xml", "nw_wand.tex")
local Visual=GLOBAL.require("nw/visual")
for code=0,Visual.count-1 do
    RegisterInventoryItemAtlas(Visual.atlas(code),Visual.icon(code)..".tex")
    RegisterInventoryItemAtlas(Visual.atlas(code),Visual.icon(code,true)..".tex")
end
for _,id in GLOBAL.ipairs(GLOBAL.require("nw/cards").order) do
    RegisterInventoryItemAtlas("images/inventoryimages/nw_icons.xml", "nw_spell_"..id..".tex")
end
for _,card in GLOBAL.ipairs(GLOBAL.require("nw/expansion")) do
    GLOBAL.STRINGS.NAMES["NW_"..GLOBAL.string.upper(card.id)]=card.name
end
GLOBAL.STRINGS.NAMES.NW_SPORE_SENTRY=T("荚刺哨株")
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_SPORE_SENTRY=T("短暂生长的哨株，会被怪物击倒。")
GLOBAL.STRINGS.NAMES.NW_SPORE_BALL_FLIGHT=T("蘑菇孢球")
GLOBAL.STRINGS.NAMES.NW_EDGE_YELLOWSTAFF=T("矮星")
GLOBAL.STRINGS.NAMES.NW_EDGE_OPALSTAFF=T("极光")
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_EDGE_YELLOWSTAFF=T("法术唤出的矮星，带来光亮与温暖。")
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_EDGE_OPALSTAFF=T("法术唤出的极光，散发清冷的光芒。")
GLOBAL.STRINGS.NAMES.NW_WAND = T("织法之杖")
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_WAND = T("等待注入法术的实验法杖。")
AddReplicableComponent("nw_wand")
AddComponentPostInit("inventory",GLOBAL.require("nw/orbit_shield").install_inventory)
AddComponentPostInit("combat",GLOBAL.require("nw/orbit_shield").install_combat)
GLOBAL.require("nw/dark_fog").install(env)
AddComponentPostInit("temperature",GLOBAL.require("nw/giant_stars").temperature)
AddComponentPostInit("inventoryitemtemperature",GLOBAL.require("nw/giant_stars").item_temperature)
AddComponentPostInit("sanity",GLOBAL.require("nw/giant_stars").sanity)
GLOBAL.STRINGS.NAMES.NW_TARGET_DUMMY=T("法杖测试靶")
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_TARGET_DUMMY=T("1000 生命的测试靶，不会反击。")
GLOBAL.STRINGS.NAMES.NW_SPELLCARD=T("法术卡")
GLOBAL.STRINGS.NAMES.NW_WORKBENCH=T("奥术台")
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_SPELLCARD=T("靠近奥术台，点击法杖面板安装。")
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_WORKBENCH=T("靠近它制作法杖、刻写和更换法术卡。")
AddMinimapAtlas("images/inventoryimages/nw_stations.xml")
GLOBAL.STRINGS.NAMES.NW_ENGRAVER=T("武器刻印台")
GLOBAL.STRINGS.RECIPE_DESC.NW_ENGRAVER=T("刻写武器与工具的法术卡。")
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_ENGRAVER=T("放入两件同种武器，用晶笔刻写它们的力量。")
GLOBAL.STRINGS.NAMES.NW_DISASSEMBLER=T("奥术分解炉")
GLOBAL.STRINGS.RECIPE_DESC.NW_DISASSEMBLER=T("将附近地上的法术卡和法杖分解为粉尘。")
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_DISASSEMBLER=T("持续操作时分解四单位内的物品。随时走开即可停止。")
GLOBAL.require("nw/dustbox").install(env)
GLOBAL.require("nw/crafting").install(env)
GLOBAL.require("nw/rewards").install(env)
GLOBAL.require("nw/first_boss_reward").install(env)
GLOBAL.require("nw/spelljournal").install(env)
GLOBAL.require("nw/journal_damage").install(env)
GLOBAL.require("nw/balance_damage").install(env)
GLOBAL.STRINGS.NAMES.NW_SPELLPILE=T("法术牌堆")
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_SPELLPILE=T("打开可以逐张取出法术卡。")
GLOBAL.require("nw/cardpile").install(env)
GLOBAL.require("nw/wand_container").install(env)
GLOBAL.require("nw/wand_naming").install(env)
GLOBAL.require("nw/recycle").install(env)
GLOBAL.require("nw/guard_ring").install(env)
GLOBAL.require("nw/wand_damage").install(env)
if GetModConfigData("developer_options") == true then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then
            GLOBAL.require("nw/dev_commands").install(GLOBAL, GLOBAL.TheWorld)
        end
    end)
end
local CastAction=GLOBAL.require("nw/cast_action")
GLOBAL.require("nw/cast_direction").install(env,GLOBAL)
local cast=GLOBAL.Action({priority=10,rmb=true,distance=GLOBAL.math.huge,
    mount_valid=true,invalid_hold_action=true,silent_fail=true})
cast.id="NW_CAST";cast.str=T("施法")
cast.fn=CastAction.perform;cast.pre_action_cb=CastAction.prepare;cast.validfn=CastAction.valid
AddAction(cast)
AddComponentAction("POINT","nw_wand",CastAction.point)
AddComponentAction("EQUIPPED","nw_wand",CastAction.equipped)
AddStategraphActionHandler("wilson",GLOBAL.ActionHandler(cast,CastAction.server_state))
AddStategraphActionHandler("wilson_client",GLOBAL.ActionHandler(cast,CastAction.client_state))
AddStategraphPostInit("wilson",GLOBAL.require("nw/cast_timing").install)
AddStategraphPostInit("wilson_client",GLOBAL.require("nw/cast_timing").install)
AddStategraphPostInit("tornado",GLOBAL.require("nw/giant_native").install_tornado)
AddModRPCHandler("nw_weave","focus",function(player,editing)
    local id,near=GLOBAL.require("nw/edit_protocol").focus(player,editing)
    if player.userid then GLOBAL.SendModRPCToClient(GLOBAL.CLIENT_MOD_RPC.nw_weave.edit_status,player.userid,id,near) end
end)
AddModRPCHandler("nw_weave","edit",GLOBAL.require("nw/edit_protocol").handle)
AddClientModRPCHandler("nw_weave","edit_result",GLOBAL.require("nw/editor_client").result)
AddClientModRPCHandler("nw_weave","edit_status",GLOBAL.require("nw/editor_client").status)
AddClientModRPCHandler("nw_weave","dev_help",GLOBAL.require("nw/dev_output").print_lines)
if not GLOBAL.TheNet:IsDedicated() then
    AddClassPostConstruct("widgets/redux/craftingmenu_pinbar",GLOBAL.require("nw/station_sounds").install)
    AddClassPostConstruct("widgets/image",GLOBAL.require("nw/card_icon").install)
    GLOBAL.require("nw/crafting_filter").install(env,GLOBAL)
    AddComponentPostInit("playercontroller",GLOBAL.require("nw/hold_cast").install)
    AddClassPostConstruct("widgets/itemtile",GLOBAL.require("nw/client").tile)
    AddClassPostConstruct("widgets/controls",function(self)
        self.nw_wandpanel=self.inv.root:AddChild(GLOBAL.require("widgets/nw_wandpanel")(self.inv))
    end)
end
if GetModConfigData("development_smoke")=="loot_only" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_loot_only").run) end
    end)
elseif GetModConfigData("development_smoke")=="balance" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_balance").run) end
    end)
elseif GetModConfigData("development_smoke")=="dark_fog" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_dark_fog").run) end
    end)
elseif GetModConfigData("development_smoke")=="dustbox" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_dustbox").run) end
    end)
elseif GetModConfigData("development_smoke")=="crafting" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_crafting_filter").run) end
    end)
elseif GetModConfigData("development_smoke")=="journal" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_spelljournal").run) end
    end)
elseif GetModConfigData("development_smoke")=="wands" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_wand_generation").run) end
    end)
elseif GetModConfigData("development_smoke")=="revision" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_revision").run) end
    end)
elseif GetModConfigData("development_smoke")=="bag_bonus" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_bag_bonus").run) end
    end)
elseif GetModConfigData("development_smoke")=="scenes" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then
            GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_test_scenes").run)
        end
    end)
elseif GetModConfigData("development_smoke")=="cleanup" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then
            GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_motion_cleanup").run)
        end
    end)
elseif GetModConfigData("development_smoke")=="bounds" then
    AddSimPostInit(function()
        if GLOBAL.TheWorld.ismastersim then
            GLOBAL.TheWorld:DoTaskInTime(2,GLOBAL.require("nw/smoke_world_bounds").run)
        end
    end)
elseif GetModConfigData("development_smoke") then
    AddSimPostInit(function()
        if not GLOBAL.TheWorld.ismastersim then return end
        GLOBAL.TheWorld:DoTaskInTime(2, function()
            local wand = GLOBAL.SpawnPrefab("nw_wand")
            GLOBAL.assert(wand and wand.components.nw_wand, "NW_SMOKE: prefab failed")
            wand.components.nw_wand:InitializePrototype()
            local plan, err = wand.components.nw_wand:PreviewCast()
            GLOBAL.assert(plan and plan.projectile_count == 1, err or "NW_SMOKE: compiler failed")
            GLOBAL.assert(wand.components.inventoryitem.imagename==Visual.icon(wand._nw_look:value()),"NW_SMOKE: wand inventory art")
            local saved = wand.components.nw_wand:OnSave()
            GLOBAL.assert(saved.wand.stats.capacity == 4, "NW_SMOKE: save failed")
            for style=1,Visual.styles do
                saved.wand.appearance=Visual.appearance(saved.wand.stats,18*(style-1)+16)
                local restored=GLOBAL.SpawnPrefab("nw_wand")
                restored.components.nw_wand:OnLoad(saved)
                local look=restored._nw_look:value()
                local inv=restored.components.inventoryitem
                GLOBAL.assert(look==Visual.from_data(saved.wand) and inv.atlasname==Visual.atlas(look)
                    and inv.imagename==Visual.icon(look), "NW_SHAFT: restored look/icon mismatch")
                local _,_,_,body=Visual.parts(look)
                GLOBAL.assert(body==saved.wand.appearance.body_id,"NW_SHAFT: restore lost the approved body")
                restored:Remove()
            end
            GLOBAL.print("NW_SHAFT_PASS: all nine saved styles restore their network look and inventory page")
            for code = 0, Visual.count-1 do
                GLOBAL.require("nw/visual").apply(wand, code, "ground")
            end
            for i,length in GLOBAL.ipairs(Visual.lengths) do
                local code=(i-1)*#Visual.tails*#Visual.colors
                Visual.apply_dropped(wand,code,false)
                local hx,hy,_,head=wand.AnimState:GetSymbolPosition("head",0,0,0)
                local tx,ty,_,tail=wand.AnimState:GetSymbolPosition("tail",0,0,0)
                local gx,gy,_,grass=wand.AnimState:GetSymbolPosition("contact_grass",0,0,0)
                -- These are world coordinates; camera-right is not world +X.
                GLOBAL.assert(head and tail and grass and GLOBAL.math.abs(hx-tx)>.1 and hy>ty and ty>gy,
                    "NW_GROUND: missing contact or incorrect lean for "..length)
                Visual.apply_dropped(wand,code,true)
                GLOBAL.assert(wand.AnimState:IsCurrentAnimation("floating_"..length),"NW_GROUND: water pose")
                GLOBAL.print("NW_GROUND_PASS:",length,hx-tx,hy-ty,gx,gy)
            end
            local visual = GLOBAL.SpawnPrefab("nw_wand_visual")
            GLOBAL.assert(visual, "NW_SMOKE: visual proxy failed")
            visual._look:set(Visual.count-1)
            GLOBAL.assert(visual._look:value() == Visual.count-1, "NW_SMOKE: look network range")
            wand._nw_capacity:set(12)
            GLOBAL.assert(wand._nw_capacity:value() == 12, "NW_SMOKE: capacity network range")
            visual:Remove()
            wand:Remove()
            for _,id in GLOBAL.ipairs(GLOBAL.require("nw/cards").order) do
                local card=GLOBAL.SpawnPrefab("nw_spellcard")
                card:SetSpell(id)
                GLOBAL.assert(card.components.inventoryitem.imagename=="nw_spell_"..id,"NW_ART: icon mismatch")
                GLOBAL.assert(card.components.inspectable.description==GLOBAL.require("nw/cards").names[id],"NW_ART: inspection must say only the name")
                local savedcard={};card:OnSave(savedcard)
                local copy=GLOBAL.SpawnPrefab("nw_spellcard");copy:OnLoad(savedcard)
                GLOBAL.assert(copy.spell_id==id,"NW_ART: spell card restore")
                copy:Remove();card:Remove()
            end
            GLOBAL.print("NW_ART_PASS: all card IDs, icons, descriptions and save/restore")
            -- Query the actual engine's player animation, including on a headless host.
            local probe=GLOBAL.CreateEntity()
            probe.entity:AddTransform();probe.entity:AddAnimState()
            probe.AnimState:SetBank("wilson");probe.AnimState:SetBuild("wilson")
            probe.AnimState:OverrideSymbol("swap_object","nw_parts","anchor")
            for _,anim in GLOBAL.ipairs({"atk_pre","atk"}) do
                probe.AnimState:PlayAnimation(anim);probe.AnimState:SetFrame(4)
                for _,capacity in GLOBAL.ipairs({4,8,12}) do
                    local x,y,z,source=GLOBAL.require("nw/muzzle").origin(probe,capacity,1,0)
                    GLOBAL.assert(source=="symbol" and y>.2,"NW_MUZZLE: player staff tip lookup")
                    GLOBAL.print("NW_MUZZLE_PASS:",anim,capacity,x,y,z,source)
                end
            end
            -- Exercise the same follower path as an equipped wand. Measure the
            -- head-to-tail anchor span from the engine, after loading anim.bin.
            local child=GLOBAL.CreateEntity()
            child.entity:AddTransform();child.entity:AddAnimState();child.entity:AddFollower()
            child.entity:SetParent(probe.entity)
            child.Follower:FollowSymbol(probe.GUID,"swap_object",0,0,0,true)
            local function span(entity,code,pose)
                Visual.apply(entity,code,pose)
                local x,y,z,head=entity.AnimState:GetSymbolPosition("head",0,0,0)
                local tx,ty,tz,tail=entity.AnimState:GetSymbolPosition("tail",0,0,0)
                GLOBAL.assert(head and tail,"NW_HELD: missing attachment")
                return GLOBAL.math.sqrt((x-tx)^2+(y-ty)^2+(z-tz)^2)
            end
            local dropped=GLOBAL.SpawnPrefab("nw_wand")
            for i,length in GLOBAL.ipairs(Visual.lengths) do
                local code=(i-1)*#Visual.tails*#Visual.colors
                local ground=span(dropped,code,"ground")
                local held=span(child,code,"held")
                GLOBAL.assert(ground>0 and GLOBAL.math.abs(held/ground-Visual.held_multiplier)<.05,
                    "NW_HELD: equipped/planted span mismatch for "..length.." ("..held..", "..ground..")")
                GLOBAL.print("NW_HELD_PASS:",length,"ground",ground,"held",held)
            end
            dropped:Remove()
            child:Remove()
            probe:Remove()
            GLOBAL.require("nw/smoke_combat").run(function(x,z)
                GLOBAL.require("nw/smoke_cardpile").run(x,z,function()
                    GLOBAL.require("nw/smoke_acquisition").run(x,z,GetModConfigData("starting_wand") ~= false)
                    GLOBAL.require("nw/smoke_firestaff").run(x,z,function()
                        GLOBAL.require("nw/smoke_input").run(x,z,function()
                            GLOBAL.require("nw/smoke_perf").run(x,z,function()
                                GLOBAL.require("nw/smoke_spell_lab").run(x,z,function()
                                    GLOBAL.print("NW_SMOKE_PASS: spell lab + save + combat + native input + perf + card piles")
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end
