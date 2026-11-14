local C=require("nw/constants/casting")
local Budget=require("nw/entity_limits")
local RNG=require("nw/rng")
local Effects=require("nw/spell_effects")
local Limits=require("nw/spell_limits")
local Templates=require("nw/cast_templates")
local Damage=require("nw/balance_damage")
local Policy=require("nw/target_policy")
local M={}
local function no_release() end
function M.set_projectile_limit(value) Budget.configure("projectiles",value) end
function M.stats() return Budget.stats() end
function M.owner_used(owner) return Budget.owner_used(owner) end

M.store_payload=Templates.snapshot

function M.execute(plan,owner,x,z,dx,dz,height,aim,inherited_root)
    if plan.projectile_count==0 then return true end
    local blocks=plan.blocks
    local sizes,invalid=Templates.sizes(blocks)
    if not sizes then return false,invalid end
    local resolve=Templates.resolver()
    local root=Damage.root(inherited_root)
    local rooted={}
    local cast_context={arcs={},side_left=math.huge}
    local draw_rng=RNG.new(plan.next_state.rng_state)
    local rng=draw_rng:fork()
    local launch
    launch=function(index,px,pz,ax,az,h,hit_target,scale,secondary,depth)
        local objects={}
        local block=blocks[index]
        if #block.projectiles==0 then return true end
        if Limits.depth>0 and depth>Limits.depth then
            require("nw/limit_feedback").limited(owner);return true
        end
        local fraction=(scale or 1)*(block.copy_damage or 1)
        for copy=1,block.copies or 1 do
            local emitted=0
            local limited=secondary or (block.copy_damage~=nil and copy>1)
            for _,original in ipairs(block.projectiles) do
                local p=resolve(original,fraction,limited)
                if root then
                    local variant=rooted[p]
                    if not variant then variant=Damage.parameters(p,root);rooted[p]=variant end
                    p=variant
                end
                if p.suppress_support then
                    for k=1,p.count or 1 do rng:next() end
                end
                for k=1,p.suppress_support and 0 or p.count or 1 do
                    local category=Budget.category(p)
                    local release=p.kind=="instant" and no_release or Budget.acquire(owner,category)
                    if not release then break end
                    emitted=emitted+1
                    local group={remaining=1,child=p.payload,healed=p.flags.heal_ally and {}}
                    local bound=false
                    group.cleanup=function()
                        if category=="projectiles" or not bound then release() end
                        group.remaining=0
                        if not group.timer_queued then group.child=nil end
                    end
                    if p.payload then
                        group.fire=function(cx,cz,ux,uz,target)
                            if not Effects.live(owner) then group.child=nil;return end
                            if group.child then group.child=nil
                            elseif p.event~="hit" or group.remaining<=0 then return end
                            return launch(p.payload,cx,cz,ux,uz,h,target,fraction,limited,depth+1)
                        end
                    end
                    local e
                    if p.kind~="instant" and not p.suppress_support then
                        e=SpawnPrefab((p.kind=="field" or p.kind=="note") and (p.kind=="note" and "nw_chord_d" or "nw_"..p.id) or p.kind=="melee" and ("nw_"..p.id.."_fx") or p.id=="spore_ball" and "nw_spore_ball_flight" or p.id=="end_beam" and "nw_end_beam" or "nw_projectile")
                        if not e then
                            release()
                            for _,v in ipairs(objects) do
                                if v.entity and not v.entity._nw_budget_evicted then v.entity:Remove() end
                                v.release()
                            end
                            return false
                        end
                    end
                    if e then
                        Damage.tag(e,p)
                        Budget.bind(e,release);bound=e.ListenForEvent~=nil
                    end
                    local angle=((p.formation or 0)+(p.angles and p.angles[k] or 0)
                        +(rng:next()*2-1)*(p.spread or 0))*DEGREES
                    objects[#objects+1]={entity=e,p=p,angle=angle,group=group,k=k,secondary=limited,release=release}
                end
            end
            if emitted==0 then break end
        end
        for _,v in ipairs(objects) do
            if v.entity and v.entity._nw_budget_evicted then v.group.cleanup()
            else
                local group,p=v.group,v.p
                local target_flags=Policy.flags(p)
                local co,si=math.cos(v.angle),math.sin(v.angle)
                local ux,uz=ax*co-az*si,ax*si+az*co
                local px,pz=px,pz
                if p.kind~="projectile" and p.kind~="trigger" and require("nw/targeting").only_self(target_flags) then
                    local ox,_,oz=owner.Transform:GetWorldPosition();px,pz=ox,oz
                end
                if p.suppress_support then
                    group.cleanup()
                elseif p.kind=="instant" then
                    if p.id=="explosion" then
                        Effects.blast(owner,px,pz,p)
                        group.cleanup()
                    else
                        Effects.chain(owner,hit_target,px,pz,p,ux,uz,index==1 and not plan.payload_root,group.fire,group.cleanup)
                    end
                elseif p.kind=="melee" then
                    require("nw/melee").launch(v.entity,owner,p,px,pz,ux,uz,group.cleanup)
                else
                    local fx,fz=px,pz
                    if (p.base or p.id)=="scatter" then
                        local offset=(v.k-2)*C.scatter_offset*require("nw/projectile_size").factor(p)
                        fx,fz=fx-az*offset,fz+ax*offset
                    end
                    if p.aim_range and aim and index==1 and not require("nw/targeting").only_self(target_flags) then
                        if p.id=="detonate" then
                            local ox,_,oz=owner.Transform:GetWorldPosition()
                            local tx,tz=aim.x-ox,aim.z-oz
                            local scale=math.min(1,p.aim_range/math.max(C.aim.direction_epsilon,math.sqrt(tx*tx+tz*tz)))
                            fx,fz=ox+tx*scale,oz+tz*scale
                        else
                            local r=math.min(p.aim_range,math.sqrt((aim.x-px)^2+(aim.z-pz)^2))
                            fx,fz=px+ux*r,pz+uz*r
                        end
                    end
                    if index==1 and (p.id=="crystal_mine" or p.id=="sleep_crystal") then
                        local ox,_,oz=owner.Transform:GetWorldPosition();fx,fz=ox,oz
                    end
                    local payload=p.id=="payload_egg" and M.store_payload(blocks,p.payload,fraction,v.secondary,rng:fork().state) or nil
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
        end
        return true
    end
    if not launch(1,x,z,dx,dz,height,nil,plan.payload_scale,plan.payload_secondary,blocks[1].depth or 0) then return false,"SPAWN_FAILED" end
    plan.next_state.rng_state=draw_rng.state
    return true
end
return M
