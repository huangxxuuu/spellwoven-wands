local C=require("nw/constants/projectile_runtime").collision
local Geometry=require("nw/geometry")
local Targeting=require("nw/targeting")
local Policy=require("nw/target_policy")
local Perf=require("nw/perf")
local M={}
local Size=require("nw/projectile_size")
local Limits=require("nw/spell_limits")
local Bounds=require("nw/world_bounds")
local TOOL_TARGETS={default=true}
local CELL=C.cell
local RADIUS=C.query_radius
function M.candidates(cache,x,z,nx,nz,find,flags,hit_radius,force_objects)
    local cx,cz=math.floor((x+nx)/2/CELL),math.floor((z+nz)/2/CELL)
    local dx,dz=nx-x,nz-z
    local pad=math.ceil(math.sqrt(dx*dx+dz*dz)/2+math.max(0,(hit_radius or C.default_hit_radius)-C.default_hit_radius))
    local tags=Targeting.scan_tags(flags,force_objects)
    local objects=tags~=Targeting.scan_tags()
    local selected=flags and (flags.targets or flags._nw_target_bypass)
    local key=cx..":"..cz..":"..pad..(selected and ":selected" or objects and ":objects" or "")
    local list=cache[key]
    if not list then
        list=find((cx+.5)*CELL,0,(cz+.5)*CELL,RADIUS+CELL/math.sqrt(2)+pad,nil,Targeting.scan_exclude,tags)
        cache[key]=list
        if Perf.sample then
            Perf.sample.queries=Perf.sample.queries+1
            Perf.sample.candidates=Perf.sample.candidates+#list
        end
    end
    return list
end
local function find(...) return TheSim:FindEntities(...) end

local Effects=require("nw/spell_effects")
local Engraving=require("nw/engraved_impact")
local Flight=require("nw/flight")
local AnimatedFlight=require("nw/elemental_flight")
local Triggers=require("nw/projectile_triggers")
local Beam=require("nw/end_beam")
local timer=Triggers.timer
local function active(inst,s)
    if not inst:IsValid() then return false end
    if not Effects.live(s.owner) then inst:Remove();return false end
    return true
end
function M.contact_fx(s,x,z)
    local id=AnimatedFlight.resolve(s.p and (s.p.base or s.p.id))
    if id then
        local fx=Effects.fx("nw_elemental_hit_fx",x,z)
        if fx then fx:SetImpact(id,s.height or require("nw/muzzle").default_height,Size.factor(s.p),math.atan2(s.dz,s.dx)) end
    end
end
local function impact(s,target,x,z)
    M.contact_fx(s,x,z)
    Triggers.hit(s,target,x,z)
end
local function beam_candidates(cache,x,z,nx,nz,flags,radius)
    return M.candidates(cache,x,z,nx,nz,find,flags,radius)
end
local function beam_hit(inst,s,target,x,z,kind)
    if kind=="ally" then
        if s.group and s.group.healed then s.group.healed[target]=true end
        target.components.health:DoDelta(s.p.flags.heal_ally.heal,false,"nw_heal")
        M.heal_fx(x,z)
        M.contact_fx(s,x,z)
    else
        if kind=="prop" then target._nw_break(s.owner)
        else require("nw/expanded_hits").impact(s,target,x,z) end
        impact(s,target,x,z)
    end
end
local function finish(inst,s,x,z,natural)
    if s.p and s.p.flags and s.p.flags.dark then
        require("nw/dark_fog").leave(s.owner,x,z,s.p)
    end
    if s.placement then require("nw/field_motion").stop(inst,x,z);return end
    if s.beam and not Beam.stop(inst,s,x,z,GetTime()) then return end
    local p=s.p
    local natural_effects=p and (natural or p.engraving=="orangestaff")
    if natural_effects then
        if p.engraving and not p.ballistic then Engraving.finish(s,x,z) end
        if p.id=="spore_ball" then Effects.blast(s.owner,x,z,{damage=s.damage,radius=Size.factor(p),flags=s.p.flags,quiet_burst=true,journal_id=p.journal_id or p.id,_nw_root=p._nw_root}) end
    end
    if p and (natural_effects or s.beam) and (p.end_damage or p.id=="land_hook") then require("nw/expanded_hits").finish(s,x,z) end
    if natural_effects and p.flags.light then Effects.afterlight(s.owner,x,z) end
    Triggers.finish(s,x,z)
    if not s.beam or #s.beam.segments==0 then inst:Remove()
    elseif inst:IsValid() then Beam.publish(inst,s,GetTime(),true) end
