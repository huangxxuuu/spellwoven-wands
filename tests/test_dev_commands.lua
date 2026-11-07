local Dev = require("nw/dev_commands")
local Kit = require("nw/spellkit")
local globals = setmetatable({}, {__newindex=function() error("undeclared global") end})
local remove
local world = {ListenForEvent=function(_, event, fn) assert(event=="onremove");remove=fn end}
Dev.install(globals, world)
local previous_print, printed, sent = print, {}, nil
print = function(msg) printed[#printed+1]=msg end
CLIENT_MOD_RPC={nw_weave={dev_help={}}}
SendModRPCToClient=function(rpc, userid, message)
    assert(rpc==CLIENT_MOD_RPC.nw_weave.dev_help)
    sent={userid,message}
end
local dedicated=false
TheNet={GetUserID=function() return "host" end,IsDedicated=function() return dedicated end}
ThePlayer={userid="remote-admin"}
local listing=globals.nw_help()
assert(table.concat(printed,"\n")==listing and sent[1]=="remote-admin" and sent[2]==listing)
assert(#printed==17)
local names={}
for name in listing:gmatch("\n(nw_%w+)%(") do
    assert(not names[name] and type(globals[name])=="function")
    names[name]=true
end
local count=0
for name in pairs(globals) do assert(names[name]);count=count+1 end
assert(count==16 and globals.nw_rollwand==Kit.rollwand and globals.nw_combo==Kit.wand)
printed={};sent=nil
listing=globals.nw_testscene()
assert(#printed==19 and table.concat(printed,"\n")==listing)
assert(listing:find('nw_testscene("all")',1,true) and sent[2]==listing)
printed={}
require("nw/dev_output").print_lines(sent[2])
assert(#printed==19 and table.concat(printed,"\n")==listing)
-- A remote caller must also see validation failures rather than silent returns.
printed={};sent=nil
globals.nw_testcleanup(22)
assert(#printed==1 and sent[2]==printed[1])
ConsoleCommandPlayer=function() return nil end
printed={};sent=nil
globals.nw_testscene("all")
assert(#printed==1 and sent[2]==printed[1])
ConsoleCommandPlayer=function() return {Transform={GetWorldPosition=function() return 0,0,0 end}} end
TheWorld.Map={IsPassableAtPoint=function() return false end}
printed={};sent=nil
globals.nw_testscene("all")
assert(#printed==1 and sent[2]==printed[1] and printed[1]:find("NW:",1,true))
ThePlayer={userid="host"};sent=nil
globals.nw_help();assert(not sent)
-- A hosted world's separate server shares the owner's account, not its log UI.
dedicated=true;sent=nil;printed={}
local hosted=globals.nw_help()
assert(sent and sent[1]=="host" and sent[2]==hosted and table.concat(printed,"\n")==hosted)
-- Selection must not redirect a private console reply to another player.
ConsoleCommandPlayer=function() return {userid="someone-else"} end
sent=nil;globals.nw_help();assert(sent and sent[1]=="host")
ThePlayer=nil;sent=nil;globals.nw_help();assert(not sent)
remove();assert(next(globals)==nil)
print=previous_print
print("developer commands: complete help, private remote-admin reply, world teardown")
