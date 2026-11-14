local C=require("nw/constants/protocol").edit
local T=require("nw/locale").t
local Protocol=require("nw/edit_protocol")
local M={}
function M.submit(player,wand,slot,card,cursor)
    local previous=player._nw_edit_request
    if previous and GetTime()-previous.time<C.client_timeout and not previous.done then return false end
    player._nw_edit_serial=(player._nw_edit_serial or 0)%2147483647+1
    local request={id=player._nw_edit_serial,wand=Protocol.id(wand),time=GetTime()}
    player._nw_edit_request=request
    SendModRPCToServer(MOD_RPC.nw_weave.edit,slot,Protocol.id(card),wand._nw_revision:value(),request.wand,request.id,cursor==true)
    return true
end
function M.result(request,wandid,ok,code)
    local pending=ThePlayer and ThePlayer._nw_edit_request
    if pending and pending.id==request and pending.wand==wandid then
        pending.done=true;pending.ok=ok;pending.code=code;pending.time=GetTime()
    end
end
function M.status(wandid,near)
    if ThePlayer then ThePlayer._nw_edit_status={wand=wandid,near=near,time=GetTime()} end
end
function M.text(player,wand)
    local id=Protocol.id(wand)
    local status=player._nw_edit_status
    local range
    if not status or status.wand~=id or GetTime()-status.time>C.status_max_age then range=T("正在确认奥术台距离…")
    elseif status.near then range=T("已靠近奥术台 · 可以编辑")
    else range=T("未检测到附近奥术台") end
    local request=player._nw_edit_request
    local feedback=T("点击随身法术卡安装或替换")
    if request and request.wand==id then
        if not request.done then
            feedback=GetTime()-request.time<C.client_timeout and T("正在提交换卡请求…") or T("未收到服务器回复，请重试或重开编辑器。")
        elseif GetTime()-request.time<C.result_duration then feedback=Protocol.messages[request.code] or T("换卡失败，请重试。") end
    end
    return range,feedback
end
return M
