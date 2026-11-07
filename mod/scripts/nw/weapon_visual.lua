-- Native hand builds with nonstandard filenames or swap symbols.
local overrides={
    brush={'swap_beefalobrush'},
    bullkelp_root={'swap_bullkelproot','swap_whip'},
    carnivalgame_golfclub={'carnivalgame_golfclub','swap_golfclub'},
    chum={'swap_chum_pouch'},
    cutless={'cutless','swap_cutless'},
    dumbbell_heat={'swap_dumbbell_heat3','swap_dumbbell_heat'},
    farm_hoe={'quagmire_hoe','swap_quagmire_hoe'},
    fence_rotator={'fence_rotator','swap_fence_rotator'},
    fumarole_farm_hoe={'fumarolehoe','swap_fumarolehoe_1'},
    fumaroleaxe={'fumaroleaxe','swap_fumaroleaxe_1'},
    fumarolehammer={'fumarolehammer','swap_fumarolehammer_1'},
    fumarolepickaxe={'fumarolepickaxe','swap_fumarolepickaxe_1'},
    fumaroleshovel={'fumaroleshovel','swap_fumaroleshovel_1'},
    gestalt_cage={'gestalt_cage','swap_object'},
    golden_farm_hoe={'swap_goldenhoe'},
    hambat={'swap_ham_bat'},
    handpillow_beefalowool={'swap_pillows_beefalowool','swap_object'},
    handpillow_kelp={'swap_pillows_kelp','swap_object'},
    handpillow_petals={'swap_pillows_petals','swap_object'},
    handpillow_steelwool={'swap_pillows_steelwool','swap_object'},
    houndstooth_blowpipe={'swap_houndstooth_blowpipe','swap_blowdart_pipe'},
    king_cane={'king_cane'},
    lucy={'swap_lucy_axe'},
    merm_tool={'mermtool','swap_mermtool'},
    merm_tool_upgraded={'mermtool_upgraded','swap_mermtool_upgraded'},
    moonglassaxe={'swap_glassaxe'},
    nightsword={'swap_nightmaresword'},
    oceanfishingrod={'swap_fishingrod_ocean'},
    orangestaff={'swap_staffs','swap_orangestaff'},
    pickaxe_lunarplant={'pickaxe_lunarplant','swap_pickaxe_lunarplant'},
    pocketwatch_weapon={'pocketwatch_weapon','swap_object'},
    propsign={'swap_sign_elite'},
    queen_torch={'queen_torch','swap_queen_torch'},
    shadow_battleaxe={'nightmare_axe'},
    shieldofterror={'swap_eye_shield','swap_shield'},
    shovel_lunarplant={'shovel_lunarplant','swap_shovel_lunarplant'},
    spear_wathgrithr_lightning={'spear_wathgrithr_lightning','swap_spear_wathgrithr_lightning'},
    spear_wathgrithr_lightning_charged={'spear_wathgrithr_lightning','swap_spear_wathgrithr_lightning'},
    sword_lunarplant={'sword_lunarplant'},
    tentaclespike={'swap_spike'},
    thulecitebugnet={'thulecitebugnet','swap_object'},
    vault_compass={'vault_compass','swap_compass'},
    voidcloth_scythe={'scythe_voidcloth'},
    wathgrithr_shield={'swap_wathgrithr_shield','swap_shield'},
    witchbroom={'witchbroom','swap_witchbroom'},
    wortox_nabbag={'swap_wortox_nabbag','swap_wortox_nabbag_empty'},
    yoth_knightstick={'yoth_knightstick','swap_knightstick'},
    yoth_lance={'yoth_lance','swap_lance'},
}

-- These four native items draw their hand art with animated followers.
-- Frame intervals match the equip FX for the swap_object facing frames.
local layers={
    king_cane={{"swap_loop1"}},
    sword_lunarplant={{"swap_loop1",0,3},{"swap_loop2",5,8}},
    shadow_battleaxe={{"swap_level1_f1",0,2},{"swap_level1_f3",2},{"swap_level1_f4",3},
        {"swap_level1_f6",5},{"swap_level1_f7",6},{"swap_level1_f8",7}},
    voidcloth_scythe={{"swap_loop_1",0,2},{"swap_loop_3",2},{"swap_loop_6",5},
        {"swap_loop_7",6},{"swap_loop_8",7}},
}
local function weapon_fx(id,source,pose,duration)
    local override=overrides[source]
    local build=override and override[1] or "swap_"..source
    local symbol=override and override[2] or build
    local animation=pose=="thrust" and "spearjab" or pose=="whip" and "whip" or pose=="pocketwatch_atk" and "pocketwatch_atk" or pose=="atk_prop" and "atk_prop" or "atk"
    local assets={Asset("ANIM","anim/player_attacks.zip"),Asset("ANIM","anim/nw_objects.zip"),Asset("ANIM","anim/nw_spell_world.zip"),
        Asset("ANIM","anim/"..build..".zip")}
    return Prefab("nw_"..id.."_fx",function()
        local inst=CreateEntity()
        inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddNetwork()
        if pose=="whirl" then
            inst.AnimState:SetBank("nw_spell_world");inst.AnimState:SetBuild("nw_spell_world")
            inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
            inst.AnimState:PlayAnimation("axe_whirl")
            inst:AddTag("FX");inst:AddTag("NOCLICK");inst.entity:SetPristine()
            inst.persists=false
            return inst
        end
        inst.Transform:SetFourFaced()
        -- The native attack bank supplies the hand transform and selects the
        -- right swap frame for the camera. This build has no character art.
        inst.AnimState:SetBuild("nw_objects")
        inst.AnimState:SetBankAndPlayAnimation("wilson",animation)
        inst.AnimState:SetDeltaTimeMultiplier(inst.AnimState:GetCurrentAnimationLength()/duration)
        if layers[source] then
            if not TheNet:IsDedicated() then
                for _,layer in ipairs(layers[source]) do
                    local fx=CreateEntity()
                    fx.entity:AddTransform();fx.entity:AddAnimState();fx.entity:AddFollower()
                    fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
                    fx.entity:SetParent(inst.entity)
                    fx.AnimState:SetBank(build);fx.AnimState:SetBuild(build)
                    fx.AnimState:PlayAnimation(layer[1],true)
                    fx.Follower:FollowSymbol(inst.GUID,"swap_object",0,0,0,true,nil,layer[2],layer[3])
                end
            end
        else
            inst.AnimState:OverrideSymbol("swap_object",build,symbol)
            if pose=="whip" then inst.AnimState:OverrideSymbol("whipline",build,"whipline") end
        end
        inst:AddTag("FX");inst:AddTag("NOCLICK");inst.entity:SetPristine()
        inst.persists=false
        if source=="torch" and TheWorld.ismastersim then
            local flame=SpawnPrefab("torchfire")
            flame.entity:SetParent(inst.entity)
            flame.entity:AddFollower()
            flame.Follower:FollowSymbol(inst.GUID,"swap_object",flame.fx_offset_x or 0,flame.fx_offset,0)
            inst._nw_flame=flame
            inst:ListenForEvent("onremove",function() if flame:IsValid() then flame:Remove() end end)
        end
        return inst
    end,assets,source=="torch" and {"torchfire"} or nil)
end
return weapon_fx
