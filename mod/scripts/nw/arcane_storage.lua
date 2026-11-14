local C=require("nw/constants/storage")
local M={
    atlas="images/inventoryimages/nw_arcane_storage.xml",
    FULL_THRESHOLD=C.full_stack_count*require("nw/acquisition").materials.nw_dust[3],
    DUST_SECONDS=C.dust_seconds,
    DUSTBOX_SCALE=C.dustbox_scale,
    LAMP_SCALE=C.lamp_scale,
    LAMP_COLLISION_RADIUS=C.lamp_collision_radius,
    LAMP_MIN_SPACING=C.lamp_min_spacing,
    LIGHT=require("nw/util").copy(C.light),
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
