local function scale(inst) inst.AnimState:SetScale(1.48,1.48) end
local function engraver_scale(inst) inst.AnimState:SetScale(1.1,1.1) end
local function make_station(name,bank,pose)
    local function fn()
        local inst=CreateEntity()
        inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddNetwork()
        MakeObstaclePhysics(inst,.735)
        inst.AnimState:SetBank(bank);inst.AnimState:SetBuild(bank);inst.AnimState:PlayAnimation(pose)
        if name=="nw_workbench" then
            scale(inst)
        else
            engraver_scale(inst)
            inst.entity:AddMiniMapEntity()
            inst.MiniMapEntity:SetIcon("nw_engraver.tex")
        end
        inst:AddTag(name)
        inst:AddTag("structure")
        inst:AddTag("prototyper")
        inst.entity:SetPristine()
        if not TheWorld.ismastersim then return inst end
        inst:AddComponent("inspectable")
        inst:AddComponent("prototyper")
        inst:AddComponent("craftingstation")
        inst.components.craftingstation.nosave = true
        local crafting=require("nw/crafting")
        for _,row in ipairs(require("nw/acquisition").menu_entries) do
            if row.station==name and crafting.recipe_enabled(row) then
                inst.components.craftingstation:LearnItem(row.name,row.name)
            end
        end
        inst:AddComponent("lootdropper")
        inst:AddComponent("workable")
        inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
        inst.components.workable:SetWorkLeft(4)
        inst.components.workable:SetOnFinishCallback(function(bench)
            bench.components.lootdropper:DropLoot()
            bench:Remove()
        end)
        return inst
    end
    return Prefab(name,fn,{Asset("ANIM","anim/"..bank..".zip")})
end
return make_station("nw_workbench","nw_stations","workbench"),
    make_station("nw_engraver","nw_stations","engraver"),
    MakePlacer("nw_engraver_placer","nw_stations","nw_stations","engraver",nil,nil,nil,nil,nil,nil,engraver_scale),
    MakePlacer("nw_workbench_placer","nw_stations","nw_stations","workbench",nil,nil,nil,nil,nil,nil,scale)
