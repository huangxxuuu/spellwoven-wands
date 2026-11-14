local C=require("nw/constants/native_effects")
local M={}
local Native=require("nw/native_targeting")
function M.bell(inst,attacker,scale)
    local selected=Native.context(inst)
    if not selected and scale<=1 or not attacker or not attacker:IsValid() then return end
    local x,_,z=inst.Transform:GetWorldPosition()
    local weapon,combat=inst.components.weapon,attacker.components.combat
    local damage=weapon.damage
    local skills=attacker.components.skilltreeupdater
    if skills and skills:IsActivated("wolfgang_dumbbell_throwing_2") then weapon.damage=damage*TUNING.SKILLS.WOLFGANG_DUMBELL_TOSS_2
    elseif skills and skills:IsActivated("wolfgang_dumbbell_throwing_1") then weapon.damage=damage*TUNING.SKILLS.WOLFGANG_DUMBELL_TOSS_1 end
    local must=not selected and {"_combat","_health"} or nil
    for _,e in ipairs(TheSim:FindEntities(x,0,z,C.bell.radius*scale,must,{"FX","NOCLICK","DECOR","INLIMBO"})) do
        if selected or e:GetDistanceSqToPoint(x,0,z)>C.bell.radius^2 then
            local allowed=not e.components.minigame_participator and not e:HasTag("playerghost")
                and (selected and Native.permits(inst,e) or not selected
                    and combat and (not e.isplayer or TheNet:GetPVPEnabled()) and not combat:IsAlly(e))
            local hit=allowed and combat and e.components.combat and e.components.health
                and not e.components.health:IsDead()
            if hit then
                local old=combat.ignorehitrange;combat.ignorehitrange=true
                combat:DoAttack(e,inst,inst);combat.ignorehitrange=old
            end
            local cold=selected and allowed or not selected and (hit or e==attacker)
            if cold and inst.isiceattack and e:IsValid() and e.components.freezable then e.components.freezable:AddColdness(C.bell.coldness) end
        end
    end
    weapon.damage=damage
end
local works={CHOP=true,DIG=true,HAMMER=true,MINE=true}
local tags={"_combat","CHOP_workable","DIG_workable","HAMMER_workable","MINE_workable"}
function M.tornado(inst)
    local selected=Native.context(inst)
    local scale=inst._nw_giant or 1
    if not selected and scale==1 then return end
    local x,y,z=inst.Transform:GetWorldPosition()
    for _,e in ipairs(TheSim:FindEntities(x,y,z,C.tornado.radius*scale,nil,{"INLIMBO","tornado_immune"},tags)) do
        if (selected and Native.permits(inst,e) or not selected and e~=inst.WINDSTAFF_CASTER)
            and e:IsValid() and (selected or scale<1 or e:GetDistanceSqToPoint(x,y,z)>C.tornado.radius^2) then
            local c,h,w=e.components.combat,e.components.health,e.components.workable
            if h and not h:IsDead() and c and c:CanBeAttacked()
                and (selected or TheNet:GetPVPEnabled() or not (inst.WINDSTAFF_CASTER_ISPLAYER and e:HasAnyTag("player","possessedbody"))) then
                local damage=TUNING.TORNADO_DAMAGE*(inst.WINDSTAFF_CASTER_ISPLAYER and e:HasTag("player") and TUNING.PVP_DAMAGE_MOD or 1)
                c:GetAttacked(inst,damage,nil,"wind")
                local caster=inst.WINDSTAFF_CASTER
                if e:IsValid() and caster and caster:IsValid() and e.components.combat and not h:IsDead()
                    and not (e.components.follower and e.components.follower.keepleaderonattacked and e.components.follower:GetLeader()==caster) then
                    e.components.combat:SuggestTarget(caster)
                end
            elseif w and w:CanBeWorked() and w:GetWorkAction() and works[w:GetWorkAction().id] then
                SpawnPrefab("collapse_small").Transform:SetPosition(e.Transform:GetWorldPosition());w:WorkedBy(inst,C.tornado.work)
            end
        end
    end
end
function M.install_tornado(sg)
    local function extend(fn,enter)
        return function(inst,...)
            if Native.context(inst) or inst._nw_giant and inst._nw_giant<1 then
                if enter then
                    if enter=="idle" then inst.Physics:Stop()
                    else inst.components.locomotor:WalkForward() end
                    inst.AnimState:PushAnimation("tornado_loop",false)
                end
            else fn(inst,...) end
            if inst:IsValid() then M.tornado(inst) end
        end
    end
    for name,state in pairs(sg.states) do
        if name=="idle" or name=="walk" then state.onenter=extend(state.onenter,name) end
        if name=="walk" or name=="run_start" or name=="run" or name=="run_stop" then
            for _,event in ipairs(state.timeline or {}) do event.fn=extend(event.fn) end
        end
    end
end
return M
