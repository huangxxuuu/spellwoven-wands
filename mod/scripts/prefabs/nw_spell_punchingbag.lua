require("prefabutil")
local Bag=require("nw/punchingbag")
local assets={Asset("ANIM","anim/punchingbag.zip"),Asset("ANIM","anim/nw_objects.zip")}
local function fn()
    local inst=Prefabs.punchingbag.fn()
    inst:AddTag("nw_test_target")
    inst._nw_combo_text=net_string(inst.GUID,"nw_bag.combo","nw_combo_dirty")
    inst._nw_trial_text=net_string(inst.GUID,"nw_bag.trial","nw_trial_dirty")
    inst._nw_trial_mode=net_tinybyte(inst.GUID,"nw_bag.mode","nw_trial_dirty")
    if not TheNet:IsDedicated() then Bag.visual(inst) end
    if TheWorld.ismastersim then Bag.setup(inst) end
    return inst
end
return Prefab("nw_spell_punchingbag",fn,assets,{"punchingbag"}),
    MakePlacer("nw_spell_punchingbag_placer","punchingbag","punchingbag","placer")
