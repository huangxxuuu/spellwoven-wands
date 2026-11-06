-- Extend only the annulus outside each native effect's original radius. The
-- original callback remains responsible for its inner disk and timing.
local M={}
function M.bell(inst,attacker,scale)
    if scale<=1 or not attacker:IsValid() then return end
    local x,_,z=inst.Transform:GetWorldPosition()
    local weapon,combat=inst.components.weapon,attacker.components.combat
    local damage=weapon.damage
    local skills=attacker.components.skilltreeupdater
    if skills and skills:IsActivated("wolfgang_dumbbell_throwing_2") then weapon.damage=damage*TUNING.SKILLS.WOLFGANG_DUMBELL_TOSS_2
    elseif skills and skills:IsActivated("wolfgang_dumbbell_throwing_1") then weapon.damage=damage*TUNING.SKILLS.WOLFGANG_DUMBELL_TOSS_1 end
    for _,e in ipairs(TheSim:FindEntities(x,0,z,2*scale,{"_combat","_health"},{"FX","NOCLICK","DECOR","INLIMBO"})) do
        if e:GetDistanceSqToPoint(x,0,z)>4 then
            local hit=not e.components.minigame_participator and not e:HasTag("playerghost")
                and (not e.isplayer or TheNet:GetPVPEnabled()) and not combat:IsAlly(e)
            if hit then
                local old=combat.ignorehitrange;combat.ignorehitrange=true
                combat:DoAttack(e,inst,inst);combat.ignorehitrange=old
            end
            if (hit or e==attacker) and inst.isiceattack and e:IsValid() and e.components.freezable then e.components.freezable:AddColdness(2) end
        end
    end
    weapon.damage=damage
end
local works={CHOP=true,DIG=true,HAMMER=true,MINE=true}
local tags={"_combat","CHOP_workable","DIG_workable","HAMMER_workable","MINE_workable"}
function M.tornado(inst)
    local scale=inst._nw_giant
    if not scale or scale<=1 then return end
    local x,y,z=inst.Transform:GetWorldPosition()
    for _,e in ipairs(TheSim:FindEntities(x,y,z,3*scale,nil,{"INLIMBO","tornado_immune"},tags)) do
        if e~=inst.WINDSTAFF_CASTER and e:IsValid() and e:GetDistanceSqToPoint(x,y,z)>9 then
            local c,h,w=e.components.combat,e.components.health,e.components.workable
            if h and not h:IsDead() and c and c:CanBeAttacked()
                and (TheNet:GetPVPEnabled() or not (inst.WINDSTAFF_CASTER_ISPLAYER and e:HasAnyTag("player","possessedbody"))) then
                local damage=TUNING.TORNADO_DAMAGE*(inst.WINDSTAFF_CASTER_ISPLAYER and e:HasTag("player") and TUNING.PVP_DAMAGE_MOD or 1)
                c:GetAttacked(inst,damage,nil,"wind")
                local caster=inst.WINDSTAFF_CASTER
                if e:IsValid() and caster and caster:IsValid() and e.components.combat and not h:IsDead()
                    and not (e.components.follower and e.components.follower.keepleaderonattacked and e.components.follower:GetLeader()==caster) then
                    e.components.combat:SuggestTarget(caster)
                end
            elseif w and w:CanBeWorked() and w:GetWorkAction() and works[w:GetWorkAction().id] then
                SpawnPrefab("collapse_small").Transform:SetPosition(e.Transform:GetWorldPosition());w:WorkedBy(inst,2)
            end
        end
    end
end
function M.install_tornado(sg)
    local function extend(fn)
        return function(inst,...) fn(inst,...);if inst:IsValid() then M.tornado(inst) end end
    end
    for name,state in pairs(sg.states) do
        if name=="idle" or name=="walk" then state.onenter=extend(state.onenter) end
        if name=="walk" or name=="run_start" or name=="run" or name=="run_stop" then
            for _,event in ipairs(state.timeline or {}) do event.fn=extend(event.fn) end
        end
    end
end
return M
