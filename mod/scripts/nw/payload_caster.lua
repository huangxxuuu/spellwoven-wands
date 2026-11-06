local M={}
function M.resolve(e)
    local seen={}
    while e and not seen[e] do
        seen[e]=true
        local c=e.components or {}
        local source=e._nw_owner or e._shot and e._shot.owner
            or c.explosive and (c.explosive.attacker or c.explosive.pvpattacker)
            or c.projectile and c.projectile.owner or c.complexprojectile and c.complexprojectile.attacker
            or c.inventoryitem and c.inventoryitem.owner
        if not source then return c.combat and require("nw/persistent_fields").caster(e) or nil end
        e=source
    end
end
function M.neutral(x,z)
    local e=CreateEntity()
    e.entity:AddTransform();e.Transform:SetPosition(x,0,z)
    e:AddTag("FX");e:AddTag("NOCLICK");e:AddTag("notarget")
    e:AddComponent("combat")
    e.persists=false;e._nw_neutral=true;e._nw_owned=0
    e:DoPeriodicTask(1,function()
        if e._nw_owned==0 and require("nw/executor").owner_used(e)==0 then e:Remove() end
    end)
    return e
end
function M.retain(owner,inst)
    if not owner or not owner._nw_neutral or inst._nw_neutral_retained then return end
    inst._nw_neutral_retained=true
    owner._nw_owned=owner._nw_owned+1
    inst:ListenForEvent("onremove",function() owner._nw_owned=owner._nw_owned-1 end)
end
return M
