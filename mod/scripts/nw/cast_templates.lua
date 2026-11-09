local Copy=require("nw/util").copy
local M={}

-- Count the first release of each payload without materializing copies.
-- Memoization also allows several carriers to reference the same template.
function M.sizes(blocks)
    local sizes,visiting={},{}
    local function count(index)
        if sizes[index] then return sizes[index] end
        if visiting[index] or not blocks[index] then return nil end
        visiting[index]=true
        local b,n=blocks[index],0
        for _,p in ipairs(b.projectiles) do
            local child=p.payload and count(p.payload) or 0
            if p.payload and not sizes[p.payload] then return nil end
            n=n+(p.count or 1)*(1+child)
        end
        sizes[index]=n*(b.copies or 1)
        visiting[index]=nil
        return sizes[index]
    end
    for i in ipairs(blocks) do if not count(i) then return nil,"INVALID_PLAN" end end
    return sizes
end

-- Static parameters are immutable. Only damage/support variants need a copy;
-- payload IDs still point into the compact plan, never into a per-carrier tree.
function M.resolver()
    local templates={}
    return function(original,fraction,limited)
        if fraction==1 and not limited then return original end
        local variants=templates[original]
        if not variants then variants={};templates[original]=variants end
        local scaled=variants[fraction]
        if not scaled then scaled={};variants[fraction]=scaled end
        local key=limited and 2 or 1
        if scaled[key] then return scaled[key] end
        local p=Copy(original)
        if fraction~=1 then
            p.effect_scale=fraction
            for _,field in ipairs({"damage","jump_damage","burn_damage","end_damage","planar","heal"}) do
                if p[field] then p[field]=p[field]*fraction end
            end
        end
        if limited then
            p.flags.melee_mark=nil
            p.freeze,p.flags.heal_ally,p.flags.leech,p.flags.knockback=nil,nil,nil,nil
            p.secondary=true
            p.suppress_support=p.kind=="note" or p.id=="vital_ring" or p.id=="vortex"
                or p.id=="rain_cloud" or p.id=="guard_ring" or p.id=="detonate"
        end
        scaled[key]=p
        return p
    end
end

-- Saved placements own a serializable snapshot of reachable templates only.
-- Inherited copy restrictions are applied when this payload actually fires.
function M.snapshot(blocks,root,scale,secondary,seed)
    if not root then return end
    local plan={blocks={},next_state={rng_state=seed or 1},payload_root=true,
        payload_scale=scale or 1,payload_secondary=secondary or false}
    local mapped={}
    local function collect(index)
        if mapped[index] then return mapped[index] end
        local n=#plan.blocks+1
        mapped[index]=n
        local b=Copy(blocks[index])
        b.id=n;plan.blocks[n]=b
        for _,p in ipairs(b.projectiles) do
            if p.payload then p.payload=collect(p.payload) end
        end
        return n
    end
    collect(root)
    plan.projectile_count=assert(M.sizes(plan.blocks))[1]
    return plan
end
return M
