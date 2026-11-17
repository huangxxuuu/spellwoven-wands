-- Actual component and RPC modules, with queued transport so stale deliveries
-- and migration ordering are exercised rather than replaced with a shortcut.
Class=function(ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...) local self=setmetatable({},cls);ctor(self,...);return self end})
end
local C=require("nw/constants/cast_binding")
local Component=require("components/nw_castbinding")
local function fresh()
    package.loaded["nw/cast_binding"]=nil
    return require("nw/cast_binding")
end
local uninstalled=fresh()
assert(uninstalled.ready() and uninstalled.get()==C.default and uninstalled.get_default()==C.default)
local nodes,clients,wire={},{},{}
local function task(node,delay,fn)
    local t={at=node.now+delay,fn=fn,Cancel=function(self) self.cancelled=true end}
    node.tasks[#node.tasks+1]=t;return t
end
local function advance(node,dt)
    node.now=node.now+dt
    local again=true
    while again do
        again=false
        for i,t in ipairs(node.tasks) do
            if not t.cancelled and not t.done and t.at<=node.now then
                t.done=true;t.fn();again=true;break
            end
        end
    end
end
local names={"cast_binding_query","cast_binding_set","cast_binding_state",
    "cast_binding_default_query","cast_binding_default_state"}
local function node(id,master,config)
    local n={id=id,now=0,tasks={},server={},client={},shard={},connected=true}
    nodes[id]=n
    local rpc={nw_weave={}}
    for _,name in ipairs(names) do rpc.nw_weave[name]=name end
    local g={TheWorld={ismastersim=master,ismastershard=id=="1"},SHARDID={MASTER="1"},
        MOD_RPC=rpc,CLIENT_MOD_RPC=rpc,SHARD_MOD_RPC=rpc,TheShard={GetShardId=function() return id end}}
    n.g=g;g.TheWorld.DoTaskInTime=function(_,delay,fn) return task(n,delay,fn) end
    g.Shard_IsWorldAvailable=function(target) return nodes[target] and nodes[target].connected end
    g.SendModRPCToServer=function(name,...)
        wire[#wire+1]={kind="server",source=n,name=name,args={...}}
    end
    g.SendModRPCToClient=function(name,userid,...)
        wire[#wire+1]={kind="client",target=clients[userid],name=name,args={...}}
    end
    g.SendModRPCToShard=function(name,target,...)
        wire[#wire+1]={kind="shard",source=id,target=nodes[target],name=name,args={...}}
    end
    local env={GetModConfigData=function(key) assert(key=="cast_key");return config end,
        AddModRPCHandler=function(_,name,fn) n.server[name]=fn end,
        AddClientModRPCHandler=function(_,name,fn) n.client[name]=fn end,
        AddShardModRPCHandler=function(_,name,fn) n.shard[name]=fn end,
        AddSimPostInit=function(fn) n.init=fn end,
        AddPlayerPostInit=function(fn) n.post=fn end}
    n.binding=fresh();n.binding.install(env,g)
    return n
end
local function deliver(e)
    if e.kind=="server" then
        local target=e.source.link
        target.node.server[e.name](target.player,unpack(e.args))
    elseif e.kind=="client" then e.target.client[e.name](unpack(e.args))
    else e.target.shard[e.name](e.source,unpack(e.args)) end
end
local function drain()
    local count=0
    while #wire>0 do
        count=count+1;assert(count<100,"RPC exchange must terminate")
        deliver(table.remove(wire,1))
    end
end
local guid=0
local function player(n,userid,saved)
    guid=guid+1
    local p={GUID=guid,userid=userid,components={},events={},valid=true}
    function p:IsValid() return self.valid end
    function p:DoTaskInTime(delay,fn) return task(n,delay,fn) end
    function p:ListenForEvent(name,fn)
        self.events[name]=self.events[name] or {};table.insert(self.events[name],fn)
    end
    function p:PushEvent(name,...)
        for _,fn in ipairs(self.events[name] or {}) do fn(self,...) end
    end
    function p:AddComponent(name) assert(name=="nw_castbinding");self.components[name]=Component(self) end
    function p:SaveForReroll() return {native="kept"} end
    function p:LoadForReroll(data) self.native=data and data.native end
    n.post(p)
    if saved then p.components.nw_castbinding:OnLoad(saved) end
    return p
end
local function connect(client,server,serverplayer)
    client.link={node=server,player=serverplayer}
    local old=client.g.ThePlayer
    if old then old:PushEvent("playerdeactivated") end
    local p=player(client,serverplayer.userid)
    client.g.ThePlayer=p
    clients[serverplayer.userid]=client
    p:PushEvent("playeractivated")
    advance(client,0)
    return p
end
local root=node("1",true,"mouse:1002")
local cave=node("2",true,"mouse:1001")
local client=node("client",false,"key:107")
root.init();root.connected=false;cave.init()
local cave_new=player(cave,"new")
advance(cave,0)
assert(cave.binding.get(cave_new)==nil,"cave must not initialize from its divergent config")
root.connected=true;advance(cave,1);drain()
assert(cave.binding.get(cave_new)=="mouse:1002","old save first opened in cave uses primary default")
local p=player(root,"user");advance(root,0)
connect(client,root,p)
assert(not client.binding.ready() and not client.binding.set("key:107"))
drain()
assert(client.binding.ready() and client.binding.get()=="mouse:1002" and client.binding.get_override()==nil)
assert(client.binding.get_default()=="mouse:1002")
local notices=0;local unsubscribe=client.binding.subscribe(function() notices=notices+1 end)
assert(client.binding.set("key:107") and client.binding.pending())
assert(not client.binding.set("mouse:1001"),"one unacknowledged edit at a time")
drain()
assert(client.binding.get()=="key:107" and client.binding.get_override()=="key:107" and not client.binding.pending())
assert(p.components.nw_castbinding.revision==1 and notices>0)
unsubscribe();local previous=notices
assert(client.binding.set(nil));drain()
assert(client.binding.get()=="mouse:1002" and client.binding.get_override()==nil and notices==previous)
assert(not client.binding.set("mouse:1003"),"scroll wheel is not a held binding")
assert(client.binding.set("mouse:1005"));drain()
local saved=p.components.nw_castbinding:OnSave()
assert(saved.revision==3 and saved.override=="mouse:1005" and saved.token==nil)
-- Saving and restoring belongs to the player, not global client persistence.
local reloaded=player(root,"reload",saved);advance(root,0)
assert(root.binding.get(reloaded)=="mouse:1005")
local reroll=player(root,"reroll");reroll:LoadForReroll(p:SaveForReroll());advance(root,0)
assert(root.binding.get(reroll)=="mouse:1005" and reroll.native=="kept")
local token=p.components.nw_castbinding.token
local migrated=player(cave,"user",saved);advance(cave,0)
assert(migrated.components.nw_castbinding.token~=token and cave.binding.get(migrated)=="mouse:1005")
-- Queue a write and a reply from the old lifetime, then move to the cave.
assert(client.binding.set("key:108"))
local old_write=table.remove(wire,1)
client.binding.query();deliver(table.remove(wire,1))
local old_reply=table.remove(wire,1)
connect(client,cave,migrated)
deliver(old_reply)
assert(not client.binding.ready(),"old lifecycle reply cannot initialize the new session")
deliver(old_write) -- delivered to the new server owner; its old entity token must fail.
drain()
assert(client.binding.get()=="mouse:1005" and not client.binding.pending())
assert(migrated.components.nw_castbinding.revision==3)
-- A stale revision cannot overwrite a newer accepted value.
local c=migrated.components.nw_castbinding
assert(c:Set("key:109",3))
assert(client.binding.set("key:110"));drain()
assert(c:Get()=="key:109" and client.binding.get()=="key:109" and not client.binding.pending())
-- Lost write acknowledgements query state after timeout; never replay writes.
assert(client.binding.set("key:111"))
deliver(table.remove(wire,1));wire={}
assert(c:Get()=="key:111")
advance(client,C.request_timeout)
for _,e in ipairs(wire) do assert(e.name=="cast_binding_query") end
drain()
assert(client.binding.get()=="key:111" and not client.binding.pending())
local back=player(root,"user",c:OnSave());advance(root,0)
connect(client,root,back);drain()
assert(client.binding.get()=="key:111" and client.binding.get_default()=="mouse:1002")
-- Lower revision snapshots and foreign tokens must not roll current state back.
client.binding.query();deliver(table.remove(wire,1))
local reply=table.remove(wire,1)
reply.args[3]=0;reply.args[5]="mouse:1001";deliver(reply)
assert(client.binding.get()=="key:111")
reply.args[2]="foreign";reply.args[3]=100;deliver(reply)
assert(client.binding.get()=="key:111")
-- A truly separate save starts with the default, despite the same userid.
local other=player(root,"user");advance(root,0)
connect(client,root,other)
wire={} -- Lose the initial query; activation retries still only read state.
advance(client,C.retry_delay)
for _,e in ipairs(wire) do assert(e.name=="cast_binding_query") end
drain()
assert(client.binding.get()=="mouse:1002" and client.binding.get_override()==nil)
-- Listen-server host uses the same protocol against its own server component.
local host=player(root,"host")
root.g.ThePlayer=host;root.link={node=root,player=host};clients.host=root
advance(root,0);drain()
assert(root.binding.ready() and root.binding.get()=="mouse:1002")
assert(root.binding.set("key:107"));drain()
assert(root.binding.get()=="key:107" and root.binding.get_override()=="key:107" and not root.binding.pending())
local invalid=Component({PushEvent=function() end})
invalid:OnLoad({version=C.version,default="invalid",override="key:107",revision=9})
assert(invalid:Get()==nil)
invalid:OnLoad({version=C.version,default="mouse:1002",override="invalid",revision=0/0})
assert(invalid:Get()=="mouse:1002" and invalid.revision==0)
assert(not invalid:Set("invalid",0) and not invalid:Set("key:107",9))
print("cast binding: player persistence/reroll, primary default and cave initialization, lifecycle/token/revision isolation, explicit edits/reset, migration roundtrip, timeout reconciliation and invalid save/RPC rejection")
