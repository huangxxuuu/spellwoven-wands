local Budget=require("nw/budget")
local RNG=require("nw/rng")
local Effects=require("nw/spell_effects")
local Limits=require("nw/spell_limits")
local Copy=require("nw/util").copy
local M={}
local manager=Budget.new(math.huge,math.huge)
function M.set_projectile_limit(enabled)
    manager.per_player=enabled and 24 or math.huge
    manager.per_shard=enabled and 160 or math.huge
end
function M.stats() return manager.used end
function M.owner_used(owner) return manager.owners[tostring(owner.GUID)] or 0 end

-- A placed egg owns data, not a live reservation or an executor closure.
-- Freeze the already-rolled spread and keep only the reachable payload tree.
function M.store_payload(blocks,angles,root)
    if not root then return end
    local plan={blocks={},angles={},next_state={rng_state=1},projectile_count=0,payload_root=true}
    local function collect(index)
        local n=#plan.blocks+1
        local block=Copy(blocks[index])
        plan.blocks[n]=block;plan.angles[n]=Copy(angles[index])
        for _,p in ipairs(block.projectiles) do
            plan.projectile_count=plan.projectile_count+(p.count or 1)
            if p.payload then p.payload=collect(p.payload) end
        end
        return n
    end
    collect(root)
    local sizes={}
    for i=#plan.blocks,1,-1 do
        local n=0
        for _,p in ipairs(plan.blocks[i].projectiles) do n=n+(p.count or 1)*(1+(sizes[p.payload] or 0)) end
        sizes[i]=n
    end
    plan.projectile_count=sizes[1]
    return plan
end

