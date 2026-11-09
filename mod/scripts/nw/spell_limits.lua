-- Active, world-lived spell effects. Zero always means unlimited.
local M={range=0,depth=0,boundary_cleanup=false,permanent_motion_cleanup=false}
-- Retain ownership lists for gameplay/debugging. Admission is centralized and
-- never evicts existing entities to make room for a new one.
function M.track(inst,owner,key)
    local list=owner[key] or {}
    owner[key]=list
    list[#list+1]=inst
    inst:ListenForEvent("onremove",function()
        for i,v in ipairs(list) do
            if v==inst then table.remove(list,i);break end
        end
    end)
end
return M
