local M = {}
local report = require("nw/dev_output").report

function M.build(radius)
    radius = radius == nil and 8 or radius
    if type(radius) ~= "number" or radius ~= math.floor(radius) or radius < 2 or radius > 32 then
        report("NW: nw_arena(n) 的 n 须为 2～32 的整数；默认 8，即 17×17 格。")
        return
    end
    local player = ConsoleCommandPlayer()
    if not player or not TheWorld or not TheWorld.ismastersim then
        report("NW: 请由房主或管理员在远程控制台执行。")
        return
    end
    local map = TheWorld.Map
    local x,y,z = player.Transform:GetWorldPosition()
    local tx,tz = map:GetTileCoordsAtPoint(x,y,z)
    local cx,cy,cz = map:GetTileCenterPoint(tx,tz)
    local tiles = {}
    for a=-radius,radius do
        for b=-radius,radius do
            local px,py,pz = map:GetTileCenterPoint(tx+a,tz+b)
            if map:IsPassableAtPoint(px,0,pz) and not map:IsOceanAtPoint(px,0,pz) then
                tiles[#tiles+1] = {tx+a,tz+b,
                    (math.abs(a)==radius or math.abs(b)==radius or a==0 or b==0)
                    and WORLD_TILES.CARPET or WORLD_TILES.CHECKER}
            end
        end
    end
    if #tiles == 0 then report("NW: 脚下附近没有可铺设的陆地。") return end
    local removed = 0
    for _,e in ipairs(TheSim:FindEntities(cx,0,cz,(radius+1)*4*1.5,nil,
        {"player","INLIMBO","CLASSIFIED","FX"})) do
        if e:IsValid() and e ~= TheWorld and e.prefab and e.Transform
            and not e:HasTag("player") and e.entity:GetParent()==nil
            and not (e.components.inventoryitem and e.components.inventoryitem.owner) then
            local ex,ey,ez = e.Transform:GetWorldPosition()
            local a,b = map:GetTileCoordsAtPoint(ex,ey,ez)
            if math.abs(a-tx)<=radius and math.abs(b-tz)<=radius then
                e:Remove()
                removed = removed+1
            end
        end
    end
    for _,tile in ipairs(tiles) do map:SetTile(tile[1],tile[2],tile[3]) end
    report(string.format("NW: 场地 %d×%d 格，已铺 %d 格，清除 %d 个实体；大理石铺面、地毯外框与十字分区。",
        radius*2+1,radius*2+1,#tiles,removed))
    return #tiles,removed
end

return M
