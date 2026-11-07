local M={}
local omit={"INLIMBO","FX","playerghost"}
function M.absorb(owner,x,z,nx,nz,r)
    local dx,dz=nx-x,nz-z
    local length=math.sqrt(dx*dx+dz*dz)
    for _,e in ipairs(TheSim:FindEntities((x+nx)/2,0,(z+nz)/2,r+length/2,nil,omit,{"fire","smolder"})) do
        local ex,_,ez=e.Transform:GetWorldPosition()
        local t=length>0 and math.clamp(((ex-x)*dx+(ez-z)*dz)/(length*length),0,1) or 0
        if (x+t*dx-ex)^2+(z+t*dz-ez)^2<=r*r and e.components.burnable then
            e.components.burnable:Extinguish()
            local fx=SpawnPrefab("fire_fail_fx");fx.Transform:SetPosition(ex,.4,ez)
        end
    end
end
function M.burst(inst,owner,x,z,r,direct)
    local fx=SpawnPrefab("nw_lighter_burst_fx")
    fx.Transform:SetPosition(x,0,z);fx:SetRadius(r)
    for _,e in ipairs(TheSim:FindEntities(x,0,z,r,{"player"},omit)) do
        if e~=direct and e.components.combat and e.components.health and not e.components.health:IsDead() then
            local p=inst._shot and inst._shot.p
            local health=e.components.health
            local before=health.currenthealth
            e.components.combat:GetAttacked(owner,p and p.damage or 17,inst,"fire")
            require("nw/journal_damage").loss(owner,p,health,before)
        end
    end
    for _,e in ipairs(TheSim:FindEntities(x,0,z,r,nil,omit,{"cookable","canlight","burnable"})) do
        if e:IsValid() then
            local cook=e.components.cookable
            if cook and cook.product then
                local pos=e:GetPosition()
                local count=e.components.stackable and e.components.stackable:StackSize() or 1
                local prod=cook:Cook(inst,owner)
                if prod then
                    e:Remove()
                    if prod.components.stackable then prod.components.stackable:SetStackSize(count) end
                    prod.Transform:SetPosition(pos:Get())
                end
            elseif e.components.burnable and e.components.burnable.canlight and not e:HasTag("player") then
                e.components.burnable:Ignite(true,owner)
            end
        end
    end
end
return M
