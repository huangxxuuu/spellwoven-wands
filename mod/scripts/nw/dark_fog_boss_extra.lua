-- Explicit variants sharing native graphs; never infer support from a boss tag.
local M = {}
function M.add_specs(specs)
    local function single(graph)
        return {graph=graph,first="attack",single=true,native_entry=true,walking=true,
            states={attack=true},links={}}
    end
    specs.klaus=single("klaus")
    specs.warg=single("warg")
    specs.mutatedwarg=single("warg")
    -- SGLeif.lua is capitalized, but ModManager dispatches by graph.name.
    specs.leif=single("leif")
    specs.leif_sparse=single("leif")
    specs.spiderqueen=single("spiderqueen")
    -- SGbeequeen's native 14-frame sting is single-target, not an AOE.
    -- Missing/out-of-range targets use the common panic/body-clearing path.
    specs.beequeen=single("beequeen")
    specs.spat=single("spat")
    local function spat_weapon(inst)
        local weapon=inst.weaponitems and inst.weaponitems.meleeweapon
        return weapon and weapon:IsValid() and weapon.components
            and weapon.components.weapon and weapon.components.equippable and weapon or nil
    end
    specs.spat.available=function(inst)
        return inst.components.inventory~=nil and spat_weapon(inst)~=nil
    end
    specs.spat.target_in_range=function(inst,target)
        local weapon=spat_weapon(inst)
        local combat=inst.components.combat
        if not (weapon and combat and target and target:IsValid()) then return false end
        -- Combat:GetAttackRange/CalcAttackRangeSq, using the weapon the native
        -- melee state will actually wield. Never equip during selection and
        -- never borrow the phlegm launcher's much larger current range.
        local extra=weapon.components.weapon.attackrange
        local range=extra~=nil and math.max(0,combat.attackrange+extra) or combat.attackrange
        range=range+target:GetPhysicsRadius(0)
        return target:GetDistanceSqToPoint(inst.Transform:GetWorldPosition())<=range*range
    end
    specs.spat.prepare=function(inst)
        local weapon=spat_weapon(inst)
        local c=inst.components
        if not (weapon and c.inventory and c.combat) or c.combat:InCooldown() then return false end
        if not weapon.components.equippable:IsEquipped() then
            -- Native spatbrain equips this owned weapon before melee. Its
            -- ResetCooldown shortcut is deliberately not used by fog.
            c.inventory:Equip(weapon)
        end
        return weapon.components.equippable:IsEquipped()
    end
    specs.mutateddeerclops={graph="deerclops",first="attack",native_entry=true,walking=true,
        states={attack=true},links={}}
    specs.mutatedbearger={graph="bearger",first="pound",ring=true,timer="GroundPound",native_entry=true,walking=true,
        fallback={first="attack",sector=true},
        states={pound=true,bi=true,attack=true,attack_combo1=true,attack_combo2=true,attack_combo1a=true},
        links={pound={bi=true},bi={pound=true,attack=true,attack_combo1=true},
            attack={attack_combo1=true,bi=true},attack_combo1={bi=true,attack_combo2=true},
            attack_combo2={attack_combo1a=true},attack_combo1a={attack_combo2=true}}}
    specs.daywalker2={graph="daywalker2",first="attack_swing",native_entry=true,walking=true,
        requires_target=true,available=function(inst) return inst.canswing and inst.hostile and not(inst.buried or inst.defeated) end,
        states={attack_swing=true,attack_swing_pst=true},links={attack_swing={attack_swing_pst=true}}}
    specs.alterguardian_phase4_lunarrift={graph="alterguardian_phase4_lunarrift",first="slam",slam=true,native_entry=true,
        available=function(inst) return inst.slamcombo~=nil end,
        fallback={first="dash_pre",dash=true,requires_target=true,available=function(inst) return inst.dashcombo~=nil end},
        states={slam=true,dash_pre=true,dash_loop=true,dash_pst=true},
        links={dash_pre={dash_loop=true},dash_loop={dash_loop=true,dash_pst=true}}}
end

