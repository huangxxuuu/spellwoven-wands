-- Use the native right-click picker over empty water on a real coastline.
local M={}
local function coast(x,z)
    local map=TheWorld.Map
    for n=0,240 do
        for _,dir in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            local dx,dz=unpack(dir)
            local ax,az=x+n*2*dx,z+n*2*dz
            if map:IsLandTileAtPoint(ax,0,az) and map:IsOceanTileAtPoint(ax+2*dx,0,az+2*dz)
                and map:IsLandTileAtPoint(ax-3*dx,0,az-3*dz)
                and map:IsOceanTileAtPoint(ax+9*dx,0,az+9*dz)
                and #TheSim:FindEntities(ax,0,az,15,nil,{"INLIMBO"},{"boat","nw_test_target","wall"})==0
                and map:IsOceanTileAtPoint(ax+14*dx,0,az+14*dz) then
                return ax,az,dx,dz
            end
        end
    end
    error("NW_COAST: fixture needs a coast")
end
function M.run(x,z)
    local ax,az,dx,dz=coast(x,z)
    local function point(d) return Vector3(ax+d*dx,0,az+d*dz) end
    local boat=SpawnPrefab("boat")
    if boat.Physics then boat.Physics:Teleport(point(9):Get()) else boat.Transform:SetPosition(point(9):Get()) end
    local player=SpawnPrefab("wilson")
    player.entity:SetCanSleep(false);player.userid=""
    player:AddComponent("playeractionpicker");player:AddComponent("playercontroller")
    player.components.playercontroller:Enable(true)
    player.Physics:Teleport(point(-3):Get())
    local wand=SpawnPrefab("nw_wand")
    wand.components.nw_wand:InitializePrototype()
    local data=wand.components.nw_wand.data
    data.cards[1].spell_id="arrow";data.stats.spread=0
    data.config_revision=data.config_revision+1;wand.components.nw_wand:Sync()
    player.components.inventory:GiveItem(wand);player.components.inventory:Equip(wand)
    local dummy=SpawnPrefab("nw_target_dummy")
    dummy.Transform:SetPosition(point(4):Get())
    local function shoot(pos)
        local acts=player.components.playeractionpicker:GetRightClickActions(pos,nil)
        assert(acts[1] and acts[1].action==ACTIONS.NW_CAST,"NW_COAST: no right-click cast")
        player.sg:GoToState("idle");player.components.playercontroller:DoAction(acts[1])
    end
    TheWorld:DoTaskInTime(.3,function() shoot(point(16)) end)
    TheWorld:DoTaskInTime(2.8,function()
        assert(dummy.components.health.currenthealth==978,"NW_COAST: outgoing shot")
        dummy.Transform:SetPosition(point(-3):Get())
        player.Physics:Teleport(boat.Transform:GetWorldPosition())
        boat.components.walkableplatform:AddEntityToPlatform(player)
    end)
    TheWorld:DoTaskInTime(3.3,function()
        assert(player:GetCurrentPlatform()==boat,"NW_COAST: caster not on boat")
        shoot(point(-4))
    end)
    TheWorld:DoTaskInTime(5,function()
        assert(dummy.components.health.currenthealth==956,"NW_COAST: incoming shot")
        dummy:Remove()
        local fish=SpawnPrefab("oceanfish_small_1")
        fish.entity:SetCanSleep(false);fish.Physics:Teleport(point(15):Get())
        local shot=SpawnPrefab("nw_projectile")
        local p=require("nw/util").copy(require("nw/definitions").spells.edge_oceanfishingrod)
        local origin=point(9)
        shot:Launch(player,p,origin.x,origin.z,dx,dz,function() end)
        local bait=SpawnPrefab("nw_projectile")
        local bait_spell=require("nw/util").copy(require("nw/definitions").spells.edge_chum)
        bait:Launch(player,bait_spell,origin.x,origin.z,dx,dz,function() end,1.4)
        require("nw/engraved_flight").aim_ground(bait,bait._shot,5)
        TheWorld:DoTaskInTime(2,function()
            local caught=false
            for _,e in ipairs(TheSim:FindEntities(origin.x,0,origin.z,6,nil,{"INLIMBO"})) do
                if e.prefab=="oceanfish_small_1_inv" then caught=true;e:Remove() end
            end
            assert(caught,"NW_COAST: reel fish onto nearest boat")
            local water=point(14)
            local lure
            for _,e in ipairs(TheSim:FindEntities(water.x,0,water.z,1.5)) do
                if e.prefab=="chum_aoe" then lure=e;break end
            end
            assert(not bait:IsValid() and lure,"NW_CHUM: water landing must create native lure")
            -- Match native expiry: do not spawn replacement bait while its
            -- onremove handler is iterating and removing the existing pieces.
            lure.persists=false;lure:Remove()
            print("NW_CHUM_OCEAN_PASS: aimed ballistic landing and native chum effect")
            player:Remove();boat:Remove()
        end)
        print("NW_COAST_PASS: ocean right click, shore-to-sea hit and boat-to-shore hit")
    end)
end
return M
