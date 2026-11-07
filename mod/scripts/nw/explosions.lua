-- Gunpowder-style damage/ignition without structural demolition or the global
-- explosion event (boat hulls and docks consume that event independently).
local M={}
local function structure(e)
    local c=e.components
    return e:HasTag("structure") or e:HasTag("wall") or e:HasTag("boat")
        or c.hullhealth or c.boatphysics or c.walkableplatform
        or c.workable and c.workable:GetWorkAction()==ACTIONS.HAMMER
end
function M.hit(owner,p,x,z)
    local modifier=p and p.flags and p.flags.explosive_hit
    if not modifier then return end
    local bomb=SpawnPrefab("gunpowder")
    if not bomb then return end
    bomb.persists=false
    bomb.Transform:SetPosition(x,0,z)
    bomb._nw_owner=owner
    require("nw/journal_damage").tag(bomb,owner,p)
    local explosive=bomb.components.explosive
    explosive:SetAttacker(owner)
    local damage=modifier.explosion_damage or 25
    local radius=(modifier.radius or 3)*require("nw/projectile_size").factor(p)
    local fx=require("nw/spell_effects").fx("nw_blast_fx",x,z)
    if fx then fx:SetRadius(radius) end
    local workleft=TUNING.EXPLOSIVE_MAX_WORKABLE_INVENTORYITEMS
    for _,e in ipairs(TheSim:FindEntities(x,0,z,radius,nil,{"INLIMBO","notarget"})) do
        if e~=bomb and e:IsValid() and not e:IsInLimbo() then
            local c=e.components
            local protected=structure(e)
            local mult=bomb.components.damagetypebonus and bomb.components.damagetypebonus:GetBonus(e) or 1
            if not protected and c.workable and c.workable:CanBeWorked() then
                local work=10*mult
                if c.inventoryitem then
                    if workleft>0 then
                        workleft=workleft-1
                        work=work*(c.stackable and c.stackable:StackSize() or 1)
                    else work=0 end
                end
                if work>0 then c.workable:WorkedBy(bomb,work) end
            end
            if e:IsValid() and not e:IsInLimbo() then
                -- Structural protection does not grant fire immunity.
                if not c.fueled and c.burnable and not c.burnable:IsBurning() and not e:HasTag("burnt") then
                    c.burnable:Ignite(true,owner)
                end
                if not protected then
                    if c.combat and c.combat:CanBeAttacked() and not (c.health and c.health:IsDead()) then
                        local dmg=damage*mult
                        if c.explosiveresist then
                            dmg=dmg*(1-c.explosiveresist:GetResistance())
                            c.explosiveresist:OnExplosiveDamage(dmg,bomb)
                        end
                        c.combat:GetAttacked(bomb,dmg)
                        if e:IsValid() and c.combat and not (c.health and c.health:IsDead()) and owner and owner:IsValid() then
                            c.combat:SuggestTarget(owner)
                        end
                    end
                    if e:IsValid() then e:PushEvent("explosion",{explosive=bomb}) end
                end
            end
        end
    end
    bomb:Remove()
end
return M
