local U = require("nw/util")
local RNG = require("nw/rng")
local D = require("nw/definitions")
local M = {}
local Settings=require("nw/spell_limits")
-- Materialize each virtual carrier with its own child block. This keeps the
-- executor's scatter rolls, one-shot triggers and budget releases independent.
local function expand(outputs)
    local expanded = {}
    local function visit(id, scale, secondary)
        local source = outputs[id]
        local block = { id = #expanded+1, source_id = id, depth = source.depth,
            modifiers = source.modifiers, delay = source.delay, projectiles = {} }
        expanded[block.id] = block
        if #source.projectiles > 0 then
            for copy = 1, source.copies or 1 do
                for _, original in ipairs(source.projectiles) do
                    local p = U.copy(original)
                    local fraction = scale * (source.copy_damage or 1)
                    local limited = secondary or (source.copy_damage and copy > 1)
                    if fraction ~= 1 then
                        p.effect_scale=fraction
                        for _, key in ipairs({"damage","jump_damage","burn_damage","end_damage","planar","heal"}) do
                            if p[key] then p[key] = p[key] * fraction end
                        end
                    end
                    if limited then
                        p.flags.melee_mark=nil
                        p.freeze, p.flags.heal_ally, p.flags.leech, p.flags.knockback = nil,nil,nil,nil
                        p.secondary=true
                        p.suppress_support = p.kind=="note" or p.id=="vital_ring" or p.id=="vortex"
                            or p.id=="rain_cloud" or p.id=="guard_ring" or p.id=="detonate"
                    end
                    if p.payload then p.payload = visit(p.payload, fraction, limited) end
                    block.projectiles[#block.projectiles+1] = p
                end
            end
        end
        return block.id
    end
    visit(1,1,false)
    return expanded
end
function M.initial(cards, stats, seed)
    local deck = {}
    for _, card in ipairs(cards) do if card then deck[#deck+1] = card.card_uid end end
    local rng = RNG.new(seed or 1)
    if stats.shuffle then rng:shuffle(deck) end
    return { mana = stats.mana_max, deck = deck, discard = {}, reload_delta = 0,
        rng_state = rng.state, remaining_cast = 0, remaining_recharge = 0 }
end
function M.compile(wand, definitions, limits)
    definitions = definitions or D.spells
    limits = limits or {}
    -- Keep malformed-plan guards without turning the former 32-node ceiling
    -- into a hidden depth cap for larger card decks.
    local max_steps, max_nodes = limits.steps or math.max(128,#wand.cards*2), limits.nodes or math.max(32,#wand.cards*2)
    local max_depth, max_projectiles = limits.depth or Settings.depth, limits.projectiles or Settings.cast
    if max_depth==0 then max_depth=math.huge end
    if max_projectiles==0 then max_projectiles=math.huge end
    local stats, state = wand.stats, U.copy(wand.runtime)
    local cards, slots = {}, {}
    for i, c in ipairs(wand.cards) do
        if c then
            if cards[c.card_uid] then return nil, "DUPLICATE_CARD" end
            cards[c.card_uid], slots[c.card_uid] = c, i
        end
    end
    local seen = {}
    for _, list in ipairs({state.deck, state.discard}) do
        for _, id in ipairs(list) do
            if not cards[id] or seen[id] then return nil, "INVALID_DECK" end
            seen[id] = true
        end
    end
    for id in pairs(cards) do if not seen[id] then return nil, "INVALID_DECK" end end
    local rng = RNG.new(state.rng_state)
    local hand, trace, blocks = {}, {}, {}
    local repeated, mana_required, next_afford = false, 0, math.huge
    local wrapped, steps, nodes, error_code = false, 0, 0, nil
    local function reorder(list)
        table.sort(list, function(a,b) return slots[a] < slots[b] end)
        if stats.shuffle then rng:shuffle(list) end
    end
    local function block(depth)
        local b = { id = #blocks + 1, depth = depth, projectiles = {}, delay = 0,
            modifiers = { damage_add = 0, speed_mult = 1, speed_add = 0, lifetime_mult = 1, spread_add = 0, flags = {}, paths={} } }
        blocks[#blocks + 1] = b
        return b
    end
    local function modify(b, d)
        local m = b.modifiers
        if d.select_target then
            m.flags.targets=m.flags.targets or {}
            m.flags.targets[d.select_target]=true
        end
        if d.id=="speed_up" or d.id=="speed_down" then
            m.pitch=(m.pitch or 0)+(d.id=="speed_up" and 1 or -1)
        end
        if d.copies then
            b.copies = math.min(max_projectiles+1, (b.copies or 1) * d.copies)
            if d.copy_damage then b.copy_damage=(b.copy_damage or 1)*d.copy_damage end
            repeated = true
        end
        if D.trajectory[d.id] then m.paths[d.id]=true end
        if d.damage_mult then m.damage_mult=(m.damage_mult or 1)*d.damage_mult end
        if d.imprint then b.imprint=b.imprint or d.imprint end
        m.damage_add = m.damage_add + (d.damage_add or 0)
        m.spread_add = m.spread_add + (d.spread_add or 0)
        if (d.speed_mult or 1)>1 or d.flag=="accelerate" then m.field_drive=true end
        if d.speed_mult then m.field_adjusted=true end
        m.speed_mult = m.speed_mult * (d.speed_mult or 1)
        m.speed_add = m.speed_add + (d.speed_add or 0)
        m.lifetime_mult = m.lifetime_mult * (d.lifetime_mult or 1)
        if d.flag then
            local old = m.flags[d.flag]
            local value = U.copy(d)
            if d.flag=="giant" then value.mult=(old and old.mult or 0)+2.5 end
            if d.flag=="wet_weak" then value.mult=(old and old.mult or 1)*1.25 end
            if d.flag=="chill_touch" then value.cold=(old and old.cold or 0)+.2 end
            if old and d.amplitude then value.amplitude = math.min(2*d.amplitude, old.amplitude + d.amplitude) end
            if old and d.turn_rate then value.turn_rate = math.max(old.turn_rate, d.turn_rate) end
            if old and d.acceleration then
                value.acceleration=(old.acceleration or 0)+d.acceleration
                value.damping=(old.damping or 0)+(d.damping or 0)
            end
            m.flags[d.flag] = value
        end
    end
    local draw
    draw = function(b, allow_wrap)
        if error_code then return end
        while not error_code do
            if #state.deck == 0 then
                if allow_wrap and not wrapped and #state.discard > 0 then
                    state.deck, state.discard = state.discard, {}
                    reorder(state.deck)
                    wrapped = true
                    trace[#trace+1] = { event = "wrap", block = b.id }
                else return end
            end
            steps = steps + 1
            if steps > max_steps then error_code = "COMPILE_LIMIT"; return end
            local id = table.remove(state.deck, 1)
            local d = definitions[cards[id].spell_id]
            if not d or state.mana < d.mana then
                if d then next_afford=math.min(next_afford, wand.runtime.mana-state.mana+d.mana) end
                state.discard[#state.discard+1] = id
                trace[#trace+1] = { event = d and "skip_mana" or "skip_unknown", card = id, block = b.id }
            else
                nodes = nodes + 1
                if nodes > max_nodes then error_code = "COMPILE_LIMIT"; return end
                state.mana = state.mana - d.mana
                mana_required = math.max(mana_required, wand.runtime.mana - state.mana)
                state.reload_delta = state.reload_delta + (d.recharge or 0)
                hand[#hand+1] = id
                b.delay = b.delay + d.delay
                trace[#trace+1] = { event = "execute", card = id, block = b.id, mana = state.mana }
                if d.kind == "modifier" then
                    modify(b, d); draw(b, true)
                elseif d.kind == "multicast" then
                    if d.spread_add then b.modifiers.spread_add=b.modifiers.spread_add+d.spread_add end
                    for lane=1,d.draws do
                        local first=#b.projectiles+1
                        draw(b,true)
                        if d.fan then
                            for i=first,#b.projectiles do
                                local p=b.projectiles[i]
                                p.formation=(p.formation or 0)+d.fan[lane]
                            end
                        end
                    end
                elseif d.kind == "projectile" or d.kind == "trigger" or d.kind=="melee" or d.kind=="instant" or d.kind=="field" or d.kind=="note" then
                    local p = U.copy(d)
                    b.projectiles[#b.projectiles+1] = p
                    if d.kind=="projectile" or d.kind=="trigger" then
                        p.event=p.event or b.imprint
                        if p.event=="timer" then p.time=p.time or .5 end
                        b.imprint=nil
                    end
                    if p.event then
                        if b.depth >= max_depth then error_code = "COMPILE_LIMIT"; return end
                        local child = block(b.depth + 1)
                        p.payload = child.id
                        draw(child, true)
                    end
                else error_code = "INVALID_SPELL" end
                return
            end
        end
    end
    local root = block(0)
    if wand.always_cast then
        local d = definitions[wand.always_cast]
        if not d or d.kind ~= "modifier" then return nil, "INVALID_ALWAYS_CAST" end
        modify(root, d)
        root.delay = root.delay + d.delay
        state.reload_delta = state.reload_delta + (d.recharge or 0)
    end
    for _ = 1, stats.draw_count do draw(root, false) end
    if error_code then return nil, error_code end
    local total, cooldown_floor = 0, 0
    for _, b in ipairs(blocks) do
        local m = b.modifiers
        local paths=0
        for _ in pairs(m.paths) do paths=paths+1 end
        for _, p in ipairs(b.projectiles) do
            cooldown_floor=math.max(cooldown_floor,p.cooldown or 0)
            if p.damage and not p.no_impact_damage then p.damage = math.max(0, math.min(200, (p.damage + m.damage_add/(p.id=="star_vortex" and 4 or 1))*(m.damage_mult or 1))) end
            if p.jump_damage then p.jump_damage = math.max(0, math.min(200, p.jump_damage + m.damage_add)) end
            local travels = p.kind=="projectile" or p.kind=="trigger"
            if p.engraving=="voidcloth_boomerang" then p.growth_mult=m.damage_mult or 1 end
            if travels then
                p.speed = math.max(2, math.min(math.max(30,p.speed), p.speed * m.speed_mult + m.speed_add))
                local lifetime = p.lifetime * (1+.08*math.min(3,paths))
                -- Establish orbit's base duration before modifiers so reduction
                -- also works below four seconds. Lifetime has no upper cap.
                if m.flags.orbit then lifetime=math.max(4,lifetime*4) end
                p.lifetime = math.max(.1, lifetime * m.lifetime_mult)
                p.flight_lifetime_mult = m.lifetime_mult
            end
            if p.kind=="field" and p.id~="guard_ring" then
                p.speed=math.min(30,(p.speed or 0)*m.speed_mult+m.speed_add)
                p.field_drive=p.speed>0
            end
            p.spread = travels and math.max(0, (p.halfangle or 6)*stats.spread/6 + m.spread_add) or 0
            p.flags = U.copy(m.flags)
            if m.flags.giant then
                p.size_mult=m.flags.giant.mult
                -- Compile physical extents once; saved placements retain these
                -- resolved values and must not multiply them again on load.
                for _,key in ipairs({"radius","reach","width","work_radius"}) do
                    if p[key] then p[key]=p[key]*p.size_mult end
                end
            end
            p.pitch=m.pitch
            for key,v in pairs(p.innate or {}) do p.flags[key]=p.flags[key] or U.copy(v) end
            if travels and p.flags.harmless then p.damage,p.burn_damage,p.freeze,p.planar=0,nil,nil,nil end
            total = total + (p.count or 1)
        end
    end
    if repeated then
        -- Children are created after parents. Price the full tree, including
        -- unlaunched payloads, before allocating any copies.
        local sizes = {}
        for i = #blocks, 1, -1 do
            local count = 0
            for _, p in ipairs(blocks[i].projectiles) do
                count = count + (p.count or 1) * (1 + (sizes[p.payload] or 0))
            end
            sizes[i] = count * (blocks[i].copies or 1)
            if sizes[i] > max_projectiles then return nil, "PROJECTILE_LIMIT" end
        end
        total = sizes[1]
        if not limits.defer_copies then blocks = expand(blocks) end
    else
        local sizes={}
        for i=#blocks,1,-1 do
            local count=0
            for _,p in ipairs(blocks[i].projectiles) do count=count+(p.count or 1)*(1+(sizes[p.payload] or 0)) end
            sizes[i]=count
        end
        total=sizes[1]
        if total>max_projectiles then return nil,"PROJECTILE_LIMIT" end
    end
    for _, id in ipairs(hand) do state.discard[#state.discard+1] = id end
    local recharge = wrapped or #state.deck == 0
    state.remaining_cast = math.max(.2, cooldown_floor, stats.cast_delay + root.delay)
    state.remaining_recharge = recharge and math.max(0, stats.recharge + state.reload_delta) or 0
    if recharge then
        for _, id in ipairs(state.deck) do state.discard[#state.discard+1] = id end
        state.deck, state.discard = state.discard, {}
        reorder(state.deck)
        state.reload_delta = 0
    end
    state.rng_state = rng.state
    local mana_spent = wand.runtime.mana - state.mana
    state.mana = math.min(stats.mana_max, state.mana)
    return { next_state = state, root_block = root.id, blocks = blocks, trace = trace,
        expand_on_launch = repeated and limits.defer_copies and expand or nil,
        wrapped = wrapped, recharged = recharge, projectile_count = total,
        mana_spent = mana_spent, mana_required = mana_required, next_afford = next_afford,
        cooldown = math.max(state.remaining_cast, state.remaining_recharge) }
end
return M
