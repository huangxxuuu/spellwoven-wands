local C=require("nw/constants/dark_fog").boss
local M = {}
local REASON = "nw_fog_boss"
local Wait = require("nw/dark_fog_boss_wait")
local Extra = require("nw/dark_fog_boss_extra")
local specs = {
    deerclops = { graph = "deerclops", first = "attack", states = { attack = true }, links = {} },
    bearger = { graph = "bearger", first = "pound", ring = true, timer = "GroundPound", native_entry = true,
        fallback = { first = "attack", sector = true }, states = { pound = true, bi = true, attack = true },
        links = { pound = { bi = true }, attack = { bi = true }, bi = { pound = true, attack = true } } },
    moose = { graph = "moose", first = "disarm", disarm = true, fog_radius = C.moose_radius, native_entry = true, fog_cooldown = C.moose_cooldown,
        states = { disarm = true }, links = {} },
    dragonfly = { graph = "dragonfly", first = "pound_pre", ring = true, timer = "groundpound_cd",
        fallback = { first = "attack", single = true }, states = { pound_pre = true, pound = true, pound_post = true, attack = true },
        links = { pound_pre = { pound = true }, pound = { pound_post = true } } },
    toadstool = { graph = "toadstool", first = "pound_pre", ring = true, timer = "pound_cd",
        fallback = { first = "mushroombomb", bomb = true, timer = "mushroombomb_cd" },
        states = { pound_pre = true, pound = true, pound_pst = true, mushroombomb = true },
        links = { pound_pre = { pound = true }, pound = { pound_pst = true } } },
    minotaur = { graph = "minotaur", first = "stomp", ring = true, timer = "stomptimer",
        fallback = { first = "attack", single = true }, states = { stomp = true, attack = true }, links = {} },
    alterguardian_phase1 = { graph = "alterguardian_phase1", first = "tantrum_pre", circle = true,
        states = { tantrum_pre = true, tantrum = true, tantrum_pst = true },
        links = { tantrum_pre = { tantrum = true }, tantrum = { tantrum = true, tantrum_pst = true } } },
    alterguardian_phase3 = { graph = "alterguardian_phase3", first = "atk_stab", area = true,
        states = { atk_stab = true }, links = {} },
    eyeofterror = { graph = "eyeofterror", first = "chomp", circle = true, fog_cooldown = C.eye_cooldown,
        available = function(inst) return inst.sg.mem and inst.sg.mem.transformed == true end,
        states = { chomp = true }, links = {} },
}
specs.toadstool_dark = specs.toadstool
specs.twinofterror1 = specs.eyeofterror
specs.twinofterror2 = specs.eyeofterror
Extra.add_specs(specs)
Wait.target_range = function(inst,target)
    local spec=specs[inst.prefab]
    if spec and spec.target_in_range then return spec.target_in_range(inst,target) end
end
local graphs = setmetatable({}, { __mode = "k" })
local batches = setmetatable({}, { __mode = "k" })
local ice_batches = setmetatable({}, { __mode = "k" })
local installed = false

local function warn(name, reason)
    print("[nw_dark_fog_boss] "..name.." disabled: "..tostring(reason))
end

local function ready(token)
    if not (token and token.world and token.world.ismastersim and token.world == TheWorld) then return false end
    local Fog=require("nw/dark_fog")
    if token.pending_coverage then
        local owner=token.owner
        if not (owner and owner:IsValid() and Fog.contains(token.world,owner)) then return false end
        token.pending_coverage=nil
    end
    return true
end
local function notify(token, x, z, outer, inner)
    if ready(token) then require("nw/dark_fog").disperse_circle(token.world, x, z, outer, inner) end
end

local function finish(inst, token)
    if inst._nw_fog_boss_cast ~= token then return end
    inst._nw_fog_boss_cast = nil
    if token.brain_owned then
        token.brain_owned = nil
        inst:RestartBrain(REASON)
    end
end

