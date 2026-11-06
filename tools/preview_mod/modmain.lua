-- Independent client tool: no network entities, damage, or save data.
local G = GLOBAL
local root = MODROOT
local state = {entities={}, banks={}, elapsed=0, message="选择法术后点击开始"}
local choices = {spark=true,arrow=true,fire=true,frost=true,heavy=true,scatter=true,
    gust=true,slime=true,heal_bolt=true,land_hook=true,spore_ball=true,flint_lance=true,
    grow_orb=true,star_vortex=true,glass_disc=true,tri_electric=true,end_beam=true,
    soundwave=true,bee_swarm=true,fireflies=true}
local scales = {arrow=1.4,fire=1.5,frost=1.5,heavy=2,scatter=1.4}
local function read(path)
    local f = G.io.open(root..path,"rb")
    if not f then return end
    local text = f:read("*a"); f:close(); return text
end
local function clear()
    if state.tick then state.tick:Cancel(); state.tick=nil end
    for _,e in G.ipairs(state.entities) do if e:IsValid() then e:Remove() end end
    state.entities={}
    -- Loaded modules own periodic tasks; remove them before dropping the environment.
    if state.clock then
        for _,t in G.ipairs(state.clock) do t:Cancel() end
    end
    state.clock={}
end
local function unload()
    if state.prefab then
        G.TheSim:UnloadPrefabs({state.prefab})
        G.TheSim:UnregisterPrefabs({state.prefab})
        state.prefab=nil
    end
end
local function modules(revision)
    local source=G.assert(read("live/"..revision.."/visual.lua"),"Missing preview visual.lua")
    local clock={};state.clock=clock
    local world={}
    function world:DoPeriodicTask(period,fn,delay)
        local t=G.TheWorld:DoPeriodicTask(period,function() fn(world) end,delay)
        clock[#clock+1]=t;return t
    end
    local env=G.setmetatable({TheWorld=world,CreateEntity=function()
        local e=G.CreateEntity();state.entities[#state.entities+1]=e;return e
    end,require=function(name)
        G.assert(name=="nw/arsenal","Unexpected preview dependency: "..name)
        return {notes={soundwave=true}}
    end},{__index=G})
    local fn=G.assert(G.loadstring(source,"preview_visual"));G.setfenv(fn,env)
    return fn(),env
end
local function spawn()
    if not state.id or not G.ThePlayer then return end
    clear()
    state.modules,state.env=modules(state.revision)
    local e=state.env.CreateEntity()
    e.entity:AddTransform();e.entity:SetCanSleep(false)
    e:AddTag("FX");e:AddTag("NOCLICK");e.persists=false
    local v=state.env.CreateEntity()
    v.entity:AddTransform();v.entity:AddAnimState();v.entity:SetParent(e.entity)
    v:AddTag("FX");v:AddTag("NOCLICK");v.persists=false
    v.Transform:SetPosition(0,1.4,0)
    v.AnimState:SetLightOverride(1)
    v.AnimState:SetOrientation(G.ANIM_ORIENTATION.BillBoard)
    e._visual=v
    e._height={value=function() return 1.4 end}
    e._size={value=function() return state.size end}
    local x,_,z=G.ThePlayer.Transform:GetWorldPosition()
    local a=state.angle*G.DEGREES
    local dx,dz=G.math.cos(a),G.math.sin(a)
    e.Transform:SetPosition(x-6*dx,0,z-6*dz)
    e.Transform:SetRotation(-state.angle)
    if state.id=="spark" then
        v.AnimState:SetBank(state.banks.spark);v.AnimState:SetBuild(state.banks.spark)
        v.AnimState:PlayAnimation("head",true)
        v.Transform:SetScale(state.size,state.size,state.size)
        state.modules.trail.attach(e)
    else
        state.modules.flight.attach(e,state.id)
        local scale=(scales[state.id] or 1.6)*state.size
        v.Transform:SetScale(scale,scale,scale)
    end
    local started=G.GetTime()
    state.tick=G.TheWorld:DoPeriodicTask(G.FRAMES,function()
        local distance=(G.GetTime()-started)*state.speed
        if distance>12 then
            -- Clear old tails on the next cycle, avoiding teleport streaks.
            spawn()
        elseif e:IsValid() then
            e.Transform:SetPosition(x+(distance-6)*dx,0,z+(distance-6)*dz)
        end
    end)
end
local function refresh(force)
    local manifest=read("live/current.txt")
    local revision,spark,world
    if manifest then revision,spark,world=manifest:match("^(r%d+) ([%w_]+) ([%w_]+)%s*$") end
    if not revision then state.message="等待资源：请运行 preview.cmd";return end
    if revision==state.revision and not force then return end
    clear();unload()
    local prefab="nw_preview_assets_"..revision
    -- Full mod paths avoid the normal prefab search-path cache.
    G.TheSim:RegisterPrefab(prefab,{
        G.Asset("ANIM",root.."live/"..revision.."/anim/"..spark..".zip"),
        G.Asset("ANIM",root.."live/"..revision.."/anim/"..world..".zip")},{})
    state.prefab=prefab
    G.TheSim:LoadPrefabs({prefab})
    state.banks={spark=spark,world=world};state.revision=revision
    spawn()
    state.message="已加载 "..revision
    print("[NW preview] loaded "..revision)
end
local function fail(message,err)
    state.id=nil
    if state.poll then state.poll:Cancel();state.poll=nil end
    clear();unload();state.revision=nil
    state.message=message
    print("[NW preview] ERROR: "..G.tostring(err))
end
local function guarded_refresh(force)
    local ok,err=G.pcall(refresh,force)
    if not ok then
        fail("加载失败，请查看 client_log.txt",err)
    end
end
local function start(id,speed,angle,size)
    if not G.TheWorld or not G.ThePlayer then print("[NW preview] Enter a world first.");return end
    id=id or "spark"
    if not choices[id] then print("[NW preview] Unsupported spell: "..G.tostring(id));return end
    state.id=id;state.speed=G.math.max(.1,G.math.min(60,G.tonumber(speed) or 20))
    state.angle=G.tonumber(angle) or 0
    state.size=G.math.max(1,G.math.min(5,G.tonumber(size) or 1))
    if state.poll then state.poll:Cancel() end
    state.poll=G.TheWorld:DoPeriodicTask(.5,function() guarded_refresh(false) end)
    if state.revision then spawn() else guarded_refresh(false) end
    print("[NW preview] "..id.."; watching live/current.txt. nw_preview_stop() to stop.")
end
G.rawset(G,"nw_preview",start)
G.rawset(G,"nw_preview_refresh",function() guarded_refresh(true) end)
G.rawset(G,"nw_preview_stop",function()
    state.id=nil
    if state.poll then state.poll:Cancel();state.poll=nil end
    clear();unload();state.revision=nil
    state.message="已停止，预览实体已清理"
    print("[NW preview] stopped")
end)

-- HUD widget stays in the world, so opening the panel never pauses playback.
AddClassPostConstruct("widgets/controls",function(controls)
    local api={
        start=function(...) 
            local ok,err=G.pcall(start,...)
            if not ok then
                fail("启动失败，请查看 client_log.txt",err)
            end
        end,
        stop=G.nw_preview_stop,
        refresh=G.nw_preview_refresh,
        status=function() return state.message,state.id~=nil,state.revision end,
    }
    controls.nw_live_preview=controls:AddChild(G.require("widgets/nw_live_preview_panel")(api))
    controls.inst:ListenForEvent("onremove",function() G.nw_preview_stop() end)
end)
