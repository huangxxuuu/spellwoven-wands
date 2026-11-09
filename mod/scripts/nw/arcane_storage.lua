-- Both containers use the stock dust stack size as their visual threshold.
local M={
    atlas="images/inventoryimages/nw_arcane_storage.xml",
    FULL_THRESHOLD=2*require("nw/acquisition").materials.nw_dust[3],
    DUST_SECONDS=60,
    DUSTBOX_SCALE=1.5,
    LAMP_SCALE=1.65,
    -- Ground footprint is independent of the hanging lamp's visual height.
    LAMP_COLLISION_RADIUS=.4,
    LAMP_MIN_SPACING=2,
    LIGHT={half_radius=3.5,full_radius=5,intensity=.6,falloff=.7,colour={.78,.50,1}},
}

function M.Count(container)
    local item=container and container:GetItemInSlot(1)
    if not item or item.prefab~="nw_dust" then return 0 end
    return item.components.stackable and item.components.stackable:StackSize() or 1
end

function M.StateForCount(count)
    return count<=0 and "empty" or count>M.FULL_THRESHOLD and "full" or "half"
end

function M.Watch(inst,callback)
    local watched,pending
    local queue
    local function bind(item)
        if watched==item then return end
        if watched then
            inst:RemoveEventCallback("stacksizechange",queue,watched)
            inst:RemoveEventCallback("onremove",queue,watched)
        end
        watched=item
        if watched then
            inst:ListenForEvent("stacksizechange",queue,watched)
            inst:ListenForEvent("onremove",queue,watched)
        end
    end
    local function refresh()
        if pending then pending:Cancel();pending=nil end
        local container=inst.components.container
        bind(container and container:GetItemInSlot(1))
        local count=M.Count(container)
        callback(inst,M.StateForCount(count),count)
    end
    queue=function()
        -- A native merge changes the stored stack without sending itemget.
        -- Defer until the transfer finishes, so temporary empty slots do not flash.
        if not pending then pending=inst:DoTaskInTime(0,refresh) end
    end
    inst:ListenForEvent("itemget",queue)
    inst:ListenForEvent("itemlose",queue)
    inst:ListenForEvent("onremove",function()
        if pending then pending:Cancel();pending=nil end
        bind(nil)
    end)
    inst._nw_storage_refresh=refresh
    queue()
    return refresh
end

return M