local function begin(inst, spec, now, brain_owned, move)
    local token=inst._nw_fog_boss_pending
    if not token or token.spec~=spec then token={spec=spec,move=move or spec,world=TheWorld} end
    token.pending_coverage=nil
    token.brain_owned=brain_owned
    inst._nw_fog_boss_pending=nil
    if token.move.fog_cooldown then
        inst._nw_fog_boss_moves = inst._nw_fog_boss_moves or {}
        inst._nw_fog_boss_moves[token.move] = now + token.move.fog_cooldown
    end
    inst._nw_fog_boss_cast = token
    if brain_owned then inst:StopBrain(REASON);Wait.stop_chase(inst);Wait.prune_target(inst) end
    if not inst._nw_fog_boss_cleanup then
        inst._nw_fog_boss_cleanup = true
        inst:ListenForEvent("onremove", function(owner)
            owner._nw_fog_boss_cast = nil
            owner._nw_fog_boss_covered = nil
        end)
        inst:ListenForEvent("entitysleep", function(owner)
            M.leave(owner)
            local cast = owner._nw_fog_boss_cast
            if cast then finish(owner, cast) end
        end)
    end
    return token
end

local function state_move(spec, name)
    if name == "bi" then return nil end
    if spec.fallback and (name == spec.fallback.first or name:find("attack_combo", 1, true)
        or spec.fallback.dash and (name=="dash_loop" or name=="dash_pst")) then return spec.fallback end
    return spec.states[name] and spec or nil
end

local function active_token(inst, state)
    local token = inst._nw_fog_boss_cast
    local sg, spec = inst.sg, specs[inst.prefab]
    if not (sg and spec and (state == nil or sg.currentstate.name == state)) then return nil end
    if not token and M.supports(inst) and TheWorld and TheWorld.ismastersim
        and require("nw/dark_fog").contains(TheWorld, inst) then
        local move = state_move(spec, sg.currentstate.name)
        if move then
            token = begin(inst, spec, GetTime(), nil, move)
            sg.statemem._nw_fog_boss_token = token
        end
    end
    return token and token.spec == spec and sg.statemem._nw_fog_boss_token == token and token or nil
end

local function dispatch_token(inst, state)
    local token=active_token(inst,state)
    if token then return token end
    local sg,spec=inst.sg,specs[inst.prefab]
    if not (spec and sg and (not state or sg.currentstate.name==state)
        and TheWorld and TheWorld.ismastersim and M.supports(inst)) then return nil end
    local move=state_move(spec,sg.currentstate.name)
    if not move then return nil end
    local pending=inst._nw_fog_boss_pending
    if not pending or pending.spec~=spec then
        pending={spec=spec,move=move,world=TheWorld,owner=inst,pending_coverage=true}
        inst._nw_fog_boss_pending=pending
    end
    sg.statemem._nw_fog_boss_pending=pending
    return pending
end

local function install_groundpounder(self)
    if self._nw_fog_boss_hooked then return end
    if type(self.GroundPound) ~= "function" or type(self.DestroyRing) ~= "function" then
        warn("groundpounder", "missing GroundPound/DestroyRing")
        return
    end
    self._nw_fog_boss_hooked = true
    local groundpound, destroy = self.GroundPound, self.DestroyRing
    self.GroundPound = function(component, pt, ents_hit, ...)
        local token = dispatch_token(component.inst)
        if token and token.move.ring and not component.usePointMode then
            ents_hit = ents_hit or {}
            batches[ents_hit] = token
        end
        return groundpound(component, pt, ents_hit, ...)
    end
    self.DestroyRing = function(component, pt, radius, points, breakobjects, dodamage,
        pushplatforms, pushinventoryitems, spawnfx, ents_hit, platforms_hit, ...)
        local token = ents_hit and batches[ents_hit] or nil
        local outer, inner = radius + component.ringWidth, math.max(0, radius - component.ringWidth)
        local result = destroy(component, pt, radius, points, breakobjects, dodamage,
            pushplatforms, pushinventoryitems, spawnfx, ents_hit, platforms_hit, ...)
        if token and dodamage then notify(token, pt.x, pt.z, outer, inner) end
        return result
    end
end

