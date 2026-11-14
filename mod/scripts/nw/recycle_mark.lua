local C=require("nw/constants/visuals/recycle_mark")
local M={}
function M.attach(item,draw)
    item._nw_mark=net_bool(item.GUID,"nw_recycle.mark","nw_markdirty")
    local function refresh()
        if TheNet:IsDedicated() then return end
        if not item._nw_mark:value() then
            if item._nw_outline then item._nw_outline:Remove();item._nw_outline=nil end
            return
        end
        if item._nw_outline then return end
        local glow=CreateEntity()
        glow.entity:AddTransform();glow.entity:AddAnimState()
        glow:AddTag("FX");glow:AddTag("NOCLICK");glow.persists=false
        glow.entity:SetParent(item.entity)
        draw(glow,item)
        glow.Transform:SetScale(C.scale,C.scale,C.scale)
        glow.AnimState:SetFinalOffset(C.offset)
        glow.AnimState:SetLightOverride(C.light)
        glow.AnimState:SetAddColour(unpack(C.colour))
        glow.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
        item._nw_outline=glow
    end
    item:ListenForEvent("nw_markdirty",refresh)
    item.SetNWMarked=function(_,enabled) item._nw_mark:set(enabled);refresh() end
    if not TheWorld.ismastersim then item:DoTaskInTime(0,refresh) end
end
return M
