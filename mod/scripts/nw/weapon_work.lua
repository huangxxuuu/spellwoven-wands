local Melee=require("nw/constants/melee")
local C,Work=Melee.runtime,Melee.work
local Combat=require("nw/constants/combat")
local Target=require("nw/targeting")
local M={}
local TOOL_TARGETS={default=true}
local function credit(e,key,amount)
    local c=e.components.nw_workcredit or e:AddComponent("nw_workcredit")
    return c:Take(key,amount)
end
local function effectiveness(id)
    if id=="lucy" then return Work.lucy_efficiency end
    if id=="moonglassaxe" then return TUNING.MOONGLASSAXE.EFFECTIVENESS end
    if id=="multitool_axe_pickaxe" then return TUNING.MULTITOOL_AXE_PICKAXE_EFFICIENCY end
    if id=="pickaxe_lunarplant" then return TUNING.PICKAXE_LUNARPLANT_EFFICIENCY end
    if id=="shadow_battleaxe" then return TUNING.SHADOW_BATTLEAXE.LEVEL[1].CHOPPING_EFFICIENCY end
    if id=="merm_tool" or id=="merm_tool_upgraded" then return TUNING[id:upper()].EFFICIENCY end
    return 1
end
local function terrain(inst,owner,action,x,z,r)
    local map,seen=TheWorld.Map,{}
    for _,pt in ipairs({{0,0},{r,0},{-r,0},{0,r},{0,-r}}) do
        local tx,tz=x+pt[1],z+pt[2]
        local a,b=map:GetTileCoordsAtPoint(tx,0,tz)
        local till=action=="TILL"
        local key=till and string.format("T:%d:%d",math.floor(tx*Work.tile_precision+.5),math.floor(tz*Work.tile_precision+.5)) or ("F:"..a..":"..b)
        if not seen[key] and (till and map:CanTillSoilAtPoint(tx,0,tz,false) or not till and map:CanTerraformAtPoint(tx,0,tz)) then
            seen[key]=true
            if credit(TheWorld,key,Work.credit)>0 then
                local pos=Vector3(tx,0,tz)
                if till then inst.components.farmtiller:Till(pos,owner) else inst.components.terraformer:Terraform(pos,owner) end
            end
        end
    end
end
function M.strike(inst,owner,p,x,z,dx,dz)
    if not p.work or #p.work==0 then return end
    local eff=effectiveness(p.source_weapon)
    local tool=inst.components.tool or inst:AddComponent("tool")
    if p.source_weapon=="multitool_axe_pickaxe" or p.source_weapon=="shadow_battleaxe" or p.source_weapon=="pickaxe_lunarplant" then tool:EnableToughWork(true) end
    for _,id in ipairs(p.work) do
        if id=="TILL" or id=="TERRAFORM" then
            if Target.allows_category(p.flags,"nature") then
                local name=id=="TILL" and "farmtiller" or "terraformer"
                if not inst.components[name] then inst:AddComponent(name) end
                terrain(inst,owner,id,x,z,p.work_radius)
            end
        else
            local action=ACTIONS[id]
            tool:SetAction(action,eff)
            local tags={id=="SCYTHE" and "pickable" or id.."_workable"}
            for _,e in ipairs(TheSim:FindEntities(x,0,z,p.work_radius+C.query_padding,tags,{"INLIMBO","FX","intense"})) do
                local tx,_,tz=e.Transform:GetWorldPosition()
                local rx,rz=tx-x,tz-z
                if Target.accepts(owner,e,p.flags,TOOL_TARGETS)
                    and require("nw/melee").contains(p,rx*dx+rz*dz,rz*dx-rx*dz,e:GetPhysicsRadius(Combat.collision_radius)+C.hit_padding,0,1)
                    and require("nw/spell_effects").clear(x,z,tx,tz,require("nw/spell_effects").scan(x,z,p.reach+C.query_padding,p.flags),e) then
                    local w=e.components.workable
                    if id=="SCYTHE" and e:HasOneOfTags(HARVESTABLE_PLANT_TARGET_TAGS) and e.components.pickable and e.components.pickable:CanBePicked() then
                        if credit(e,id,Work.credit)>=1 then
                            local _,loot=e.components.pickable:Pick(TheWorld)
                            for _,item in ipairs(loot or {}) do Launch(item,owner,Work.loot_speed) end
                        end
                    elseif w and w:CanBeWorked() and w:GetWorkAction()==action then
                        local mult=owner.components.workmultiplier
                        local recoil,n=w:ShouldRecoil(owner,inst,eff*(mult and mult:GetMultiplier(action) or 1))
                        if mult then n=mult:ResolveSpecialWorkAmount(action,e,inst,n,recoil) end
                        if n>0 then
                            local full=p.source_weapon=="fumaroleaxe" or p.source_weapon=="fumarolepickaxe"
                            local strokes=credit(e,id,full and n or n*Work.credit)
                            if strokes>0 then w:WorkedBy_Internal(owner,strokes) end
                        end
                    end
                end
            end
        end
    end
end
return M
