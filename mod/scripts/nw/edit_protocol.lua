local T=require("nw/locale").t
local U=require("nw/util")
local CastAction=require("nw/cast_action")
local Editing=require("nw/editing")
local M={}
M.messages={OK=T("法术槽已更新。"),NOT_OWNER=T("请先装备法杖。"),WAND_CHANGED=T("法杖已切换，请重新选择槽位。"),
    OUT_OF_RANGE=T("未检测到附近奥术台，请靠近后再试。"),STALE_REVISION=T("法术槽已更新，请再点一次。"),
    INVALID_SLOT=T("这个法术槽不存在。"),CARD_MISSING=T("法术卡已移动，请从随身物品栏重新选择。"),
    INVENTORY_FULL=T("请先腾出一格随身物品栏。"),BUSY=T("操作太快，请稍后再试。"),
    SPAWN_FAILED=T("法术卡创建失败。"),UNSUPPORTED_CARD=T("该法术尚未支持编辑。"),INVALID_REQUEST=T("换卡请求无效，请重新打开编辑器。")}
function M.id(item)
    return item and item.Network and item.Network:GetNetworkID() or 0
end
local function integer(n)
    return U.finite(n) and n>=0 and n==math.floor(n)
end
-- GUID is process-local. Only network IDs may cross the RPC boundary as numbers.
function M.request(player,slot,cardid,revision,wandid,cursor)
    if not integer(cardid) or not integer(wandid) or wandid==0 or not integer(revision) then return false,"INVALID_REQUEST" end
    local wand=CastAction.hand(player)
    if not wand then return false,"NOT_OWNER" end
    if M.id(wand)~=wandid then return false,"WAND_CHANGED" end
    if (player._nw_nextedit or 0)>GetTime() then return false,"BUSY" end
    player._nw_nextedit=GetTime()+.15
    CastAction.stop(player);player._nw_edit_until=GetTime()+.75
    local source
    if cardid~=0 then
        local inv=player.components.inventory
        if cursor then
            local item=inv:GetActiveItem()
            if M.id(item)==cardid then source=item end
        else
            for i=1,inv.maxslots do
                local item=inv:GetItemInSlot(i)
                if item and M.id(item)==cardid then source=item;break end
            end
        end
        if not source then return false,"CARD_MISSING" end
    end
    local ok,err=Editing.commit(player,wand,slot,source,revision,cursor)
    return ok,ok and "OK" or err
end
function M.focus(player,editing)
    CastAction.stop(player);player._nw_edit_until=editing==false and 0 or GetTime()+.75
    local wand=CastAction.hand(player)
    return M.id(wand),wand~=nil and Editing.near(player)
end
function M.send_result(player,request,wandid,ok,code)
    if player.userid then
        SendModRPCToClient(CLIENT_MOD_RPC.nw_weave.edit_result,player.userid,request,wandid,ok,code)
    end
end
function M.handle(player,slot,cardid,revision,wandid,request,cursor)
    if not integer(request) or request>2147483647 then return end
    local ok,code=M.request(player,slot,cardid,revision,wandid,cursor)
    M.send_result(player,request,integer(wandid) and wandid or 0,ok,code)
    return ok,code
end
return M