function M.execute(plan,owner,x,z,dx,dz,height,aim)
    if plan.projectile_count==0 then return true end
    local owner_key=tostring(owner.GUID)
    local token,err=manager:reserve(owner_key,plan.projectile_count)
    if not token then return false,err end
    local blocks=plan.expand_on_launch and plan.expand_on_launch(plan.blocks) or plan.blocks
    local sizes,angles={},{}
    local cast_context={arcs={},side_left=(Limits.cast>0 and Limits.cast or math.huge)-plan.projectile_count}
    local rng=RNG.new(plan.next_state.rng_state)
    for i,b in ipairs(blocks) do
        angles[i]={}
        for j,p in ipairs(b.projectiles) do
            angles[i][j]={}
            for k=1,p.count or 1 do
                angles[i][j][k]=plan.angles and plan.angles[i][j][k] or
                    ((p.formation or 0)+(p.angles and p.angles[k] or 0)+(rng:next()*2-1)*p.spread)*DEGREES
            end
        end
    end
    for i=#blocks,1,-1 do
        local n=0
        for _,p in ipairs(blocks[i].projectiles) do n=n+(p.count or 1)*(1+(sizes[p.payload] or 0)) end
        sizes[i]=n
    end
    local launch
    launch=function(reservation,index,px,pz,ax,az,h,hit_target)
        local objects={}
        for j,p in ipairs(blocks[index].projectiles) do
            for k=1,p.count or 1 do
                local group={remaining=1,child=p.payload,healed=p.flags.heal_ally and {}}
                group.cleanup=function()
                    manager:release(reservation,1,false)
                    group.remaining=group.remaining-1
                    if group.remaining==0 and group.child and not group.timer_queued then
                        manager:release(reservation,sizes[group.child],true);group.child=nil
                    end
                end
                if p.payload then
                    group.fire=function(cx,cz,ux,uz,target)
                        if not Effects.live(owner) then
                            if group.child then manager:release(reservation,sizes[group.child],true);group.child=nil end
                            return
                        end
                        local child,child_token=p.payload,reservation
                        if group.child then
                            group.child=nil
                        elseif p.event=="hit" and group.remaining>0 and sizes[child]>0 then
                            -- Only the first subtree is prepaid in the entity ledger.
                            -- Replays reuse the paid spell plan, under the same live caps.
                            child_token=manager:reserve(owner_key,sizes[child])
                            if not child_token then return end
                        else
                            return
                        end
                        return launch(child_token,child,cx,cz,ux,uz,h,target)
                    end
                end
                local e
                if p.kind~="instant" and not p.suppress_support then
                    e=SpawnPrefab((p.kind=="field" or p.kind=="note") and (p.kind=="note" and "nw_chord_d" or "nw_"..p.id) or p.kind=="melee" and ("nw_"..p.id.."_fx") or p.id=="spore_ball" and "nw_spore_ball_flight" or p.id=="end_beam" and "nw_end_beam" or "nw_projectile")
                    if not e then
                        for _,v in ipairs(objects) do if v.entity then v.entity:Remove() end end
                        manager:release(reservation,sizes[index],true)
                        return false
                    end
                end
                objects[#objects+1]={entity=e,p=p,angle=angles[index][j][k],group=group,k=k}
            end
        end
        manager:activate(reservation,#objects)
        for _,v in ipairs(objects) do
            local group,p=v.group,v.p
            local co,si=math.cos(v.angle),math.sin(v.angle)
            local ux,uz=ax*co-az*si,ax*si+az*co
            local px,pz=px,pz
            if p.kind~="projectile" and p.kind~="trigger" and require("nw/targeting").only_self(p.flags) then
                local ox,_,oz=owner.Transform:GetWorldPosition();px,pz=ox,oz
            end
            if p.suppress_support then
                group.cleanup()
            elseif p.kind=="instant" then
                if p.id=="explosion" then
                    Effects.blast(owner,px,pz,p)
                else
                    Effects.chain(owner,hit_target,px,pz,p,ux,uz,index==1 and not plan.payload_root)
                end
                group.cleanup()
            elseif p.kind=="melee" then
                require("nw/melee").launch(v.entity,owner,p,px,pz,ux,uz,group.cleanup)
            else
                local fx,fz=px,pz
                if (p.base or p.id)=="scatter" then
                    local offset=(v.k-2)*.35*require("nw/projectile_size").factor(p)
                    fx,fz=fx-az*offset,fz+ax*offset
                end
                if p.aim_range and aim and index==1 and not require("nw/targeting").only_self(p.flags) then
                    if p.id=="detonate" then
                        local ox,_,oz=owner.Transform:GetWorldPosition()
                        local tx,tz=aim.x-ox,aim.z-oz
                        local scale=math.min(1,p.aim_range/math.max(.001,math.sqrt(tx*tx+tz*tz)))
                        fx,fz=ox+tx*scale,oz+tz*scale
                    else
                        local r=math.min(p.aim_range,math.sqrt((aim.x-px)^2+(aim.z-pz)^2))
                        fx,fz=px+ux*r,pz+uz*r
                    end
                end
                if index==1 and (p.id=="crystal_mine" or p.id=="sleep_crystal") then
                    local ox,_,oz=owner.Transform:GetWorldPosition();fx,fz=ox,oz
                end
                local payload=p.id=="payload_egg" and M.store_payload(blocks,angles,p.payload) or nil
                v.entity:Launch(owner,p,fx,fz,ux,uz,group.cleanup,h,group.fire,payload)
                if owner._nw_neutral and v.entity:IsValid() then require("nw/payload_caster").retain(owner,v.entity) end
                local effects=v.entity._nw_effects
                if effects then
                    effects.context=cast_context
                    if p.flags.twin_arc then
                        local partner=cast_context.unpaired_field
                        if partner and partner:IsValid() then partner._nw_effects.partner=v.entity;cast_context.unpaired_field=nil
                        else cast_context.unpaired_field=v.entity end
                    end
                end
                if v.entity._shot then v.entity._shot.context=cast_context end
                local s=v.entity._shot
                if s then
                    if p.ballistic and index==1 and aim then
                        require("nw/engraved_flight").aim_ground(v.entity,s,math.sqrt((aim.x-fx)^2+(aim.z-fz)^2))
                    end
                    if p.engraving=="staff_tornado" and index==1 and aim then
                        s.aim_distance=math.sqrt((aim.x-fx)^2+(aim.z-fz)^2)
                        s.remaining=math.max(s.remaining,s.aim_distance/s.speed*(p.flight_lifetime_mult or 1))
                    end
                    s.fire=group.fire;s.group=group
                    if p.flags.twin_arc then
                        local partner=cast_context.unpaired
                        if partner and partner:IsValid() then partner._shot.partner=v.entity;cast_context.unpaired=nil
                        else cast_context.unpaired=v.entity end
                    end
                    s.timer_rank=v.k==2 and 0 or v.k
                    s.fan_angle=((p.formation or 0)+(p.angles and p.angles[v.k] or 0))*DEGREES
                end
            end
        end
        return true
    end
    if not launch(token,1,x,z,dx,dz,height) then return false,"SPAWN_FAILED" end
    plan.next_state.rng_state=rng.state
    return true
end
return M