local function install_combat(self)
    if type(self.SetTarget) == "function" and not self._nw_fog_boss_target_hooked then
        self._nw_fog_boss_target_hooked = true
        local settarget = self.SetTarget
        self.SetTarget = function(component, target, ...)
            local inst = component.inst
            local cast = inst._nw_fog_boss_cast
            if target and (inst._nw_fog_boss_wait or cast and cast.brain_owned)
                and not Wait.target_in_range(inst, target) then return end
            return settarget(component, target, ...)
        end
    end
    if self.inst and type(self.DoAttack) == "function" and not self._nw_fog_boss_single_hooked then
        self._nw_fog_boss_single_hooked = true
        local attack = self.DoAttack
        self.inst:ListenForEvent("onattackother", function(_, data)
            local pending = self._nw_fog_boss_contact
            if pending and data and data.target == pending.target then
                local x, _, z = data.target.Transform:GetWorldPosition()
                pending.hit = { x = x, z = z, radius = data.target:GetPhysicsRadius(0) }
            end
        end)
        self.DoAttack = function(component, target, ...)
            local token = active_token(component.inst)
            if not (token and token.move.single) then return attack(component, target, ...) end
            local previous = component._nw_fog_boss_contact
            local pending = { token = token, target = target or component.target }
            component._nw_fog_boss_contact = pending
            local ok, result = pcall(attack, component, target, ...)
            component._nw_fog_boss_contact = previous
            if not ok then error(result, 0) end
            if pending.hit then notify(token, pending.hit.x, pending.hit.z, pending.hit.radius) end
            return result
        end
    end
    if self._nw_fog_boss_area_hooked or type(self.DoAreaAttack) ~= "function" then return end
    self._nw_fog_boss_area_hooked = true
    local original = self.DoAreaAttack
    self.DoAreaAttack = function(component, target, radius, weapon, validfn, stimuli, excludetags, onlyontarget, ...)
        local token = active_token(component.inst)
        token = token and token.spec.area and not onlyontarget and validfn == nil and token or nil
        local x, y, z
        if token and target and target.Transform then x, y, z = target.Transform:GetWorldPosition() end
        local result = original(component, target, radius, weapon, validfn, stimuli, excludetags, onlyontarget, ...)
        if token and x then notify(token, x, z, radius) end
        return result
    end
end

local function upvalue(fn, wanted)
    if type(fn) ~= "function" then return nil end
    for i = 1, C.signature.max_upvalues do
        local name, value = debug.getupvalue(fn, i)
        if name == nil then break end
        if name == wanted then return value, i end
    end
end

local function native_deer_fn(fn)
    if type(fn) ~= "function" then return false end
    local info = debug.getinfo(fn, "S")
    return info and info.what == "Lua" and
        string.find(string.gsub(info.source, "\\", "/"), "stategraphs/SGdeerclops.lua", 1, true) ~= nil
end

local function install_ice(graph)
    if not (debug and debug.getupvalue and debug.setupvalue and debug.getinfo) then
        return false, "debug upvalue API unavailable"
    end
    local event, spawn, spawn_index
    for _, e in ipairs(graph.states.attack.timeline or {}) do
        local value, index = upvalue(e.fn, "SpawnIceFx")
        if value ~= nil then
            if event ~= nil then return false, "ambiguous SpawnIceFx timeline" end
            event, spawn, spawn_index = e, value, index
        end
    end
    if not event or not native_deer_fn(spawn) then return false, "native SpawnIceFx not found" end
    local spike, spike_index = upvalue(spawn, "DoSpawnIceSpike")
    local aoe, aoe_index = upvalue(spike, "DoIceSpikeAOE")
    local radius = upvalue(aoe, "ICESPIKE_RADIUS")
    local spawn_time = upvalue(spawn, "ICESPAWNTIME")
    if not native_deer_fn(spike) or not native_deer_fn(aoe) or radius ~= C.signature.ice_radius or spawn_time ~= C.signature.ice_spawn_time then
        return false, "ice closure/radius/timing signature changed"
    end
    debug.setupvalue(spike, aoe_index, function(inst, target, x, z, data)
        local token = ice_batches[data]
        local result = aoe(inst, target, x, z, data)
        if token then notify(token, x, z, radius) end
        return result
    end)
    debug.setupvalue(event.fn, spawn_index, function(inst, target)
        local token = dispatch_token(inst, "attack")
        if not token then return spawn(inst, target) end
        local previous = upvalue(spawn, "DoSpawnIceSpike")
        debug.setupvalue(spawn, spike_index, function(owner, original_target, rot, info, data, ...)
            ice_batches[data] = token
            return previous(owner, original_target, rot, info, data, ...)
        end)
        local ok, err = pcall(spawn, inst, target)
        debug.setupvalue(spawn, spike_index, previous)
        if not ok then error(err, 0) end
    end)
    return true
end

