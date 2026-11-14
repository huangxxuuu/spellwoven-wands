local C=require("nw/constants/visuals/weapon_visual")
local overrides=C.overrides

local layers=C.layers
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
