local C=require("nw/constants/wands").damage
local M={chance=C.chance,dust=C.dust}
function M.set(wand,broken)
    local c=wand.components.nw_wand
    if not c or not c.data then return false end
    c.data.broken=broken==true
    c.data.config_revision=c.data.config_revision+1
    c:Sync()
    return true
end
function M.hit(wand,attacker,target)
    if target and target:IsValid() and math.random()<M.chance then M.set(wand,true) end
end
function M.repair(act)
    local wand,dust,doer=act.target,act.invobject,act.doer
    if not wand or not wand:IsValid() or not wand:HasTag("nw_broken")
        or not dust or not dust:IsValid() or dust.prefab~="nw_dust"
        or dust.components.inventoryitem:GetGrandOwner()~=doer then return false end
    local holder=wand.components.inventoryitem:GetGrandOwner()
    if holder~=wand and holder~=doer or holder==wand and not doer:IsNear(wand,C.repair_distance) then return false end
    local stack=dust.components.stackable
    if not stack or stack:StackSize()<M.dust then return false end
    if not M.set(wand,false) then return false end
    stack:Get(M.dust):Remove()
    return true
end
function M.install(env)
    local a=Action({priority=C.action_priority,rmb=true,distance=C.repair_distance})
    a.id="NW_REPAIR";a.str=require("nw/locale").t("修复法杖（5 粉尘）");a.fn=M.repair
    env.AddAction(a)
    env.AddComponentAction("USEITEM","inventoryitem",function(item,doer,target,actions,right)
        if right and item.prefab=="nw_dust" and target:HasTag("nw_broken") then actions[#actions+1]=a end
    end)
    for _,sg in ipairs({"wilson","wilson_client"}) do env.AddStategraphActionHandler(sg,ActionHandler(a,"doshortaction")) end
end
return M
