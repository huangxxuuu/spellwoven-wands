local M={}

function M.print_lines(text)
    -- Each help entry gets its own console history line.
    for line in tostring(text):gmatch("[^\r\n]+") do print(line) end
end

function M.report(text)
    text=tostring(text)
    M.print_lines(text)
    -- Remote execution binds ThePlayer to the administrator who ran it.
    -- Do not use ConsoleCommandPlayer here: a selected player may be someone else.
    -- A hosted world's dedicated child process can share the host's user ID.
    -- Its print output still goes to server_log, not the host client's console.
    -- Only an in-process listen host can read the local print directly.
    if ThePlayer and ThePlayer.userid and
        (TheNet:IsDedicated() or ThePlayer.userid~=TheNet:GetUserID()) then
        SendModRPCToClient(CLIENT_MOD_RPC.nw_weave.dev_help,ThePlayer.userid,text)
    end
end

return M
