local M={}

function M.print_lines(text)
    for line in tostring(text):gmatch("[^\r\n]+") do print(line) end
end

function M.report(text)
    text=tostring(text)
    M.print_lines(text)
    if ThePlayer and ThePlayer.userid and
        (TheNet:IsDedicated() or ThePlayer.userid~=TheNet:GetUserID()) then
        SendModRPCToClient(CLIENT_MOD_RPC.nw_weave.dev_help,ThePlayer.userid,text)
    end
end

return M