end
local function rebound(inst,s,c,ix,iz,length,fraction)
    if not s.bounces or s.bounces<=0 then return false end
    local ux,uz=ix-c.tx,iz-c.tz
    local n=math.sqrt(ux*ux+uz*uz)
    if n<=C.wall_epsilon then return false end
    ux,uz=ux/n,uz/n
    local dot=s.dx*ux+s.dz*uz
    s.dx,s.dz=s.dx-2*dot*ux,s.dz-2*dot*uz
    s.x,s.z=ix+ux*C.rebound_offset,iz+uz*C.rebound_offset
    s.travelled=s.travelled-length*fraction*(1-c.t)
    s.lastwall=c.e;s.bounces=s.bounces-1;s.escaped=true
    local speed=math.min(Limits.max_speed,s.motor_speed or s.speed)
    local accel_factor=s.accel_factor
    Flight.reset(s,s.dx,s.dz)
    s.accel_factor=accel_factor or s.accel_factor
    s.vx,s.vz=s.dx*speed,s.dz*speed
    inst.Physics:Teleport(s.x,0,s.z)
    inst.Transform:SetRotation(-math.atan2(s.dz,s.dx)/DEGREES)
    Limits.set_motor_velocity(inst,speed,0,0)
    return true
end
function M.step(inst,now,cache,timers)
    local s=inst._shot or inst._nw_motion
    if s and s.placement then
        if not require("nw/field_motion").prepare(inst,s,now) then return end
    elseif not s or not Effects.live(s.owner) then inst:Remove();return end
    local p=s.p
    local flags=Policy.flags(p)
    if Beam.is(p) then
        Beam.start(inst,s)
        if s.beam.ended then
            if Beam.step(inst,s,now,cache,beam_candidates,beam_hit) then Beam.publish(inst,s,now) end
            return
        end
    end
    local key=not s.placement and p and p.engraving
    if key=="shieldofterror" then require("nw/orbit_shield").update(inst,s,now,timers);return end
    local x,z=s.x,s.z
    local nx,ny,nz=inst.Transform:GetWorldPosition()
    if not s.placement and not (p and p.ballistic) then Flight.ground(inst,nx,ny,nz) end
    local dx,dz=nx-x,nz-z
    local length=math.sqrt(dx*dx+dz*dz)
    local dt=math.max(0,now-s.time)
    local range=Limits.range>0 and Limits.range or math.huge
    local fraction=math.max(0,math.min(1,dt>0 and s.remaining/dt or 1,length>0 and (range-s.travelled)/length or 1))
    if key=="staff_tornado" and s.aim_distance and length>0 then
        fraction=math.min(fraction, math.max(0,s.aim_distance-s.travelled)/length)
    end
    local boundary=Bounds.clip(x,z,x+dx*fraction,z+dz*fraction)
    local shore=s.placement and require("nw/ground_fields").clip(s,x,z,x+dx*fraction,z+dz*fraction)
    if shore and (not boundary or shore<boundary) then
        fraction=fraction*shore;boundary=nil
    else shore=nil end
    if boundary==0 then inst:Remove();return end
    if boundary then fraction=fraction*boundary end
    nx,nz=x+dx*fraction,z+dz*fraction
    if not s.placement then
        local intercepted,contact=require("nw/guard_ring").intercept(inst,x,z,nx,nz)
        if intercepted then
            if flags.dark and contact then
                require("nw/dark_fog").trail(inst,s,x,z,x+(nx-x)*contact,z+(nz-z)*contact)
            end
            return
        end
    end
    if s.beam and boundary then inst:Remove();return end
    local age=s.age or 0
    local elapsed=dt*fraction
    local deadline=p and p.event=="timer" and not s.timer_done and (p.time or C.timer_delay)
    local trail_t=0
    local function advance_trail(t)
        if t>trail_t and flags.dark then
            require("nw/dark_fog").trail(inst,s,x+(nx-x)*trail_t,z+(nz-z)*trail_t,x+(nx-x)*t,z+(nz-z)*t)
        end
        trail_t=math.max(trail_t,t)
    end
    local function advance_timer(t)
        if deadline and deadline<=age+t*elapsed+C.time_epsilon then
            local f=elapsed>0 and math.max(0,math.min(1,(deadline-age)/elapsed)) or 0
            advance_trail(f)
            timer(s,x+(nx-x)*f,z+(nz-z)*f,timers)
            deadline=nil;s.timer_done=true
            if not inst:IsValid() then return end
        end
        advance_trail(t)
    end
    s.time=now;s.age=age+elapsed;s.remaining=s.remaining-elapsed
    s.x,s.z=nx,nz;s.travelled=s.travelled+length*fraction
    if Perf.sample then Perf.sample.steps=Perf.sample.steps+1 end
    if not s.placement and (flags.side_embers or flags.halo or s.partner) then require("nw/expanded_hits").step(s,now) end
    if s.ignore_self then
        local ox,_,oz=s.owner.Transform:GetWorldPosition()
        local radius=s.owner:GetPhysicsRadius(C.target_radius)+Size.radius(p,s.age)
        if (x-ox)^2+(z-oz)^2>radius^2 then s.ignore_self=false end
    end
    if s.beam and not Beam.step(inst,s,now,cache,beam_candidates,beam_hit) then return end
    local contacts
    local filter=Engraving.filters[key]
    local skip_contacts=key=="staff_tornado" or key=="farm_hoe" or key=="chum"
    local hit_radius=Size.radius(p,s.age)
    local proximity=s.placement and inst._nw_proximity
    local query_radius=proximity and math.max(hit_radius,proximity.radius) or hit_radius
    for _,e in ipairs(not skip_contacts and M.candidates(cache,x,z,nx,nz,find,flags,query_radius,filter) or {}) do
        if Perf.sample then Perf.sample.visits=Perf.sample.visits+1 end
        if e~=inst and not (s.ignore_walls and e:HasTag("wall")) and (e~=s.owner or flags.targets and flags.targets.self and not s.ignore_self) and e:IsValid()
            and (proximity or not s.hit or not s.hit[e] or s.age+C.time_epsilon>=s.hit[e] or s.beam and (e:HasTag("wall") or e._nw_break)) then
            local tx,_,tz=e.Transform:GetWorldPosition()
            local sensing=proximity and Targeting.selected(s.owner,e,flags)
            local t=Geometry.hit(x,z,nx,nz,tx,tz,sensing and proximity.radius or math.min(C.max_target_radius,e:GetPhysicsRadius(C.target_radius))+hit_radius)
            if t then
                local wall=e:HasTag("wall") and e.components.health and not e.components.health:IsDead()
                local ally=not s.placement and not (p and p.heal) and flags.heal_ally and Effects.ally(s.owner,e,flags) and not s.group.healed[e]
                local prop=Targeting.selectable_prop(s.owner,e,flags)
                if p and p.id=="gust" and e._nw_stored and e._nw_stored.p.id~="payload_egg" then prop=false end
                local selected=not (wall and flags.phase_wall) and Targeting.selected(s.owner,e,flags)
                local specific=filter and Engraving.accepts(key,e) and Targeting.accepts(s.owner,e,flags,TOOL_TARGETS)
                if specific or not filter and (prop or selected or (wall and not flags.targets and not flags.phase_wall and not (s.lastwall==e and t==0 and dx*(x-tx)+dz*(z-tz)>0))
                    or not wall and ally) then
                    contacts=contacts or {}
                    contacts[#contacts+1]={e=e,t=t,specific=specific,prop=prop,selected=selected,wall=wall,ally=ally,tx=tx,tz=tz,proximity=sensing}
                end
            end
        end
    end
    if key=="lighter" then
        local t=1
        if contacts and not s.hits_left then for _,c in ipairs(contacts) do t=math.min(t,c.t) end end
        require("nw/engraved_fire").absorb(s.owner,x,z,x+(nx-x)*t,z+(nz-z)*t,(p.fire_radius or C.fire_radius)*Size.factor(p),p)
    end
    if s.beam then
        if contacts and #contacts>1 then table.sort(contacts,function(a,b) return a.t<b.t or a.t==b.t and a.e.GUID<b.e.GUID end) end
        for _,c in ipairs(contacts or {}) do
            local ix,iz=x+(nx-x)*c.t,z+(nz-z)*c.t
            advance_timer(c.t)
            if not inst:IsValid() then return end
            if not Effects.live(s.owner) then inst:Remove();return end
            local target=c.e
            if target:IsValid() then
                local wall=c.wall and not c.selected and target.components.health and not target.components.health:IsDead()
                if wall then
                    if Beam.claim(s,target,now) then impact(s,target,ix,iz) end
                    if not inst:IsValid() then return end
                    if not Effects.live(s.owner) then inst:Remove();return end
                    Beam.record(s,x,z,ix,iz,now)
                    if rebound(inst,s,c,ix,iz,length,fraction) then Beam.publish(inst,s,now);return end
                    finish(inst,s,ix,iz,true);return
                end
                local kind=Beam.classify(s,target)
                if kind then
                    Beam.hit(inst,s,target,ix,iz,s.dx,s.dz,now,beam_hit,kind)
                    if not inst:IsValid() then return end
                    if not Effects.live(s.owner) then inst:Remove();return end
                    if kind=="prop" or kind=="ally" then
                        Beam.record(s,x,z,ix,iz,now)
                        finish(inst,s,ix,iz,kind=="prop");return
                    end
                end
            end
        end
        advance_timer(1)
        if not inst:IsValid() then return end
        if not Effects.live(s.owner) then inst:Remove();return end
        Beam.record(s,x,z,nx,nz,now)
        if s.remaining<=C.time_epsilon or s.travelled>=range-C.time_epsilon then finish(inst,s,nx,nz,true)
        elseif not Flight.steer(inst,s,dt) then finish(inst,s,nx,nz,false)
        else Beam.publish(inst,s,now) end
        return
    end
    if contacts then
        if #contacts>1 then table.sort(contacts,function(a,b) return a.t<b.t or a.t==b.t and a.e.GUID<b.e.GUID end) end
        for _,c in ipairs(contacts) do
            local ix,iz=x+(nx-x)*c.t,z+(nz-z)*c.t
            advance_timer(c.t)
            if not active(inst,s) then return end
            if c.e:IsValid() and not (c.e.components.health and c.e.components.health:IsDead()) then
                c.prop=Targeting.selectable_prop(s.owner,c.e,flags)
                if p and p.id=="gust" and c.e._nw_stored and c.e._nw_stored.p.id~="payload_egg" then c.prop=false end
                c.selected=not (c.wall and flags.phase_wall) and Targeting.selected(s.owner,c.e,flags)
                c.specific=filter and Engraving.accepts(key,c.e) and Targeting.accepts(s.owner,c.e,flags,TOOL_TARGETS)
                local admitted=c.specific or not filter and (c.prop or c.selected or c.wall and not flags.targets and not flags.phase_wall)
                    or c.ally and Effects.ally(s.owner,c.e,flags)
                if admitted then
                    if s.placement then
                        if c.proximity then
                            s.x,s.z=ix,iz
                            inst.Physics:Teleport(ix,0,iz)
                            proximity.trigger(c.e)
                            return
                        end
                        if c.wall and not c.selected then
                            if rebound(inst,s,c,ix,iz,length,fraction) then return end
                            finish(inst,s,ix,iz,false);return
                        end
                        s.hit[c.e]=s.age+C.field_hit_interval
                        if not c.wall then require("nw/explosions").hit(s.owner,p,ix,iz) end
                        if not s.pass_creatures then
                            if s.hits_left then s.hits_left=s.hits_left-1 end
                            if not s.hits_left or s.hits_left<=0 then finish(inst,s,ix,iz,false);return end
                        end
                    elseif p and p.id=="gust" and c.prop and c.e._nw_stored and c.e._nw_stored.p.id=="payload_egg" then
                        local speed=s.motor_speed or s.speed
                        require("nw/field_motion").push_egg(c.e,s.owner,s.dx,s.dz,speed*C.egg_impulse_mult)
                        impact(s,c.e,ix,iz);if active(inst,s) then finish(inst,s,ix,iz,true) end;return
                    elseif key and (not c.wall or c.selected or key=="orangestaff" or p.ballistic or filter or not s.bounces or s.bounces<=0) and (c.specific or c.wall or c.prop or Targeting.selected(s.owner,c.e,flags)) then
                        local invalid=filter and not Engraving.accepts(key,c.e)
                        local handled=Engraving.hit(s,c.e,ix,iz)
                        if not active(inst,s) then return end
                        if not handled then require("nw/expanded_hits").impact(s,c.e,ix,iz) end
                        impact(s,c.e,ix,iz)
                        if not active(inst,s) then return end
                        if s.hits_left then
                            s.hit[c.e]=(p.ballistic or key=="voidcloth_scythe") and math.huge or s.age+C.hit_interval;s.hits_left=s.hits_left-1
                        end
                        if (not handled and not c.e.components.health) and (not s.hits_left or s.hits_left<=0) then Engraving.fade(ix,iz) end
                        if invalid or not s.hits_left or s.hits_left<=0 then finish(inst,s,ix,iz,true);return end
                    elseif c.prop and not (p and p.heal) and c.e:IsValid() and c.e._nw_break then
                        c.e._nw_break(s.owner)
                        if not inst:IsValid() then return end
                        if not Effects.live(s.owner) then inst:Remove();return end
                        impact(s,c.e,ix,iz)
                        if not inst:IsValid() then return end
                        if not Effects.live(s.owner) then inst:Remove();return end
                        if s.hits_left then
                            s.hit[c.e]=s.age+C.hit_interval;s.hits_left=s.hits_left-1
                        end
                        if not s.hits_left or s.hits_left<=0 then finish(inst,s,ix,iz,true);return end
                    elseif c.wall and not c.selected then
                        impact(s,c.e,ix,iz)
                        if not active(inst,s) then return end
                        if rebound(inst,s,c,ix,iz,length,fraction) then return end
                        Engraving.fade(ix,iz);finish(inst,s,ix,iz,true);return
                    elseif c.ally and Effects.ally(s.owner,c.e,flags) then
                        s.group.healed[c.e]=true
                        c.e.components.health:DoDelta(flags.heal_ally.heal,false,"nw_heal")
                        M.heal_fx(c.tx,c.tz)
                        M.contact_fx(s,ix,iz)
                        finish(inst,s,ix,iz,false);return
                    elseif c.e:IsValid() and (c.prop and p and p.heal or Targeting.selected(s.owner,c.e,flags)) then
                        if p and p.heal then
                            local health=c.e.components.health
                            if health and not health:IsDead() then
                                health:DoDelta(p.heal,false,"nw_heal")
                                M.heal_fx(c.tx,c.tz)
                            end
                        elseif p and p.id=="spore_ball" then
                            impact(s,c.e,ix,iz);if active(inst,s) then finish(inst,s,ix,iz,true) end;return
                        elseif p and (p.name or flags.wet_weak or flags.crit or flags.chill_touch or flags.melee_mark) then
                            require("nw/expanded_hits").impact(s,c.e,ix,iz)
                        elseif p and (p.burn_damage or p.freeze or flags.leech or flags.knockback) then
                            Effects.direct(s.owner,c.e,p,s.dx,s.dz)
                        else Targeting.damage(s.owner,c.e,s.damage,flags,p) end
                        if not s.hits_left or s.hits_left<=1 then
                            if not (p and p.heal and c.e.components.health) then Engraving.fade(ix,iz) end
                        end
                        impact(s,c.e,ix,iz)
                        if not active(inst,s) then return end
                        if s.hits_left then
                            s.hit[c.e]=s.age+C.hit_interval;s.hits_left=s.hits_left-1
                        end
                        if not s.hits_left or s.hits_left<=0 then finish(inst,s,ix,iz,true);return end
                    end
                end
            end
        end
    end
    advance_timer(1)
    if not active(inst,s) then return end
    if shore then require("nw/field_motion").stop(inst,nx,nz);return end
    if boundary then inst:Remove();return end
    if key=="staff_tornado" and s.aim_distance and s.travelled+C.distance_epsilon>=s.aim_distance then finish(inst,s,nx,nz,true);return end
    if p and p.ballistic then
        if s.remaining<=C.time_epsilon or s.travelled>=range-C.time_epsilon then Engraving.fade(nx,nz);finish(inst,s,nx,nz,false)
        else Flight.steer(inst,s,dt) end
        return
    end
    if s.remaining<=C.time_epsilon or s.travelled>=range-C.time_epsilon then finish(inst,s,nx,nz,true)
    elseif p and not Flight.steer(inst,s,dt) then finish(inst,s,nx,nz,key~=nil) end
end
function M.heal_fx(x,z) Effects.fx("nw_heal_fx",x,z) end
local function tick(world)
    local pool=world._nw_projectiles
    local cache,timers={},{};local now=GetTime()
    for i=#pool.items,1,-1 do
        local inst=pool.items[i]
        if inst:IsValid() then
            M.step(inst,now,cache,timers)
            if inst:IsValid() and inst._shot.native then require("nw/engraved_flight").sync_native(inst,inst._shot) end
        end
        if not inst:IsValid() then
            pool.items[i]=pool.items[#pool.items];pool.items[#pool.items]=nil
        end
    end
    for group,t in pairs(timers) do
        group.timer_queued=nil
        t.fire(t.x,t.z,t.dx,t.dz)
    end
    if #pool.items==0 then pool.task:Cancel();pool.task=nil end
end
function M.add(inst)
    local pool=TheWorld._nw_projectiles
    if not pool then pool={items={}};TheWorld._nw_projectiles=pool end
    pool.items[#pool.items+1]=inst
    if not pool.task then pool.task=TheWorld:DoPeriodicTask(FRAMES,tick) end
end
return M
