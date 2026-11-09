local M={}
function M.install(env)
    local T=require("nw/locale").t
    local atlas=require("nw/arcane_storage").atlas
    STRINGS.NAMES.NW_DUSTBOX=T("粉尘收纳盒")
    STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_DUSTBOX=T("盒上的符文将魔力余烬拢在一起，小小一格似乎永远装不满。")
    STRINGS.NAMES.NW_EMBERLAMP=T("奥术余烬灯")
    STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_EMBERLAMP=T("灯芯将晶粉中的余韵引作幽光，静静照亮长夜。")
    for _,icon in ipairs({"nw_dustbox","nw_dustbox_open","nw_dustbox_open_empty",
        "nw_dustbox_open_half","nw_dustbox_open_full","nw_emberlamp","nw_emberlamp_empty",
        "nw_emberlamp_half","nw_emberlamp_full","nw_emberlamp_half_lit","nw_emberlamp_full_lit"}) do
        env.RegisterInventoryItemAtlas(atlas,icon..".tex")
    end
    env.AddMinimapAtlas(atlas)
    local containers=require("containers")
    containers.params.nw_dustbox={
        widget={slotpos={Vector3(0,0,0)},animbank="ui_chest_1x1",animbuild="ui_chest_1x1",
            animbank_upgraded="ui_chest_1x1",animbuild_upgraded="ui_chest_1x1",
            pos=Vector3(0,160,0),side_align_tip=100},
        type="chest",acceptsstacks=true,
        itemtestfn=function(_,item) return item.prefab=="nw_dust" end,
    }
    containers.params.nw_dustbox.priorityfn=containers.params.nw_dustbox.itemtestfn
    containers.params.nw_emberlamp={
        widget={slotpos={Vector3(0,0,0)},animbank="ui_chest_1x1",animbuild="ui_chest_1x1",
            animbank_upgraded="ui_chest_1x1",animbuild_upgraded="ui_chest_1x1",
            pos=Vector3(0,160,0),side_align_tip=100},
        type="chest",acceptsstacks=true,
        itemtestfn=containers.params.nw_dustbox.itemtestfn,
        priorityfn=containers.params.nw_dustbox.itemtestfn,
    }
    containers.MAXITEMSLOTS=math.max(containers.MAXITEMSLOTS,1)
end
return M