local function install_circle(graph, spec)
    if not (debug and debug.getupvalue and debug.setupvalue and debug.getinfo) then
        return false, "debug upvalue API unavailable"
    end
    local sites = {}
    for name in pairs(spec.states) do
        for _, event in ipairs(graph.states[name].timeline or {}) do
            local fn, index = upvalue(event.fn, "DoAOEAttack")
            if fn then
                local info = type(fn) == "function" and debug.getinfo(fn, "S")
                if not (info and string.find(string.gsub(info.source, "\\", "/"),
                    "stategraphs/SG"..spec.graph..".lua", 1, true)) then
                    return false, "native DoAOEAttack closure changed"
                end
                sites[#sites + 1] = { owner = event.fn, index = index, original = fn }
            end
        end
    end
    if #sites == 0 then return false, "native DoAOEAttack timeline not found" end
    local wrappers = {}
    for _, site in ipairs(sites) do
        local original = site.original
        if not wrappers[original] then
            wrappers[original] = function(inst, radius, ...)
                local token = active_token(inst)
                local x, _, z = inst.Transform:GetWorldPosition()
                local result = original(inst, radius, ...)
                if token and token.spec == spec then notify(token, x, z, radius) end
                return result
            end
        end
        debug.setupvalue(site.owner, site.index, wrappers[original])
    end
    return true
end

local function install_disarm(graph, spec)
    if not (debug and debug.getupvalue and debug.setupvalue and debug.getinfo) then
        return false, "debug upvalue API unavailable"
    end
    local site, original, index
    for _, event in ipairs(graph.states.disarm.timeline or {}) do
        local fn, i = upvalue(event.fn, "DisarmTarget")
        if fn then
            local info = type(fn) == "function" and debug.getinfo(fn, "S")
            if site or not (info and string.find(string.gsub(info.source, "\\", "/"),
                "stategraphs/SGmoose.lua", 1, true)) then
                return false, "native DisarmTarget closure changed"
            end
            site, original, index = event.fn, fn, i
        end
    end
    if not site then return false, "native DisarmTarget timeline not found" end
    debug.setupvalue(site, index, function(inst, target, ...)
        local token = active_token(inst, "disarm")
        local x, _, z = inst.Transform:GetWorldPosition()
        local combat=inst.components.combat
        if token and target and (not target:IsValid() or not combat.CalcAttackRangeSq
            or target:GetDistanceSqToPoint(x,0,z)>combat:CalcAttackRangeSq(target)) then
            target=nil
        end
        local result = original(inst, target, ...)
        if token and token.spec == spec then notify(token, x, z, spec.fog_radius) end
        return result
    end)
    return true
end

local function install_sector(graph)
    if not (debug and debug.getupvalue and debug.setupvalue and debug.getinfo) then return false, "debug API unavailable" end
    local sites, original = {}, nil
    for _, event in ipairs(graph.states.attack.timeline or {}) do
        local fn, index = upvalue(event.fn, "DoArcAttack")
        if fn then
            local info = type(fn) == "function" and debug.getinfo(fn, "S")
            if not (info and string.find(string.gsub(info.source,"\\","/"),"stategraphs/SGbearger.lua",1,true))
                or original and original ~= fn or upvalue(fn,"ARC") ~= math.pi / 2 then
                return false, "native DoArcAttack geometry changed"
            end
            original = fn;sites[#sites+1] = {fn=event.fn,index=index}
        end
    end
    if #sites ~= C.signature.sector_timeline_count then return false, "native DoArcAttack timelines changed" end
    local wrapper = function(inst, dist, radius, ...)
        local token = active_token(inst, "attack")
        local x, _, z = inst.Transform:GetWorldPosition()
        local rotation = inst.Transform:GetRotation()
        local radians = rotation * math.pi / 180
        x,z=x+dist*math.cos(radians),z-dist*math.sin(radians)
        local result = original(inst,dist,radius,...)
        if token and token.move.sector then
            require("nw/dark_fog").disperse_sector(token.world,x,z,radius,rotation,C.sector_arc)
        end
        return result
    end
    for _,site in ipairs(sites) do debug.setupvalue(site.fn,site.index,wrapper) end
    return true
end

local launching_token, landing_token
local bomb_hooks=setmetatable({}, {__mode="k"})
local function native_source(fn, file)
    local info=type(fn)=="function" and debug.getinfo(fn,"S")
    return info and string.find(string.gsub(info.source,"\\","/"),file,1,true)
end
local function install_toad_bombs(inst)
    if not (TheWorld and TheWorld.ismastersim and debug and debug.getupvalue and debug.setupvalue and debug.getinfo) then return end
    local original=inst.DoMushroomBomb
    local spawn,index=upvalue(original,"SpawnMushroomBombProjectile")
    local recursive,recursive_index=upvalue(spawn,"SpawnMushroomBombProjectile")
    if not native_source(original,"prefabs/toadstool.lua") or not native_source(spawn,"prefabs/toadstool.lua") or recursive~=spawn then
        warn(inst.prefab,"native mushroom launch chain changed");return
    end
    inst._nw_fog_boss_bombs_ready=true
    inst.DoMushroomBomb=function(owner,...)
        local token=dispatch_token(owner,"mushroombomb")
        if not (token and token.move.bomb) then return original(owner,...) end
        local launch
        launch=function(boss,targets,...)
            local old_scope=launching_token
            local previous=upvalue(spawn,"SpawnMushroomBombProjectile")
            launching_token=token
            debug.setupvalue(spawn,recursive_index,launch)
            local ok,result=pcall(spawn,boss,targets,...)
            debug.setupvalue(spawn,recursive_index,previous)
            launching_token=old_scope
            if not ok then error(result,0) end
            return result
        end
        local previous=upvalue(original,"SpawnMushroomBombProjectile")
        debug.setupvalue(original,index,launch)
        local ok,result=pcall(original,owner,...)
        debug.setupvalue(original,index,previous)
        if not ok then error(result,0) end
        return result
    end
end
local function install_bomb_projectile(inst)
    if not (TheWorld and TheWorld.ismastersim) then return end
    local cp=inst.components.complexprojectile
    if not (cp and type(cp.Launch)=="function" and type(cp.onhitfn)=="function") then return end
    local launch,hit=cp.Launch,cp.onhitfn
    cp.Launch=function(component,...)
        inst._nw_fog_boss_bomb_token=launching_token
        return launch(component,...)
    end
    cp.onhitfn=function(projectile,...)
        local previous=landing_token
        landing_token=projectile._nw_fog_boss_bomb_token
        local ok,result=pcall(hit,projectile,...)
        landing_token=previous
        if not ok then error(result,0) end
        return result
    end
end
local function install_bomb(inst)
    if not (TheWorld and TheWorld.ismastersim and debug and debug.getupvalue and debug.setupvalue and debug.getinfo) then return end
    local grow=upvalue(inst.OnLoad,"Grow")
    if not bomb_hooks[grow] then
        local explode,index=upvalue(grow,"Explode")
        if not native_source(grow,"prefabs/mushroombomb.lua") or not native_source(explode,"prefabs/mushroombomb.lua")
            or upvalue(inst.OnLoad,"Explode")~=explode then
            warn(inst.prefab,"native mushroom explosion chain changed");return
        end
        debug.setupvalue(grow,index,function(bomb,...)
            local token=bomb._nw_fog_boss_bomb_token
            local x,_,z=bomb.Transform:GetWorldPosition()
            local result=explode(bomb,...)
            if token then notify(token,x,z,TUNING.TOADSTOOL_MUSHROOMBOMB_RADIUS) end
            return result
        end)
        bomb_hooks[grow]=true
    end
    inst._nw_fog_boss_bomb_token=landing_token
end

local function cooling(inst, timer)
    return timer and inst.components.timer and inst.components.timer:TimerExists(timer)
end

local function original_target(inst, entering, move)
    local combat = inst.components.combat
    local target = combat and combat.target
    if not (target and target:IsValid() and combat.CanTarget and combat:CanTarget(target)) then return false end
    if move and move.target_in_range then
        if not move.target_in_range(inst,target) then return false end
        return entering or (not combat.IsValidTarget or combat:IsValidTarget(target))
            and combat.canattack~=false and not combat:InCooldown()
            and (not inst.sg or not inst.sg:HasStateTag("busy") or inst.sg:HasStateTag("hit"))
    end
    if not entering then return combat.CanAttack and combat:CanAttack(target) end
    return Wait.target_in_range(inst,target)
end

function M.select(inst, entering)
    local spec = specs[inst.prefab]
    if not spec then return nil, false end
    local fallback, combat = spec.fallback, inst.components.combat
    local blocked=false
    for _,move in ipairs({spec,fallback}) do
        local eligible=(not move.available or move.available(inst))
            and (not move.bomb or inst._nw_fog_boss_bombs_ready)
            and (not move.single or combat and combat._nw_fog_boss_single_hooked)
        if eligible and (move.single or move.requires_target) then eligible=original_target(inst,true,move) end
        if eligible then
            if GetTime() < ((inst._nw_fog_boss_moves or {})[move] or 0) or cooling(inst,move.timer) or (not move.timer and inst.prefab~="moose" and combat and combat:InCooldown())
                or move==fallback and combat and combat:InCooldown() then
                blocked=true
            elseif not (move.single or move.requires_target) or entering or original_target(inst,false,move) then
                return move,false
            end
        end
    end
    return nil, blocked
end

local function install_graph(name, graph)
    if not graph or graphs[graph] then return end
    local accepted, states = {}, {}
    for prefab,spec in pairs(specs) do
        if spec.graph==name and not accepted[spec] then
            local valid=true
            for state in pairs(spec.states) do
                if not(graph.states[state] and type(graph.states[state].onenter)=="function") then
                    warn(prefab,"missing state "..state);valid=false;break
                end
            end
            if valid then accepted[spec]=true end
        end
    end
    if not next(accepted) then return end
    local representative
    for spec in pairs(accepted) do representative=spec;break end
    local ok,reason=true,nil
    if name=="deerclops" then ok,reason=install_ice(graph)
    elseif representative.circle then ok,reason=install_circle(graph,representative)
    elseif representative.disarm then ok,reason=install_disarm(graph,representative) end
    if not ok then warn(name,reason);return end
    if name=="bearger" then
        ok,reason=install_sector(graph)
        if not ok then warn(name,reason);return end
    end
    if name~="bearger" or accepted[specs.mutatedbearger] then
        ok,reason=Extra.install_graph(name,graph,{upvalue=upvalue,active=active_token,notify=notify,native_source=native_source})
        if not ok then
            if name=="bearger" then accepted[specs.mutatedbearger]=nil;warn("mutatedbearger",reason)
            else warn(name,reason);return end
        end
    end
    for spec in pairs(accepted) do for state in pairs(spec.states) do states[state]=true end end
    for state_name in pairs(states) do
        local state=graph.states[state_name]
        local enter,leave=state.onenter,state.onexit
        local name_here=state_name
        state.onenter=function(inst,...)
            local spec=specs[inst.prefab]
            local token=inst._nw_fog_boss_cast
            if spec and accepted[spec] and spec.states[name_here] then
                local native_move=state_move(spec,name_here)
                if not token and native_move and TheWorld and TheWorld.ismastersim and M.supports(inst)
                    and require("nw/dark_fog").contains(TheWorld,inst) then
                    token=begin(inst,spec,GetTime(),nil,native_move)
                end
                if token and token.spec==spec then inst.sg.statemem._nw_fog_boss_token=token end
                if inst._nw_fog_boss_pending then inst.sg.statemem._nw_fog_boss_pending=inst._nw_fog_boss_pending end
            end
            return enter(inst,...)
        end
        state.onexit=function(inst,nextstate,...)
            local pending=inst.sg.statemem._nw_fog_boss_pending
            if pending and not(pending.spec.links[name_here] and pending.spec.links[name_here][nextstate])
                and inst._nw_fog_boss_pending==pending then inst._nw_fog_boss_pending=nil end
            local token=inst.sg.statemem._nw_fog_boss_token
            if token and not(token.spec.links[name_here] and token.spec.links[name_here][nextstate]) then finish(inst,token) end
            if leave then return leave(inst,nextstate,...) end
        end
    end
    graphs[graph]=accepted
end

function M.install(AddComponentPostInit, AddStategraphPostInit, AddPrefabPostInit)
    if installed then return end
    installed = true
    AddComponentPostInit("groundpounder", install_groundpounder)
    AddComponentPostInit("combat", install_combat)
    if AddPrefabPostInit then
        AddPrefabPostInit("alterguardian_lunar_fissures",function(inst) Extra.install_fissure(inst,{upvalue=upvalue,active=active_token,dispatch=dispatch_token,ready=ready,native_source=native_source}) end)
        for _,name in ipairs({"toadstool","toadstool_dark"}) do AddPrefabPostInit(name,install_toad_bombs) end
        for _,name in ipairs({"mushroombomb_projectile","mushroombomb_dark_projectile"}) do AddPrefabPostInit(name,install_bomb_projectile) end
        for _,name in ipairs({"mushroombomb","mushroombomb_dark"}) do AddPrefabPostInit(name,install_bomb) end
    end
    local registered = {}
    for _, spec in pairs(specs) do
        local key = spec.graph
        if not registered[key] then
            registered[key] = true
            AddStategraphPostInit(key, function(graph) install_graph(key, graph) end)
        end
    end
end

function M.supports(inst)
    local spec = inst and specs[inst.prefab]
    if not (spec and inst.sg and graphs[inst.sg.sg] and graphs[inst.sg.sg][spec]) then return false end
    if spec.ring then
        local gp = inst.components and inst.components.groundpounder
        if not (gp and gp._nw_fog_boss_hooked and not gp.usePointMode) then return false end
    elseif spec.area then
        local combat = inst.components and inst.components.combat
        if not (combat and combat._nw_fog_boss_area_hooked and combat.areahitrange == C.signature.area_radius
            and combat.areahitcheck == nil) then return false end
    end
    return true
end

local function safe(inst, waiting)
    if not (inst:IsValid() and inst.components.health and not inst.components.health:IsDead())
        or inst:IsInLimbo() or inst:IsAsleep() then return false end
    if inst.bufferedaction and not (ACTIONS and inst.bufferedaction.action==ACTIONS.ATTACK) then return false end
    for reason in pairs(inst._brainstopped or {}) do if not waiting or reason~=Wait.reason then return false end end
    if not waiting and inst.brain and inst.brain.paused then return false end
    local dragon = inst.prefab == "dragonfly"
    if inst.buried or inst.defeated or (inst.prefab=="daywalker2" and not inst.hostile) then return false end
    if not Wait.can_move(inst) then return false end
    local mem = inst.sg.mem
    if mem and (mem.wantstoleave or mem.wantstotransform or mem.wantstospawn or mem.wantstofocustarget
        or mem.wantstotransition or mem.wantstochomp or mem.laughsremaining
        or mem.wantstochannel or mem.wantstoroar or mem.wantstoburrow
        or mem.wantstoscreech or mem.wantstoflyaway or mem.wantstospawnguards or mem.focuscount ~= nil
        or mem.dostagger or mem.dohowl or mem.doicegrow or mem.sleeping or (dragon and mem.flyover)) then return false end
    if dragon and inst.reset then return false end
    for _, tag in ipairs({ "busy", "attack", "atk_pre", "dead", "sleeping", "frozen", "electrocute",
        "knockback", "fossilized", "flight", "grounded", "jumping", "nointerrupt" }) do
        if inst.sg:HasStateTag(tag) then return false end
    end
    if inst.components.freezable and inst.components.freezable:IsFrozen() then return false end
    if inst.components.sleeper and inst.components.sleeper:IsAsleep() then return false end
    return true
end

function M.leave(inst)
    if inst then
        inst._nw_fog_boss_covered = nil
        Wait.leave(inst)
    end
end

local function start_move(inst,now,move)
    if move.prepare and move.prepare(inst)==false then return false end
    local spec=specs[inst.prefab]
    local token=begin(inst,spec,now,true,move)
    local ok,err=pcall(inst.sg.GoToState,inst.sg,move.first,inst.components.combat and inst.components.combat.target)
    if not ok then finish(inst,token);error(err,0) end
    return true
end

local function retry(inst,now)
    if inst._nw_fog_boss_cast or not M.supports(inst) or not safe(inst,true) then return false end
    local move=M.select(inst)
    return move and start_move(inst,now,move) or false
end

function M.update(inst, now, covered)
    if not covered then M.leave(inst); return false end
    if not (TheWorld and TheWorld.ismastersim and M.supports(inst)) then return false end
    if inst._nw_fog_boss_cast then return false end
    if inst._nw_fog_boss_wait then return false end
    now = now or GetTime()
    if not safe(inst) then return false end
    local move=M.select(inst)
    if move and start_move(inst,now,move) then return true end
    Wait.start(inst,now,retry)
    return false
end

return M