-- Every hook executes the original once, preserving its results and side effects.
function M.install_graph(name, graph, ctx)
    if name~="daywalker2" and name~="alterguardian_phase4_lunarrift" and name~="bearger" then return true end
    if not(debug and debug.getupvalue and debug.setupvalue and debug.getinfo) then return false,"debug API unavailable" end
    local uv,active,notify=ctx.upvalue,ctx.active,ctx.notify
    local function patch(states, wanted, make, minimum)
        local sites, originals={},{}
        for _,state in ipairs(states) do
            local s=graph.states[state]
            if s then
                local funcs={};if s.onenter then funcs[#funcs+1]=s.onenter end
                if s.onupdate then funcs[#funcs+1]=s.onupdate end
                for _,e in ipairs(s.timeline or {}) do funcs[#funcs+1]=e.fn end
                for _,owner in ipairs(funcs) do
                    local fn,index=uv(owner,wanted)
                    if fn then
                        if not ctx.native_source(fn,"stategraphs/SG"..name..".lua") then return false,"changed "..wanted end
                        sites[#sites+1]={owner,index,fn};originals[fn]=true
                    end
                end
            end
        end
        if #sites<(minimum or 1) then return false,"missing "..wanted end
        for fn in pairs(originals) do originals[fn]=make(fn) end
        for _,s in ipairs(sites) do debug.setupvalue(s[1],s[2],originals[s[3]]) end
        return true
    end
    if name=="bearger" then
        -- The combo closure has the same native 180-degree half-disc as attack,
        -- but uses its own half-unit offset and follows all three native swings.
        return patch({"attack_combo1","attack_combo2","attack_combo1a"},"DoComboArcAttack",function(original)
            return function(inst,...)
                local token=active(inst)
                local x,_,z=inst.Transform:GetWorldPosition();local rot=inst.Transform:GetRotation()
                local result=original(inst,...)
                if token and token.move.sector then
                    local a=rot*math.pi/180
                    require("nw/dark_fog").disperse_sector(token.world,x+.5*math.cos(a),z-.5*math.sin(a),TUNING.BEARGER_MELEE_RANGE,rot,180)
                end
                return result
            end
        end,6)
    elseif name=="daywalker2" then
        return patch({"attack_swing"},"DoArcAttack",function(original)
            return function(inst,dist,radius,arc,...)
                local token=active(inst,"attack_swing")
                local x,_,z=inst.Transform:GetWorldPosition();local rot=inst.Transform:GetRotation()
                local result=original(inst,dist,radius,arc,...)
                if token then
                    local a=rot*math.pi/180
                    require("nw/dark_fog").disperse_arc(token.world,x+dist*math.cos(a),z-dist*math.sin(a),radius,rot,arc)
                end
                return result
            end
        end)
    end
    local ok,reason=patch({"slam"},"DoSlamAOE",function(original)
        return function(inst,x,z,...)
            local token=active(inst,"slam")
            local result=original(inst,x,z,...)
            if token then notify(token,x,z,5) end
            return result
        end
    end,4)
    if not ok then return ok,reason end
    return patch({"dash_loop","dash_pst"},"DoDashAOE",function(original)
        return function(inst,...)
            local token=active(inst)
            local x,_,z=inst.Transform:GetWorldPosition()
            local result=original(inst,...)
            if token and token.move.dash then notify(token,x,z,3.6) end
            return result
        end
    end,2)
end

function M.install_fissure(inst,ctx)
    if not(TheWorld and TheWorld.ismastersim and debug and debug.getupvalue and debug.setupvalue and debug.getinfo) then return end
    local uv=ctx.upvalue
    local anim=uv(inst.OnLoad,"OnAnimOver")
    local update,index=uv(anim,"OnUpdate")
    -- Shared OnUpdate upvalue is used both by immediate activation and the
    -- native periodic task. Mark once, before any fissure can finish its preanim.
    M.fissure_hooks=M.fissure_hooks or setmetatable({}, {__mode="k"})
    if not M.fissure_hooks[anim] and not ctx.native_source(update,"prefabs/alterguardian_lunar_fissures.lua") then return end
    if not M.fissure_hooks[anim] then
        debug.setupvalue(anim,index,function(fissure,...)
            local awake=not fissure:IsAsleep()
            local token=fissure._nw_fog_boss_fissure_token
            local result=update(fissure,...)
            if awake and token and token.world==TheWorld and TheWorld.ismastersim
                and (not ctx.ready or ctx.ready(token)) then
                local x,_,z=fissure.Transform:GetWorldPosition()
                require("nw/dark_fog").disperse_box(token.world,x,z,2,2)
            end
            return result
        end)
        M.fissure_hooks[anim]=true
    end
    local tracking=inst.StartTrackingBoss
    if type(tracking)=="function" then
        inst.StartTrackingBoss=function(fissure,boss,...)
            local token=boss and (ctx.dispatch or ctx.active)(boss,"slam")
            fissure._nw_fog_boss_fissure_token=token and token.move.slam and token or nil
            return tracking(fissure,boss,...)
        end
    end
end
return M
