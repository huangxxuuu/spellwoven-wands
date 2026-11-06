-- One server collision loop per world. Native Physics moves the entities;
-- this module sweeps the actual distance travelled and alone applies damage.
local Geometry=require("nw/geometry")
local Targeting=require("nw/targeting")
local Perf=require("nw/perf")
local M={}
local Size=require("nw/projectile_size")
local Limits=require("nw/spell_limits")
local Bounds=require("nw/world_bounds")
local EXCLUDE={"INLIMBO","FX","DECOR"}
local INCLUDE={"_combat","wall"}
local CELL=4
local RADIUS=3.12 -- must cover target radius cap plus hit margin
local EXTENDED={"_combat","wall"}
for _,tag in ipairs(Targeting.object_tags) do EXTENDED[#EXTENDED+1]=tag end
function M.candidates(cache,x,z,nx,nz,find,scope,hit_radius)
    local cx,cz=math.floor((x+nx)/2/CELL),math.floor((z+nz)/2/CELL)
    local dx,dz=nx-x,nz-z
    local pad=math.ceil(math.sqrt(dx*dx+dz*dz)/2+math.max(0,(hit_radius or .12)-.12))
    local objects=scope and (scope.building or scope.nature)
    local key=cx..":"..cz..":"..pad..(objects and ":objects" or "")
    local list=cache[key]
    if not list then
        list=find((cx+.5)*CELL,0,(cz+.5)*CELL,RADIUS+CELL/math.sqrt(2)+pad,nil,EXCLUDE,objects and EXTENDED or INCLUDE)
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
local Triggers=require("nw/projectile_triggers")
local impact,timer=Triggers.hit,Triggers.timer
local function finish(inst,s,x,z,natural)
    if s.placement then require("nw/field_motion").stop(inst,x,z);return end
    local p=s.p
    if p and (natural or p.engraving=="orangestaff") then
        if p.engraving and not p.ballistic then Engraving.finish(s,x,z) end
        if p.id=="spore_ball" then Effects.blast(s.owner,x,z,{damage=s.damage,radius=Size.factor(p),flags=s.p.flags}) end
        if p.end_damage or p.id=="land_hook" then require("nw/expanded_hits").finish(s,x,z) end
        if p.flags.light then Effects.afterlight(s.owner,x,z) end
    end
    Triggers.finish(s,x,z)
    inst:Remove()
end
local function rebound(inst,s,c,ix,iz,length,fraction)
    if not s.bounces or s.bounces<=0 then return false end
    local ux,uz=ix-c.tx,iz-c.tz
    local n=math.sqrt(ux*ux+uz*uz)
    if n<=.0001 then return false end
    ux,uz=ux/n,uz/n
    local dot=s.dx*ux+s.dz*uz
    s.dx,s.dz=s.dx-2*dot*ux,s.dz-2*dot*uz
    s.x,s.z=ix+ux*.03,iz+uz*.03
    s.travelled=s.travelled-length*fraction*(1-c.t)
    s.lastwall=c.e;s.bounces=s.bounces-1;s.escaped=true
    local speed=s.motor_speed or s.speed
    local accel_factor=s.accel_factor
    Flight.reset(s,s.dx,s.dz)
    s.accel_factor=accel_factor or s.accel_factor
    s.vx,s.vz=s.dx*speed,s.dz*speed
    inst.Physics:Teleport(s.x,0,s.z)
    inst.Transform:SetRotation(-math.atan2(s.dz,s.dx)/DEGREES)
    inst.Physics:SetMotorVel(speed,0,0)
    return true
end
function M.step(inst,now,cache,timers)
    local s=inst._shot or inst._nw_motion
    if s and s.placement then
        if not require("nw/field_motion").prepare(inst,s,now) then return end
    elseif not s or not Effects.live(s.owner) then inst:Remove();return end
    local p=s.p
    local flags=p and p.flags or {}
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
    local age=s.age or 0
    local elapsed=dt*fraction
    local deadline=p and p.event=="timer" and not s.timer_done and (p.time or .5)
    local function advance_timer(t)
        if deadline and deadline<=age+t*elapsed+.000001 then
            local f=elapsed>0 and math.max(0,math.min(1,(deadline-age)/elapsed)) or 0
            timer(s,x+(nx-x)*f,z+(nz-z)*f,timers)
            deadline=nil;s.timer_done=true
        end
    end
    s.time=now;s.age=age+elapsed;s.remaining=s.remaining-elapsed
    s.x,s.z=nx,nz;s.travelled=s.travelled+length*fraction
    if Perf.sample then Perf.sample.steps=Perf.sample.steps+1 end
    if flags.side_embers or flags.halo or s.partner then require("nw/expanded_hits").step(s,now) end
    if s.ignore_self then
        local ox,_,oz=s.owner.Transform:GetWorldPosition()
        local radius=s.owner:GetPhysicsRadius(.5)+Size.radius(p,s.age)
        if (x-ox)^2+(z-oz)^2>radius^2 then s.ignore_self=false end
    end
    local contacts
    local filter=Engraving.filters[key]
    local scope=flags.targets or (filter and {nature=true})
    local skip_contacts=key=="staff_tornado" or key=="farm_hoe" or key=="chum"
    local hit_radius=Size.radius(p,s.age)
    for _,e in ipairs(not skip_contacts and M.candidates(cache,x,z,nx,nz,find,scope,hit_radius) or {}) do
        if Perf.sample then Perf.sample.visits=Perf.sample.visits+1 end
        -- Floating staff stars pass over walls even when buildings are selected.
        if e~=inst and not (s.ignore_walls and e:HasTag("wall")) and (e~=s.owner or flags.targets and flags.targets.self and not s.ignore_self) and e:IsValid() and (not s.hit or not s.hit[e] or s.age+.000001>=s.hit[e]) then
            local tx,_,tz=e.Transform:GetWorldPosition()
            local t=Geometry.hit(x,z,nx,nz,tx,tz,math.min(3,e:GetPhysicsRadius(.5))+hit_radius)
            if t then
                local wall=e:HasTag("wall") and e.components.health and not e.components.health:IsDead()
                local ally=not s.placement and not (p and p.heal) and flags.heal_ally and Effects.ally(s.owner,e) and not s.group.healed[e]
                local prop=require("nw/expanded_fields").can_break(e,s.owner) and (Targeting.breakable(e) or not flags.targets or flags.targets.building)
                if p and p.id=="gust" and e._nw_stored and e._nw_stored.p.id~="payload_egg" then prop=false end
                local selected=not (wall and flags.phase_wall) and flags.targets and (flags.targets.nature or flags.targets.building)
                    and Targeting.object(e) and Targeting.matches(s.owner,e,flags.targets)
                local specific=filter and not flags.targets and Engraving.accepts(key,e)
                if specific or (not filter or flags.targets) and (prop or selected or (wall and not flags.phase_wall and not (s.lastwall==e and t==0 and dx*(x-tx)+dz*(z-tz)>0))
                    or not wall and (ally or Targeting.allowed(s.owner,e,flags))) then
                    contacts=contacts or {}
                    contacts[#contacts+1]={e=e,t=t,specific=specific,prop=prop,selected=selected,wall=wall,ally=ally,tx=tx,tz=tz}
                end
            end
        end
    end
    if key=="lighter" then
        local t=1
        if contacts and not s.hits_left then for _,c in ipairs(contacts) do t=math.min(t,c.t) end end
        require("nw/engraved_fire").absorb(s.owner,x,z,x+(nx-x)*t,z+(nz-z)*t,(p.fire_radius or 3)*Size.factor(p))
    end
    if contacts then
        if #contacts>1 then table.sort(contacts,function(a,b) return a.t<b.t or a.t==b.t and a.e.GUID<b.e.GUID end) end
        for _,c in ipairs(contacts) do
            local ix,iz=x+(nx-x)*c.t,z+(nz-z)*c.t
            advance_timer(c.t)
            if s.placement then
                if c.wall and not c.selected then
                    if rebound(inst,s,c,ix,iz,length,fraction) then return end
                    finish(inst,s,ix,iz,false);return
                end
                if s.hits_left then s.hit[c.e]=s.age+.1;s.hits_left=s.hits_left-1 end
                if not s.hits_left or s.hits_left<=0 then finish(inst,s,ix,iz,false);return end
            elseif p and p.id=="gust" and c.prop and c.e._nw_stored and c.e._nw_stored.p.id=="payload_egg" then
                local speed=s.motor_speed or s.speed
                require("nw/field_motion").push_egg(c.e,s.owner,s.dx,s.dz,speed*.5)
                impact(s,c.e,ix,iz);finish(inst,s,ix,iz,true);return
            elseif key and (not c.wall or c.selected or key=="orangestaff" or p.ballistic or filter or not s.bounces or s.bounces<=0) and (c.specific or c.selected or c.wall or c.prop or Targeting.allowed(s.owner,c.e,flags)) then
                local invalid=filter and not Engraving.accepts(key,c.e)
                local handled=Engraving.hit(s,c.e,ix,iz)
                if not handled then require("nw/expanded_hits").impact(s,c.e,ix,iz) end
                impact(s,c.e,ix,iz)
                if s.hits_left then
                    s.hit[c.e]=(p.ballistic or key=="voidcloth_scythe") and math.huge or s.age+.1;s.hits_left=s.hits_left-1
                end
                if (not handled and not c.e.components.health) and (not s.hits_left or s.hits_left<=0) then Engraving.fade(ix,iz) end
                if invalid or not s.hits_left or s.hits_left<=0 then finish(inst,s,ix,iz,true);return end
            elseif c.prop and not (p and p.heal) and c.e:IsValid() and c.e._nw_break then
                c.e._nw_break(s.owner)
                impact(s,c.e,ix,iz);finish(inst,s,ix,iz,true);return
            elseif c.wall and not c.selected then
                impact(s,c.e,ix,iz)
                if rebound(inst,s,c,ix,iz,length,fraction) then return end
                Engraving.fade(ix,iz);finish(inst,s,ix,iz,true);return
            elseif c.ally and Effects.ally(s.owner,c.e) then
                s.group.healed[c.e]=true
                c.e.components.health:DoDelta(flags.heal_ally.heal,false,"nw_heal")
                M.heal_fx(c.tx,c.tz)
                finish(inst,s,ix,iz,false);return
            elseif c.e:IsValid() and (c.selected or c.prop and p and p.heal or Targeting.allowed(s.owner,c.e,flags)) then
                if p and p.heal then
                    local health=c.e.components.health
                    if health and not health:IsDead() then
                        health:DoDelta(p.heal,false,"nw_heal")
                        M.heal_fx(c.tx,c.tz)
                    end
                elseif p and p.id=="spore_ball" then
                    impact(s,c.e,ix,iz);finish(inst,s,ix,iz,true);return
                elseif p and (p.name or flags.wet_weak or flags.crit or flags.chill_touch or flags.melee_mark) then
                    require("nw/expanded_hits").impact(s,c.e,ix,iz)
                elseif p and (p.burn_damage or p.freeze or flags.leech or flags.knockback) then
                    Effects.direct(s.owner,c.e,p,s.dx,s.dz)
                else Targeting.damage(s.owner,c.e,s.damage,flags) end
                if not s.hits_left or s.hits_left<=1 then
                    -- A selected object may accept a collision without having a
                    -- health, burnable or freezable component. Always show the
                    -- terminal contact unless this branch just played a heal FX.
                    if not (p and p.heal and c.e.components.health) then Engraving.fade(ix,iz) end
                end
                impact(s,c.e,ix,iz)
                if s.hits_left then
                    s.hit[c.e]=s.age+.10;s.hits_left=s.hits_left-1
                end
                if not s.hits_left or s.hits_left<=0 then finish(inst,s,ix,iz,true);return end
            end
        end
    end
    advance_timer(1)
    if shore then require("nw/field_motion").stop(inst,nx,nz);return end
    -- Raw removal releases reservations without termination payloads, blasts,
    -- native handoffs or teleporting the caster beyond the world.
    if boundary then inst:Remove();return end
    if key=="staff_tornado" and s.aim_distance and s.travelled+.001>=s.aim_distance then finish(inst,s,nx,nz,true);return end
    if p and p.ballistic then
        -- Expiration in midair removes the projectile without manufacturing
        -- a landing (fish bait, tilling and native impact attacks need ground).
        if s.remaining<=.000001 or s.travelled>=range-.000001 then Engraving.fade(nx,nz);finish(inst,s,nx,nz,false)
        else Flight.steer(inst,s,dt) end
        return
    end
    if s.remaining<=.000001 or s.travelled>=range-.000001 then finish(inst,s,nx,nz,true)
    elseif p and not Flight.steer(inst,s,dt) then finish(inst,s,nx,nz,key~=nil) end
end
function M.heal_fx(x,z) Effects.fx("nw_heal_fx",x,z) end
local function tick(world)
    local pool=world._nw_projectiles
    local cache,timers={},{};local now=GetTime()
    -- Reverse iteration also tolerates removals and new shots from hit events.
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
