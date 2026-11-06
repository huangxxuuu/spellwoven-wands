-- Active, world-lived spell effects. Zero always means unlimited.
local M={sentries=0,storms=0,world_storms=0,lights=0,cast=0,range=0,depth=0,boundary_cleanup=false,permanent_motion_cleanup=false}
function M.track(inst,owner,key,limit)
    local list=owner[key] or {}
    owner[key]=list
    if limit>0 and #list>=limit then list[1]:Remove() end
    list[#list+1]=inst
    inst:ListenForEvent("onremove",function()
        for i,v in ipairs(list) do
            if v==inst then table.remove(list,i);break end
        end
    end)
end
return M
