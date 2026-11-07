-- Independent client tool: no network entities, damage, or save data.
local G = GLOBAL
local root = MODROOT
local state = {entities={}, banks={}, elapsed=0, message="选择法术后点击开始"}
local choices = {spark=true,arrow=true,fire=true,frost=true,heavy=true,scatter=true,
    gust=true,slime=true,heal_bolt=true,land_hook=true,spore_ball=true,flint_lance=true,
    grow_orb=true,star_vortex=true,glass_disc=true,tri_electric=true,end_beam=true,
    soundwave=true,bee_swarm=true,fireflies=true,
    orange_bolt=true,fishingrod=true,oceanfishingrod=true,trident=true,farm_hoe=true,yoth_lance=true,
    crystal_mine=true,sleep_crystal=true,payload_egg=true,moon_fall=true,
    delay_seal=true,detonate=true,rain_cloud=true,storm_cloud=true,guard_ring=true,
    shock_ring=true,vortex=true,deer_decoy=true,vital_ring=true,spore_sentry=true}
local field_radius={crystal_mine=1.6,sleep_crystal=1.8,payload_egg=1,moon_fall=2,
    delay_seal=1,detonate=4,rain_cloud=2,storm_cloud=3,guard_ring=2.5,
    shock_ring=2,vortex=2.5,deer_decoy=3,vital_ring=3,spore_sentry=4}
local function read(path)
    local f = G.io.open(root..path,"rb")
    if not f then return end
    local text = f:read("*a"); f:close(); return text
