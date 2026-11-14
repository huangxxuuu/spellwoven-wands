local C=require("nw/constants/casting")
local M={}
function M.install(sg)
    local attack=sg.states.attack
    local enter=attack.onenter
    attack.onenter=function(inst,...)
        local act=inst:GetBufferedAction()
        enter(inst,...)
        if act and act.action==ACTIONS.NW_CAST
            and inst.sg.currentstate.name=="attack" and inst.sg:HasStateTag("abouttoattack") then
            inst.sg.statemem.projectiledelay=C.projectile_delay_frames*FRAMES-FRAMES
        end
    end
end
return M
