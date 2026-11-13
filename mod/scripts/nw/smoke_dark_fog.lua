-- Isolated offline native-engine suite; never runs in normal worlds.
-- Checks real entity/combat/network APIs, not rendered client appearance.
local M = {}

function M.run()
    local Fog = require("nw/dark_fog")
    local made, seen, players = {}, {}, AllPlayers
    local restore_spawn
    local x, z = 0, 0
    for _, e in pairs(Ents) do
        if e:HasTag("multiplayer_portal") then
            local px, _, pz = e.Transform:GetWorldPosition()
            x, z = px, pz
            break
        end
    end
    local function remember(e)
        assert(e, "native prefab/region creation")
        if not seen[e] then seen[e] = true; made[#made + 1] = e end
        return e
    end
    local function position(e, px, pz)
        if e.Physics then e.Physics:Teleport(px, 0, pz)
        else e.Transform:SetPosition(px, 0, pz) end
    end
    local function spawn(name, px, pz)
        local e = remember(SpawnPrefab(name))
        position(e, px or x, pz or z)
        e.entity:SetCanSleep(false)
        print("NW_DARK_FOG_SPAWN",name,e.GUID)
        return e
    end
    local function wait(seconds) coroutine.yield(seconds or .1) end
    local function cloud(owner, px, pz)
        local e = remember(Fog.leave(owner, px, pz))
        local record = assert(TheWorld._nw_dark_fog.sources[e], "registered fog")
        local remaining = record.expires - GetTime()
        assert(remaining >= 3 - FRAMES and remaining <= 5 + FRAMES, "server lifetime 3-5 seconds")
        assert(not record.parent and e.entity:GetParent() == nil, "fixed ground fog has no carrier")
        assert(not e.persists and not e.Light and e._nw_dark_dissipating, "transient network region without light")
        return e, record
    end
    local function clear_fog()
        local pool = TheWorld._nw_dark_fog
        local list = {}
        for e in pairs(pool and pool.sources or {}) do list[#list + 1] = remember(e) end
        for _, e in ipairs(list) do if e:IsValid() then e:Remove() end end
        Fog.refresh(TheWorld)
    end
    local function cleanup()
        if restore_spawn then restore_spawn();restore_spawn=nil end
        AllPlayers = players
        clear_fog()
        for i = #made, 1, -1 do
            local e = made[i]
            if e:IsValid() then e:Remove() end
        end
    end
    local function idle_fixture(e)
        -- Suppress unrelated wandering, retaining a distinct brain stop reason.
        e:StopBrain("nw_dark_smoke")
        if e.components.sleeper then e.components.sleeper:WakeUp() end
        e.sg:GoToState("idle")
        e.components.locomotor:Stop()
    end
    local function lane()
        -- Find an unobstructed land segment; never erase world objects for tests.
        for i = 0, 31 do
            local angle = i * 2 * math.pi / 32
            local dx, dz = math.cos(angle), math.sin(angle)
            local sx, sz = x + dx * 8, z + dz * 8
            local clear = true
            for step = 0, 8 do
                local px, pz = sx + dx * step, sz + dz * step
                if not TheWorld.Map:IsPassableAtPoint(px, 0, pz) then clear = false; break end
                for _, e in ipairs(TheSim:FindEntities(px, 0, pz, 1,
                    nil, { "FX", "NOCLICK", "INLIMBO", "player", "playerghost" })) do
                    if e.Physics and not e.components.inventoryitem then clear = false; break end
                end
                if not clear then break end
            end
            if clear then return sx, sz, dx, dz end
        end
        error("no clear 8-unit ground lane near fresh-world portal")
    end

    local function suite()
        assert(TheWorld.ismastersim and not TheWorld._nw_dark_fog, "fresh isolated server world")
        TheWorld:PushEvent("ms_setclocksegs", { day = 16, dusk = 0, night = 0 })
        local player = spawn("wilson")
        player.userid = "NW_DARK_SMOKE"
        AllPlayers = { player }
        wait(.5)
        local grue = player.components.grue
        assert(player:IsInLight() and grue.immunity.light, "native daytime light baseline")
        local health = player.components.health.currenthealth
        local level, next_hit = grue.level, grue.nextHitTime
        local immunity = {}
        for key, value in pairs(grue.immunity) do immunity[key] = value end
        local grue_hits = 0
        player:ListenForEvent("attackedbygrue", function() grue_hits = grue_hits + 1 end)
        local function player_unchanged()
            assert(player:IsInLight() and player.components.health.currenthealth == health, "player light and health unchanged")
            assert(grue_hits == 0 and grue.level == level and grue.nextHitTime == next_hit,
                "fog cannot start/change native grue countdown")
            for key, value in pairs(immunity) do assert(grue.immunity[key] == value, "native immunity preserved") end
            for key, value in pairs(grue.immunity) do assert(immunity[key] == value, "fog adds no grue immunity") end
            assert(not player._nw_dark_control and not grue._nw_dark_fog, "player excluded from fog control")
        end

        -- Real server net_bool changes before deletion; overlapping sources
        -- retain one continuous small-creature fear interval.
        local rabbit = spawn("rabbit", x + 1, z)
        idle_fixture(rabbit)
        wait(2 * FRAMES) -- let native spawn/sleep state and spatial indexing settle
        local first = cloud(player, x + 1, z)
        -- Nullrenderer cannot validate textures. Compare the native emitter so
        -- its resource warning is not mistaken for a successful visual check.
        print("NW_DARK_FOG_VISUAL: native miasma baseline")
        local baseline=assert(SpawnPrefab("miasma_cloud_fx"))
        assert(baseline.VFXEffect,"native miasma emitter available")
        baseline:Remove()
        print("NW_DARK_FOG_VISUAL: spell miasma emitter")
        require("nw/dark_fog_visual").attach(first) -- native VFXEffect, even on nullrenderer
        assert(first._nw_dark_visuals and #first._nw_dark_children == 1
            and first._nw_dark_children[1].VFXEffect, "native miasma visual resources instantiate")
        assert(not first._nw_dark_dissipating:value(), "active net state")
        Fog.refresh(TheWorld)
        local state = assert(rabbit._nw_dark_control, "rabbit entered shared manager; class="
            ..tostring(require("nw/dark_fog_profiles").classify(rabbit)).." asleep="..tostring(rabbit:IsAsleep())
            .." limbo="..tostring(rabbit:IsInLimbo()).." covered="..tostring(Fog.contains(TheWorld,rabbit)))
        assert(state.kind == "small" and state.phase == "fear_hold", "small entry fear")
        assert(math.abs(state.until_time - state.entered - 1) < .001, "one-second hold deadline")
        local rx, _, rz = rabbit.Transform:GetWorldPosition()
        wait(.45)
        local ax, _, az = rabbit.Transform:GetWorldPosition()
        assert((rx-ax)^2 + (rz-az)^2 < .01 and state.phase == "fear_hold", "rabbit holds rather than walking")
        local second = cloud(player, x + 2, z)
        Fog.refresh(TheWorld)
        assert(rabbit._nw_dark_control == state, "overlap cannot restart fear")
        assert(Fog.dissipate(first) and first:IsValid() and first._nw_dark_dissipating:value(), "fade net state precedes removal")
        assert(first._nw_dark_inactive and rabbit._nw_dark_control == state, "first fade withdraws only its coverage")
        assert(not Fog.dissipate(first), "duplicate fade is idempotent")
        wait(.65)
        Fog.refresh(TheWorld)
        assert(rabbit._nw_dark_control == state and state.phase == "blind_wander", "one-second fear transitions to blind wander")
        position(rabbit, x - 5, z)
        Fog.refresh(TheWorld)
        assert(not rabbit._nw_dark_control and not (rabbit._brainstopped and rabbit._brainstopped.nw_fog_control), "exit removes own brain reason")
        assert(rabbit._brainstopped and rabbit._brainstopped.nw_dark_smoke, "independent brain stop survives")
        rabbit:Remove(); second:Remove(); player_unchanged()
        print("NW_DARK_FOG_STAGE: rabbit passed")

        local sx, sz, dx, dz = lane()
        -- Real combat methods, no forced attack event or changed attack range/CD.
        local hound = spawn("hound", sx, sz)
        idle_fixture(hound)
        local target = spawn("wilson", sx + dx * 2.5, sz + dz * 2.5)
        target.userid = "NW_DARK_TARGET"
        target.components.health:SetInvincible(true)
        wait(2 * FRAMES)
        local combat = hound.components.combat
        local attackrange, attackperiod = combat.attackrange, combat.min_attack_period
        local houndfog = cloud(player, sx, sz)
        combat:SetTarget(target)
        assert(combat.target == target, "native hound accepts real hostile target")
        Fog.refresh(TheWorld)
        assert(combat.target == nil, "entry immediately drops previous target")
        Fog.refresh(TheWorld)
        assert(combat.target == target and hound._nw_dark_control.phase == "near_combat", "legal near target reacquired")
        local direction = hound._nw_dark_control.last_direction
        position(target, sx + dx * 7, sz + dz * 7)
        wait(2 * FRAMES) -- physics teleport becomes visible to native IsNear on the next tick
        Fog.refresh(TheWorld)
        assert(combat.target == nil and hound._nw_dark_control.phase == "blind_continue", "far target lost, blind continuation entered; phase="
            ..tostring(hound._nw_dark_control and hound._nw_dark_control.phase).." target="..tostring(combat.target)
            .." near="..tostring(hound:IsNear(target,3)))
        position(target, sx - dz * 7, sz + dx * 7)
        wait(2 * FRAMES)
        combat:SetTarget(target)
        Fog.refresh(TheWorld)
        assert(combat.target == nil and hound._nw_dark_control.last_direction == direction, "remote retaliation cannot steer or re-lock")
        assert(combat.attackrange == attackrange and combat.min_attack_period == attackperiod, "native attack range and period preserved")
        print("NW_DARK_FOG_STAGE: hound perception passed")
        houndfog:Remove(); Fog.refresh(TheWorld)
        assert(not hound._nw_dark_control, "hound exit cleanup")
        hound:Remove(); target:Remove()
        print("NW_DARK_FOG_STAGE: hound cleanup passed")

        local shadow = spawn("crawlinghorror", sx, sz)
        idle_fixture(shadow)
        wait(2 * FRAMES)
        local locomotor = shadow.components.locomotor
        local speed = locomotor:GetWalkSpeed()
        local old_settarget, old_brain = shadow.components.combat.SetTarget, shadow.brain
        local sf1 = cloud(player, sx, sz)
        local sf2 = cloud(player, sx + dx, sz + dz)
        Fog.refresh(TheWorld)
        assert(shadow._nw_dark_control and shadow._nw_dark_control.kind == "shadow", "shadow classification")
        assert(math.abs(locomotor:GetWalkSpeed() / speed - 1.25) < .0001, "one external 1.25 speed multiplier")
        assert(shadow.brain == old_brain and shadow.components.combat.SetTarget == old_settarget
            and not shadow._brainstopped.nw_fog_control, "shadow native brain and combat untouched")
        sf1:Remove(); Fog.refresh(TheWorld)
        assert(math.abs(locomotor:GetWalkSpeed() / speed - 1.25) < .0001, "overlap does not stack or remove speed")
        sf2:Remove(); Fog.refresh(TheWorld)
        assert(not shadow._nw_dark_control and math.abs(locomotor:GetWalkSpeed() - speed) < .0001, "shadow speed restored")
        shadow:Remove()
        print("NW_DARK_FOG_STAGE: shadow passed")

        -- Native projectile updates must leave multiple static samples.
        local Compiler = require("nw/compiler")
        local wand = require("nw/generator").starter()
        wand.stats.mana_max = 600
        wand.cards = { { spell_id = "dark", card_uid = "fog-d" }, { spell_id = "spark", card_uid = "fog-s" } }
        wand.runtime = Compiler.initial(wand.cards, wand.stats, 4)
        local descriptor = assert(Compiler.compile(wand)).blocks[1].projectiles[1]
        assert(descriptor.flags.dark and descriptor.id == "spark", "dark remains a projectile modifier")
        descriptor.speed, descriptor.lifetime, descriptor.damage = 8, .65, 0
        local shot = spawn("nw_projectile", sx, sz)
        shot:Launch(player, descriptor, sx, sz, dx, dz, function() end, 1.4)
        assert(shot._nw_dark_trail and not shot._nw_dark_fog_fx, "distance trail replaces attached cloud")
        wait(.3)
        local sampled = {}
        for e, record in pairs(TheWorld._nw_dark_fog and TheWorld._nw_dark_fog.sources or {}) do
            remember(e); sampled[e] = { x = record.x, z = record.z }
        end
        assert(next(sampled), "projectile leaves live regions during flight")
        wait(.5)
        assert(not shot:IsValid(), "native projectile lifetime ends")
        local count, minalong, maxalong = 0, math.huge, -math.huge
        for e, record in pairs(TheWorld._nw_dark_fog and TheWorld._nw_dark_fog.sources or {}) do
            remember(e); count = count + 1
            local ex, ey, ez = e.Transform:GetWorldPosition()
            assert(math.abs(ey) < .01 and math.abs(ex-record.x) < .01 and math.abs(ez-record.z) < .01
                and e.entity:GetParent() == nil, "trail regions remain fixed on ground")
            local previous = sampled[e]
            if previous then assert(math.abs(ex-previous.x) < .01 and math.abs(ez-previous.z) < .01, "old region does not follow shot") end
            assert(record.expires - GetTime() <= 5, "no twelve-second terminal region")
            local along = (ex-sx)*dx + (ez-sz)*dz
            minalong, maxalong = math.min(minalong, along), math.max(maxalong, along)
        end
        assert(count >= 3 and maxalong - minalong >= 2, "distributed flight samples, not one terminal cloud")
        clear_fog()
        print("NW_DARK_FOG_STAGE: projectile passed")

        -- Real locomotor travel queues are separate from inst.bufferedaction.
        local queue_boss=spawn("bearger",sx,sz)
        local food=spawn("carrot",sx+dx*3,sz+dz*3)
        wait(.3);queue_boss.sg:GoToState("idle")
        local loco=queue_boss.components.locomotor
        local failed=0
        local travel=BufferedAction(queue_boss,food,ACTIONS.PICKUP)
        travel:AddFailAction(function() failed=failed+1 end)
        loco:SetBufferedAction(travel)
        cloud(player,sx,sz);Fog.refresh(TheWorld)
        assert(loco.bufferedaction==travel and failed==0 and not queue_boss._nw_fog_boss_cast
            and not queue_boss._nw_fog_boss_wait,"fog must not cancel native non-combat travel")
        clear_fog();loco:SetBufferedAction(nil)
        assert(failed==1,"native travel failure callback fixture")
        -- Once the action is a chase attack, cancel it exactly once while
        -- acquiring the cast's own brain reason before native SG entry.
        local chase=BufferedAction(queue_boss,player,ACTIONS.ATTACK)
        chase:AddFailAction(function() failed=failed+1 end)
        loco:SetBufferedAction(chase)
        cloud(player,sx,sz);Fog.refresh(TheWorld)
        assert(queue_boss._nw_fog_boss_cast and queue_boss._brainstopped.nw_fog_boss
            and not loco.bufferedaction and failed==2,"native chase queue cleared once before cast")
        queue_boss:Remove();food:Remove();clear_fog();wait(.2)
        print("NW_DARK_FOG_STAGE: native travel queue preservation and attack cancellation passed")

        -- Reproduce the reported deck against natural AI, without forcing an
        -- idle/walk state or resetting attack timers before the fog lands.
        local live_wand=require("nw/generator").starter()
        live_wand.stats.mana_max=10000
        live_wand.cards={{spell_id="dark",card_uid="live-dark"},
            {spell_id="pierce",card_uid="live-pierce"},{spell_id="scatter",card_uid="live-scatter"}}
        live_wand.runtime=Compiler.initial(live_wand.cards,live_wand.stats,13)
        local live_plan=assert(Compiler.compile(live_wand))
        for _,prefab in ipairs({"dragonfly","bearger","moose","deerclops","warg"}) do
            if prefab=="moose" then TheWorld:PushEvent("ms_setseason","spring");wait(2*FRAMES) end
            if prefab=="deerclops" then TheWorld:PushEvent("ms_setseason","winter");wait(2*FRAMES) end
            local live_boss=spawn(prefab,sx+dx*6,sz+dz*6)
            position(player,sx,sz)
            player.components.health:SetInvincible(true)
            local weapon
            if prefab=="moose" then
                weapon=remember(SpawnPrefab("spear"))
                player.components.inventory:Equip(weapon)
            end
            wait(.3)
            live_boss.components.combat:SetTarget(player)
            local covered,reacted,laststate=false,false,nil
            local dispelled=false
            local disperse=Fog.disperse_circle
            local disperse_path=Fog.disperse_path
            Fog.disperse_path=function(...)
                local count=disperse_path(...)
                dispelled=dispelled or count>0
                return count
            end
            Fog.disperse_circle=function(...)
                local count=disperse(...)
                dispelled=dispelled or count>0
                return count
            end
            for tick=1,100 do
                if tick<=60 and tick%5==1 then
                    local px,_,pz=player.Transform:GetWorldPosition()
                    local bx,_,bz=live_boss.Transform:GetWorldPosition()
                    local length=math.sqrt((bx-px)^2+(bz-pz)^2)
                    if length>.01 then assert(require("nw/executor").execute(live_plan,player,px,pz,(bx-px)/length,(bz-pz)/length,1.4)) end
                end
                wait(.1)
                local inside=Fog.contains(TheWorld,live_boss)
                covered=covered or inside
                reacted=reacted or live_boss._nw_fog_boss_cast~=nil or live_boss._nw_fog_boss_wait~=nil
                local state=live_boss.sg.currentstate.name
                if state~=laststate then
                    print("NW_DARK_FOG_LIVE:",prefab,state,"covered",inside,"reaction",live_boss._nw_fog_boss_cast~=nil,
                        "supported",require("nw/dark_fog_boss").supports(live_boss))
                    laststate=state
                end
                if tick>=60 and reacted and dispelled then break end
            end
            Fog.disperse_circle=disperse
            Fog.disperse_path=disperse_path
            print("NW_DARK_FOG_LIVE_RESULT:",prefab,"covered",covered,"reacted",reacted,"dispelled",dispelled)
            assert(covered and reacted and dispelled,"natural "..prefab.." reacts to dark/pierce/scatter and disperses fog")
            if weapon then
                -- Range-specific native honk behavior has separate checks;
                -- a fog-only honk need not drop this distant player's weapon.
                if weapon:IsValid() then weapon:Remove() end
            end
            live_boss:Remove();clear_fog()
            position(player,x,z)
            wait(.8)
        end

        -- Native inventory drop: fog honks retain close-range disarm but
        -- must not steal a remote combat target's weapon.
        TheWorld:PushEvent("ms_setseason","spring");wait(2*FRAMES)
        for _,distance in ipairs({30,1}) do
            clear_fog()
            local moose=spawn("moose",sx,sz)
            position(player,sx+dx*distance,sz+dz*distance)
            local spear=remember(SpawnPrefab("spear"));player.components.inventory:Equip(spear)
            wait(.3)
            moose.components.combat:SetTarget(player)
            moose.sg:GoToState("idle")
            cloud(player,sx,sz);Fog.refresh(TheWorld)
            assert(moose._nw_fog_boss_cast and moose.sg.currentstate.name=="disarm","range fixture starts fog honk")
            wait(.6)
            local held=player.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==spear
            assert(held==(distance==30),"fog honk retains native close range and rejects remote disarm")
            assert(not moose.CanDisarm,"fog honk preserves native availability consumption")
            moose:Remove();if spear:IsValid() then spear:Remove() end
            clear_fog();wait(.2)
        end
        position(player,x,z)
        print("NW_DARK_FOG_STAGE: native moose close/remote disarm range passed")

        player.components.health:SetInvincible(false)

        -- Real pursuit state + ordinary swing cooldown previously starved fog
        -- reactions. Keep native pound timing and its dedicated cooldown.
        local dragon = spawn("dragonfly", sx + dx * 5, sz + dz * 5)
        wait(2 * FRAMES)
        assert(dragon:IsValid(), "native dragonfly survives initialization")
        dragon.components.combat:StartAttack()
        dragon.sg:GoToState("walk")
        assert(dragon.components.combat:InCooldown(), "ordinary swing cooldown fixture")
        local df = cloud(player, sx + dx * 5, sz + dz * 5)
        Fog.refresh(TheWorld)
        assert(dragon._nw_fog_boss_cast and dragon.sg.currentstate.name == "pound_pre",
            "pursuing dragonfly starts defensive pound despite ordinary swing cooldown")
        local dragon_deadline = GetTime() + 2.8
        while df:IsValid() and not df._nw_dark_inactive and GetTime() < dragon_deadline do wait(.1) end
        assert(df._nw_dark_inactive, "native dragonfly damage rings disperse fog before expiry")
        dragon_deadline = GetTime() + 4
        while dragon._nw_fog_boss_cast and GetTime() < dragon_deadline do wait(.1) end
        assert(not dragon._nw_fog_boss_cast and not (dragon._brainstopped and dragon._brainstopped.nw_fog_boss),
            "dragonfly completes its native pound and restores brain")
        assert(dragon.components.timer:TimerExists("groundpound_cd"), "native pound cooldown retained")
        dragon:Remove(); clear_fog()
        print("NW_DARK_FOG_STAGE: dragonfly pursuit/cooldown/pound passed")

        -- Real giant SG, no fake target. Deadline excludes natural expiry.
        -- Native deerclops removes itself on the initial sleep notification
        -- outside winter, even if SetCanSleep(false) was just requested.
        TheWorld:PushEvent("ms_setseason", "winter")
        wait(2 * FRAMES)
        assert(TheWorld.state.season == "winter", "native giant season")
        local boss = spawn("deerclops", sx + dx * 6, sz + dz * 6)
        wait(2 * FRAMES)
        assert(boss:IsValid(), "native giant survives initial spawn/sleep notification")
        boss.sg:GoToState("idle")
        boss.Transform:SetRotation(-math.atan2(dz, dx) / DEGREES)
        boss.components.combat:SetTarget(nil)
        boss.components.combat:ResetCooldown()
        local bf = cloud(player, sx + dx * 7.5, sz + dz * 7.5)
        Fog.refresh(TheWorld)
        assert(boss._nw_fog_boss_cast and boss.sg.currentstate.name == "attack", "native deerclops fog attack starts")
        local deadline = GetTime() + 2.8
        while bf:IsValid() and not bf._nw_dark_inactive and GetTime() < deadline do wait(.1) end
        assert(bf._nw_dark_inactive, "native delayed ice hit dissipates before natural expiry")
        if bf:IsValid() then assert(bf._nw_dark_dissipating:value(), "boss hit synchronizes fade flag") end
        boss:Remove(); clear_fog()
        print("NW_DARK_FOG_STAGE: boss passed")

        -- Lifetimes are sampled once, then naturally fade and remove.
        local lifetimes, low, high, expires = {}, math.huge, 0, 0
        for i = 1, 6 do
            local angle = i * 2 * math.pi / 6
            local e, record = cloud(player, x + math.cos(angle) * 2, z + math.sin(angle) * 2)
            lifetimes[#lifetimes + 1] = e
            local lifetime = record.expires - GetTime()
            low, high, expires = math.min(low, lifetime), math.max(high, lifetime), math.max(expires, record.expires)
        end
        assert(high - low > .00001, "lifetimes independently randomized")
        Fog.refresh(TheWorld); player_unchanged()
        wait(math.max(0, expires - GetTime()) + Fog.fade_duration + .3)
        for _, e in ipairs(lifetimes) do assert(not e:IsValid(), "natural fade/removal completes") end
        assert(not TheWorld._nw_dark_fog, "last region releases shared manager")
        player_unchanged()

        local function compile(...)
            local wand=require("nw/generator").starter()
            wand.stats.mana_max=10000;wand.cards={}
            for i,id in ipairs({...}) do wand.cards[i]={spell_id=id,card_uid="fog_size_"..i} end
            wand.runtime=Compiler.initial(wand.cards,wand.stats,7)
            return assert(Compiler.compile(wand)).blocks[1].projectiles[1]
        end
        local probe=spawn("rabbit",sx+dx*3,sz+dz*3)
        idle_fixture(probe);wait(2*FRAMES)
        for _,case in ipairs({{compile("dark","spark"),2,false},
            {compile("giant_shot","dark","spark"),5,true},
            {compile("shrink_shot","dark","spark"),.8,false}}) do
            local region=remember(Fog.leave(player,sx,sz,case[1]))
            local record=TheWorld._nw_dark_fog.sources[region]
            assert(math.abs(record.radius-case[2])<.0001,"compiled fog radius")
            assert(math.abs(region._nw_dark_radius:value()-case[2])<.0001,"native net radius")
            assert(Fog.contains(TheWorld,probe)==case[3],"scaled native coverage")
            Fog.refresh(TheWorld)
            assert((probe._nw_dark_control~=nil)==case[3],"scaled native creature control")
            clear_fog();wait(.12)
        end
        probe:Remove()
        local victim=spawn("hound",sx+dx*4.5,sz+dz*4.5)
        idle_fixture(victim);wait(2*FRAMES)
        local chain=compile("dark","chain");chain.max_targets=1
        local before=victim.components.health.currenthealth
        require("nw/spell_effects").chain(player,victim,sx,sz,chain,dx,dz,true)
        assert(victim.components.health.currenthealth<before,"native dark chain attack")
        local start,landing,middle=false,false,false
        for region,record in pairs(TheWorld._nw_dark_fog.sources) do
            remember(region)
            local along=(record.x-sx)*dx+(record.z-sz)*dz
            start=start or math.abs(along)<.01
            landing=landing or math.abs(along-4.5)<.1
            middle=middle or along>2.5 and along<3.1
        end
        assert(start and landing and middle,"native dark chain start, impact and path fog")
        victim:Remove();clear_fog();wait(.12)
        local empty=compile("shrink_shot","dark","chain");empty.max_targets=1
        require("nw/spell_effects").chain(player,nil,sx+1000,sz+1000,empty,1,0,true)
        local count=0
        for region,record in pairs(TheWorld._nw_dark_fog.sources) do
            remember(region);count=count+1
            assert(math.abs(record.radius-.8)<.0001,"empty chain retains shrink modifier")
        end
        assert(count>=3,"empty chain also paints its path")
        clear_fog();player_unchanged()
        print("NW_DARK_FOG_STAGE: compiled sizes, net radius, native chain hit/empty paths passed")

        -- Big move and normal attack are both genuinely cooling down. The
        -- body sweep starts after two seconds and outlives its initial fog exit.
        local function waiting_bear()
            local e=spawn("bearger",sx,sz)
            wait(2*FRAMES)
            position(player,sx+1.5,sz)
            player.components.health:SetInvincible(true)
            e.components.combat:SetTarget(player)
            e.components.combat:SetAttackPeriod(10)
            e.components.combat:StartAttack()
            e.components.timer:StopTimer("GroundPound")
            e.components.timer:StartTimer("GroundPound",30)
            e.sg:GoToState("idle")
            local region=remember(Fog.leave(player,sx,sz,{size_mult=10}))
            Fog.refresh(TheWorld)
            -- Native idle may first stand up through bi; let that committed
            -- stance change finish before expecting the cooldown reaction.
            local deadline=GetTime()+2
            while not e._nw_fog_boss_wait and GetTime()<deadline do wait(.05) end
            assert(e._nw_fog_boss_wait,"both cooldowns start native boss panic; state="..e.sg.currentstate.name)
            return e,region
        end
        local cooling,cooling_fog=waiting_bear()
        local later_fog=remember(Fog.leave(player,sx+12,sz))
        wait(1.7)
        assert(cooling._nw_fog_boss_wait and not cooling_fog._nw_dark_inactive,"body does not clear first two seconds")
        wait(.6)
        assert(cooling_fog._nw_dark_inactive,"body clears after two seconds")
        assert(not cooling._nw_fog_boss_wait and not (cooling._brainstopped and cooling._brainstopped.nw_fog_boss_wait),
            "leaving self-cleared fog stops panic and restores the native brain immediately")
        local body=assert(cooling._nw_fog_boss_body,"body clearing survives the initial exit")
        assert(not later_fog._nw_dark_inactive,"distant preexisting cloud has not been cleared yet")
        position(cooling,sx+12,sz);wait(.2)
        assert(later_fog._nw_dark_inactive and cooling._nw_fog_boss_body==body,
            "body keeps sweeping preexisting fog after first leaving coverage")
        while GetTime()<body.until_time+.1 do wait(.1) end
        assert(not cooling._nw_fog_boss_body,"body sweep expires after its finite 2.5-second window")
        cooling:Remove();clear_fog();wait(.15)
        cooling,cooling_fog=waiting_bear()
        wait(.4)
        cooling.components.combat:ResetCooldown()
        local ready_deadline=GetTime()+.4
        while not cooling._nw_fog_boss_cast and GetTime()<ready_deadline do wait(FRAMES) end
        assert(cooling._nw_fog_boss_cast and cooling._nw_fog_boss_wait,"ready melee pauses panic without releasing pursuit control")
        assert(cooling.components.timer:TimerExists("GroundPound"),"fallback never resets the primary timer")
        local impact_deadline=GetTime()+2
        while not cooling_fog._nw_dark_inactive and GetTime()<impact_deadline do wait(.1) end
        assert(cooling_fog._nw_dark_inactive,"fallback melee really disperses fog")
        cooling:Remove();clear_fog();position(player,x,z)
        player.components.health:SetInvincible(false)
        wait(.2);player_unchanged()
        print("NW_DARK_FOG_STAGE: cooldown panic, delayed body sweep, immediate leave cleanup and ready melee fallback passed")

        -- Do not use mouth-only chomp before the native transformation has
        -- made those symbols visible. Native load restores the transformed phase.
        for _,prefab in ipairs({"eyeofterror","twinofterror1","twinofterror2"}) do
            for _,transformed in ipairs({false,true}) do
                local eye=spawn(prefab,sx,sz);wait(2*FRAMES)
                if transformed then eye.OnLoad(eye,{is_transformed=true}) end
                eye.sg:GoToState("idle")
                position(player,sx+1.5,sz);player.components.health:SetInvincible(true)
                eye.components.combat:SetTarget(player)
                local fog=remember(Fog.leave(player,sx,sz,{size_mult=2}))
                Fog.refresh(TheWorld)
                if transformed then
                    assert(eye._nw_fog_boss_cast and eye.sg.currentstate.name=="chomp","transformed eye uses native chomp")
                    wait(1)
                    assert(fog._nw_dark_inactive,"native transformed chomp clears fog")
                else
                    assert(not eye._nw_fog_boss_cast and eye._nw_fog_boss_wait,
                        "untransformed eye panics without hidden-mouth chomp")
                    wait(.3)
                    assert(eye.sg.currentstate.name~="chomp" and not eye.sg.mem.transformed,
                        "fog does not force a transformation or hidden-head animation")
                end
                eye:Remove();clear_fog();wait(.15)
            end
        end
        position(player,x,z);player.components.health:SetInvincible(false)
        print("NW_DARK_FOG_STAGE: all three eye prefabs preserve native transformation gate passed")

        -- Expanded boss fixtures use real native prefabs and complete attacks.
        -- State preparation is test-only; the adapter must never create equipment
        -- or unlock a defeated/buried phase in a normal world.
        local Boss=require("nw/dark_fog_boss")
        for _,row in ipairs({
            {"klaus","attack"}, {"alterguardian_phase4_lunarrift","slam"},
            {"alterguardian_phase4_lunarrift","dash_pre"},
            {"daywalker2","attack_swing"}, {"mutateddeerclops","attack"},
            {"mutatedbearger","pound"}, {"mutatedwarg","attack"},
            {"leif","attack"}, {"leif_sparse","attack"},
            {"spiderqueen","attack"}, {"warg","attack"}, {"beequeen","attack"}, {"spat","attack"},
        }) do
            local e=spawn(row[1],sx,sz)
            wait(2*FRAMES)
            position(player,sx+2,sz)
            player.components.health:SetInvincible(true)
            if row[1]=="daywalker2" then e:SetEquip("swing","object") end
            if row[1]=="alterguardian_phase4_lunarrift" and row[2]=="slam" then
                -- SetPercent sets the value before its zero-delta event, so it
                -- does not cross healthtrigger thresholds. Use real damage.
                e.components.health:DoDelta(-e.components.health.maxhealth*.1,false,"nw_dark_smoke",true,nil,true)
            end
            e.components.combat:SetTarget(player)
            e.components.combat:ResetCooldown()
            if e.components.sleeper then e.components.sleeper:WakeUp() end
            e.sg:GoToState("idle")
            assert(require("nw/dark_fog_profiles").classify(e)=="large",row[1].." boss classification")
            assert(Boss.supports(e),row[1].." installed native adapter")
            local move=Boss.select(e)
            print("NW_DARK_FOG_EXPANDED_SELECT:",row[1],move and move.first,"expected",row[2],"slamcombo",e.slamcombo)
            assert(move and move.first==row[2],row[1].." selects verified attack")
            local cleared,reacted=false,false
            local original_geometry={}
            for _,name in ipairs({"disperse_circle","disperse_sector","disperse_arc","disperse_box"}) do
                local original=Fog[name]
                original_geometry[name]=original
                Fog[name]=function(...)
                    local count=original(...)
                    if e._nw_fog_boss_cast and count>0 then cleared=true end
                    return count
                end
            end
            remember(Fog.leave(player,sx,sz,{size_mult=10}))
            Fog.refresh(TheWorld)
            local deadline=GetTime()+12
            repeat
                reacted=reacted or e._nw_fog_boss_cast~=nil
                if cleared and not e._nw_fog_boss_cast then break end
                if not cleared then remember(Fog.leave(player,sx,sz,{size_mult=10})) end
                wait(.1)
            until GetTime()>=deadline or not e:IsValid()
            for name,original in pairs(original_geometry) do Fog[name]=original end
            assert(reacted and cleared,row[1].." real native attack clears fog")
            assert(not e._nw_fog_boss_cast,row[1].." native attack finishes and restores brain")
            if row[1]=="daywalker2" then
                assert(e.numswings==TUNING.DAYWALKER2_ITEM_USES-1,"native swing still consumes equipment use")
            end
            e:Remove();clear_fog();wait(.8)
            print("NW_DARK_FOG_EXPANDED:",row[1],row[2],"actual impact and completion passed")
        end
        position(player,x,z);player.components.health:SetInvincible(false)
        wait(.2);player_unchanged()

        -- Prevent native projectiles from entering sleep BEFORE their first
        -- physics tick. SetCanSleep(false) after they already slept does not
        -- wake their physics on a server without connected players.
        local original_spawn=SpawnPrefab
        _G.SpawnPrefab=function(name,...)
            local e=original_spawn(name,...)
            if e and string.find(name,"mushroombomb",1,true) then e.entity:SetCanSleep(false) end
            return e
        end
        restore_spawn=function() _G.SpawnPrefab=original_spawn end
        for _,row in ipairs({{"dragonfly","groundpound_cd","attack"},
            {"minotaur","stomptimer","attack"},
            {"toadstool","pound_cd","mushroombomb"},
            {"toadstool_dark","pound_cd","mushroombomb"}}) do
            local e=spawn(row[1],sx,sz)
            wait(2*FRAMES)
            position(player,sx+1.5,sz)
            player.components.health:SetInvincible(true)
            e.components.combat:SetTarget(player)
            e.components.combat:ResetCooldown()
            e.components.timer:StopTimer(row[2]);e.components.timer:StartTimer(row[2],30)
            e.sg:GoToState("idle")
            local move=require("nw/dark_fog_boss").select(e)
            assert(move and move.first==row[3],row[1].." selects available fallback")
            local cleared=false
            local seen_bombs={}
            if row[3]=="mushroombomb" then
                e:ListenForEvent("newstate",function(actor)
                    print("NW_DARK_FOG_BOMB_STATE:",actor.prefab,actor.sg.currentstate.name)
                end)
            end
            local original_disperse=Fog.disperse_circle
            Fog.disperse_circle=function(...)
                local count=original_disperse(...);cleared=cleared or count>0
                print("NW_DARK_FOG_FALLBACK_CLEAR:",row[1],count)
                return count
            end
            remember(Fog.leave(player,sx,sz,{size_mult=10}))
            Fog.refresh(TheWorld)
            local deadline=GetTime()+2
            while not e._nw_fog_boss_cast and GetTime()<deadline do wait(FRAMES) end
            assert(e._nw_fog_boss_cast,row[1].." starts available fallback")
            deadline=GetTime()+8
            while not cleared and GetTime()<deadline do
                -- The actual mushroom flight/growth can outlive one cloud;
                -- replenish naturally expired samples, never extend a lifetime.
                remember(Fog.leave(player,sx,sz,{size_mult=10}))
                if row[3]=="mushroombomb" then
                    for _,bomb in pairs(Ents) do
                        if bomb.prefab and string.find(bomb.prefab,"mushroombomb",1,true) and not seen_bombs[bomb] then
                            seen_bombs[bomb]=true
                            print("NW_DARK_FOG_BOMB:",bomb.prefab,bomb.GUID,"token",bomb._nw_fog_boss_bomb_token~=nil,"asleep",bomb:IsAsleep())
                            -- This isolated server has no connected client to
                            -- wake newly spawned native projectiles or bombs.
                            bomb.entity:SetCanSleep(false)
                            remember(bomb)
                        end
                        -- The independent body sweep can clear the old giant
                        -- fixture around the boss before a bomb lands. Seed
                        -- small live regions at the actual landed bombs too.
                        if bomb.prefab and string.find(bomb.prefab,"mushroombomb",1,true)
                            and not bomb.components.complexprojectile then
                            local bx,_,bz=bomb.Transform:GetWorldPosition()
                            local region=Fog.leave(player,bx,bz,{size_mult=.1})
                            if region then remember(region) end
                        end
                    end
                end
                wait(.2)
            end
            Fog.disperse_circle=original_disperse
            if not cleared then
                for bomb in pairs(seen_bombs) do
                    if bomb:IsValid() and bomb.components.complexprojectile then
                        local bx,by,bz=bomb.Transform:GetWorldPosition()
                        print("NW_DARK_FOG_FLIGHT_TIMEOUT:",bomb.prefab,bomb.GUID,bx,by,bz,
                            "asleep",bomb:IsAsleep(),"vy",bomb.components.complexprojectile.velocity.y,
                            "updating",bomb.updatecomponents and bomb.updatecomponents[bomb.components.complexprojectile]~=nil)
                    end
                end
            end
            assert(cleared,row[1].." native fallback impact clears fog")
            assert(e.components.timer:TimerExists(row[2]),row[1].." keeps primary cooldown")
            for bomb in pairs(seen_bombs) do if bomb:IsValid() then bomb:Remove() end end
            e:Remove();clear_fog();wait(.8)
            print("NW_DARK_FOG_FALLBACK:",row[1],row[3],"actual impact passed")
        end
        restore_spawn();restore_spawn=nil
        position(player,x,z);player.components.health:SetInvincible(false)
        wait(.2);player_unchanged()

        local cards = require("nw/cards")
        assert(cards.codes.dark == 224 and cards.bycode[224] == "dark", "saved/network code 224 stable")
        local card = spawn("nw_spellcard"); card:SetSpell("dark")
        assert(card.spell_id == "dark" and card.components.inventoryitem.imagename == "nw_spell_dark", "independent card identity")
        local restored = remember(SpawnSaveRecord(card:GetSaveRecord()))
        assert(restored.spell_id == "dark" and AllRecipes.nw_inscribe_dark, "native card save and recipe")
    end

    local thread = coroutine.create(suite)
    local function resume()
        local ok, delay = coroutine.resume(thread)
        if not ok then
            cleanup()
            error("NW_DARK_FOG: " .. tostring(delay))
        elseif coroutine.status(thread) == "dead" then
            cleanup()
            assert(not TheWorld._nw_dark_fog, "fog cleanup")
            print("NW_DARK_FOG_PASS: player/grue exclusion, rabbit fear/overlap/exit, hound perception, shadow speed, static projectile trail, dragonfly pursuit/cooldown/pound, native boss ice hit, 3-5s lifetimes/net fade, card 224 save/recipe; client appearance not asserted")
        else
            TheWorld:DoTaskInTime(delay, resume)
        end
    end
    resume()
end

return M