end
local function clear()
    if state.tick then state.tick:Cancel(); state.tick=nil end
    for _,e in G.ipairs(state.entities) do
        if e._nw_tool_flight then state.modules.tools.detach(e,true) end
        if e:IsValid() then e:Remove() end
    end
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
    function world:ListenForEvent(event,fn,source)
        return G.TheWorld:ListenForEvent(event,fn,source)
    end
    function world:RemoveEventCallback(event,fn,source)
        return G.TheWorld:RemoveEventCallback(event,fn,source)
    end
    local function netvalue()
        local value=0
        return {value=function() return value end,set=function(_,n) value=n end,
            set_local=function(_,n) value=n end}
    end
    local env
    env=G.setmetatable({TheWorld=world,net_float=netvalue,net_tinybyte=netvalue,net_smallbyte=netvalue,net_ushortint=netvalue,
    CreateEntity=function()
        local e=G.CreateEntity();state.entities[#state.entities+1]=e;return e
    end,SpawnPrefab=function(name)
        -- Stage helpers may request an ending accent. Construct only a local
        -- visual anchor; the preview never creates the real network prefab.
        G.assert(name=="nw_field_stage_fx" or name=="nw_guard_stage_fx" or name=="nw_vital_stage_fx",
            "Unexpected preview prefab: "..name)
        local fx=env.CreateEntity()
        fx.entity:AddTransform();fx.entity:AddAnimState();fx.entity:SetCanSleep(false)
        fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
        local Stages=state.modules.fields
        local id=name=="nw_guard_stage_fx" and "guard_ring" or name=="nw_vital_stage_fx" and "vital_ring"
        if id then Stages.setup(fx,id);Stages.attach(fx,id)
        else
            fx.AnimState:SetBank(Stages.bank);fx.AnimState:SetBuild(Stages.bank)
            fx.AnimState:SetOrientation(G.ANIM_ORIENTATION.BillBoard)
        end
        function fx:SetStage(field,phase,size,radius,count,age,seed)
            Stages.effect_state(self,field,phase,size,radius,count,age,seed)
            self:DoTaskInTime(Stages.duration(field,phase),self.Remove)
        end
        return fx
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
    e._height={value=function() return 2 end}
    e._size={value=function() return state.size end}
    local x,_,z=G.ThePlayer.Transform:GetWorldPosition()
    local a=state.angle*G.DEGREES
    local dx,dz=G.math.cos(a),G.math.sin(a)
    e.Transform:SetPosition(x-6*dx,0,z-6*dz)
    e.Transform:SetRotation(-state.angle)
    if field_radius[state.id] then
        local id,Stages=state.id,state.modules.fields
        e.entity:AddAnimState()
        e.Transform:SetPosition(x+4*dx,0,z+4*dz)
        e.Transform:SetScale(state.size,state.size,state.size)
        local plant=id=="spore_sentry"
        if plant then
            e.AnimState:SetBank(Stages.bank);e.AnimState:SetBuild(Stages.bank)
            e.AnimState:SetOrientation(G.ANIM_ORIENTATION.BillBoard)
            e.AnimState:PlayAnimation("spore_grow")
            e.AnimState:PushAnimation("spore_idle",true)
        else
            Stages.setup(e,id);Stages.attach(e,id)
            Stages.start(e,id,{size_mult=state.size,radius=field_radius[id]*state.size})
            if id=="detonate" or id=="vortex" then Stages.pulse(e) end
        end
        -- Normal-life timelines mirror the actual gameplay event times. They
        -- only exercise the renderer; damage, healing and payloads never run.
        local timeline,duration={},3
        if id=="moon_fall" then timeline={{.56,"fall"}};duration=.8
        elseif id=="delay_seal" then duration=.75
        elseif id=="detonate" then duration=.22
        elseif id=="rain_cloud" then timeline={{.3,"pulse"},{1.8,"pulse"}};duration=3
        elseif id=="storm_cloud" then
            timeline={{.5,"warning"},{.8,"pulse"},{1.3,"warning"},{1.6,"pulse"},{2.1,"warning"},{2.4,"pulse"}};duration=2.55
        elseif id=="shock_ring" then timeline={{.85,"pulse"},{1.85,"pulse"}};duration=2
        elseif id=="guard_ring" then timeline={{.9,"guard"}};duration=2
        elseif id=="vital_ring" then timeline={{1,"pulse"},{2,"pulse"},{3,"pulse"}};duration=3.1
        elseif id=="vortex" then duration=.4
        elseif plant then timeline={{.6,"fire"},{1.4,"fire"},{2.2,"fire"}};duration=2.6 end
        local started,index,ended=G.GetTime(),1,false
        state.tick=G.TheWorld:DoPeriodicTask(G.FRAMES,function()
            local age=G.GetTime()-started
            if e:IsValid() then
                if id=="guard_ring" then
                    local px,py,pz=G.ThePlayer.Transform:GetWorldPosition()
                    e.Transform:SetPosition(px,py,pz)
                end
                while timeline[index] and age>=timeline[index][1] do
                    local phase=timeline[index][2];index=index+1
                    if phase=="fire" then
                        e.AnimState:PlayAnimation("spore_fire");e.AnimState:PushAnimation("spore_idle",true)
                    elseif phase=="guard" then Stages.guard(e,1)
                    else Stages[phase](e) end
                    if id=="storm_cloud" and phase=="pulse" then
                        local arc=state.env.CreateEntity()
                        arc.entity:AddTransform();arc.entity:SetCanSleep(false)
                        arc:AddTag("FX");arc:AddTag("NOCLICK");arc.persists=false
                        local ex,ey,ez=e.Transform:GetWorldPosition()
                        arc.Transform:SetPosition(ex,ey,ez)
                        local tx,ty,tz=G.ThePlayer.Transform:GetWorldPosition()
                        local function value(v) return {value=function() return v end} end
                        arc._dx=value(tx-ex);arc._dz=value(tz-ez)
                        arc._dy=value(state.modules.electric.target_height(G.ThePlayer)-ey)
                        arc._lift=value(2.2*state.size)
                        arc._contact=value(nil);arc._shockanim=value("")
                        state.modules.electric.attach(arc)
                        arc:DoTaskInTime(.23,arc.Remove)
                    end
                end
                if age>=duration and not ended then
                    ended=true
                    if plant then
                        e.AnimState:PlayAnimation("spore_wilt");e:DoTaskInTime(.3,e.Remove)
                    else Stages.finish(e);e:Remove() end
                end
            end
            if age>=duration+.5 then spawn() end
        end)
        return
    end
    if state.id=="end_beam" then
        -- Feed the production codec/renderer the same age-based snapshots as
        -- a real shot. This client-only anchor has no head or damage logic.
        local Path,Beam=state.modules.beam_path,state.modules.beam_visual
        local segments,packet,ended={},"",false
        local started=G.GetTime()
        local previous_x,previous_z=x-6*dx,z-6*dz
        local previous_distance,next_snapshot,index=0,started,0
        local ended_at
        e._beam_path={value=function() return packet end}
        e._beam_ended={value=function() return ended end}
        Beam.attach(e)
        state.tick=G.TheWorld:DoPeriodicTask(G.FRAMES,function()
            if not e:IsValid() then return end
            local now=G.GetTime()
            local distance=G.math.min(12,(now-started)*state.speed)
            local px,pz=x+(distance-6)*dx,z+(distance-6)*dz
            if distance>previous_distance then
                index=index+1
                segments[#segments+1]={id=index,born=now,x1=previous_x,z1=previous_z,
                    x2=px,z2=pz,radius=.12*state.size}
                previous_x,previous_z,previous_distance=px,pz,distance
            end
            e.Transform:SetPosition(px,0,pz)
            for i=#segments,1,-1 do
                if now-segments[i].born>=Path.lifetime then G.table.remove(segments,i) end
            end
            local just_ended=not ended and distance>=12
            if just_ended then ended=true;ended_at=now end
            if just_ended or now>=next_snapshot then
                packet=Path.encode(segments,now)
                Beam.refresh(e)
                next_snapshot=now+Path.snapshot_interval
            end
            -- Let the oldest-to-newest narrowing finish before the next cast.
            if ended_at and now>=ended_at+Path.lifetime+G.FRAMES then spawn() end
        end)
        return
    end
    local v=state.env.CreateEntity()
    v.entity:AddTransform();v.entity:AddAnimState();v.entity:SetParent(e.entity)
    v:AddTag("FX");v:AddTag("NOCLICK");v.persists=false
    v.Transform:SetPosition(0,e._height:value(),0)
    v.AnimState:SetLightOverride(1)
    v.AnimState:SetOrientation(G.ANIM_ORIENTATION.BillBoard)
    e._visual=v
    if state.id=="spark" then
        v.AnimState:SetBank(state.banks.spark);v.AnimState:SetBuild(state.banks.spark)
        v.AnimState:PlayAnimation("head",true)
        v.Transform:SetScale(state.size,state.size,state.size)
        state.modules.trail.attach(e)
    elseif state.modules.elemental.supports(state.id) then
        state.modules.elemental.attach(e,state.id)
        v.Transform:SetScale(state.size,state.size,state.size)
    elseif state.modules.tools.supports(state.id) then
        state.modules.tools.attach(e,state.id)
        v.Transform:SetScale(state.size,state.size,state.size)
    else
        state.modules.flight.attach(e,state.id)
        local scale=1.6*state.size
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
    local revision,spark,world,elemental,tools,fields,electric
    if manifest then
        revision,spark,world,elemental,tools,fields,electric=manifest:match("^(r%d+) ([%w_]+) ([%w_]+) ([%w_]+) ([%w_]+) ([%w_]+) ([%w_]+)%s*$")
    end
    if not revision then state.message="等待资源：请运行 preview.cmd";return end
    if revision==state.revision and not force then return end
    clear();unload()
    local prefab="nw_preview_assets_"..revision
    -- Full mod paths avoid the normal prefab search-path cache.
    G.TheSim:RegisterPrefab(prefab,{
        G.Asset("ANIM",root.."live/"..revision.."/anim/"..spark..".zip"),
        G.Asset("ANIM",root.."live/"..revision.."/anim/"..world..".zip"),
        G.Asset("ANIM",root.."live/"..revision.."/anim/"..elemental..".zip"),
        G.Asset("ANIM",root.."live/"..revision.."/anim/"..tools..".zip"),
        G.Asset("ANIM",root.."live/"..revision.."/anim/"..fields..".zip"),
        G.Asset("ANIM",root.."live/"..revision.."/anim/"..electric..".zip"),
        G.Asset("ANIM","anim/meteor_shadow.zip"),G.Asset("ANIM","anim/shock_fx.zip"),
        G.Asset("ANIM","anim/wagdrone_laserwire_fx.zip")},{})
    state.prefab=prefab
    G.TheSim:LoadPrefabs({prefab})
    state.banks={spark=spark,world=world,elemental=elemental,tools=tools,fields=fields,electric=electric};state.revision=revision
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
