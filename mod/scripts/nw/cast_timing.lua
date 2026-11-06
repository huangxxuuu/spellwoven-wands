-- Keep native attack prediction, movement cancellation and recovery. Our wand
-- has no melee weapon component, so its nopunch animation branch does not read
-- weapon.projectiledelay. Supply the same timer as firestaff to native attack's
-- existing onupdate on BOTH peers; never launch from a task after leaving it.
local M={}
function M.install(sg)
    local attack=sg.states.attack
    local enter=attack.onenter
    attack.onenter=function(inst,...)
        local act=inst:GetBufferedAction()
        enter(inst,...)
        if act and act.action==ACTIONS.NW_CAST
            and inst.sg.currentstate.name=="attack" and inst.sg:HasStateTag("abouttoattack") then
            inst.sg.statemem.projectiledelay=8*FRAMES-FRAMES
        end
    end
end
return M
