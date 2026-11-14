local C=require("nw/constants/field_runtime")
local Effects=require("nw/spell_effects")
local Target=require("nw/targeting")
local Hits=require("nw/expanded_hits")
local Stored=require("nw/persistent_fields")
local M={}

function M.can_break(inst,actor)
    if not inst._nw_break then return false end
    if inst._nw_stored and (inst._nw_stored.p.id=="payload_egg" or inst._nw_stored.p.id=="sleep_crystal"
        or inst._nw_stored.p.id=="crystal_mine") then return true end
    local owner=inst._nw_stored and Stored.owner(inst) or inst._nw_owner
    return actor==owner and actor~=nil
end

local function targets(owner,x,z,r,flags,options)
    local list=Target.query(owner,x,z,r,flags,options)
    table.sort(list,function(a,b)
        local da,db=a:GetDistanceSqToPoint(x,0,z),b:GetDistanceSqToPoint(x,0,z)
        return da<db or da==db and a.GUID<b.GUID
    end)
    return list
end

function M.attackable(inst)
    inst:AddComponent("inspectable")
    inst:AddComponent("health");inst.components.health:SetMaxHealth(C.attackable_health)
    inst.components.health:SetInvincible(true)
    inst:AddComponent("combat")
    local function struck(_,data)
        if M.can_break(inst,data and data.attacker) then inst._nw_break(data and data.attacker,true) end
    end
    inst:ListenForEvent("attacked",struck)
    inst:ListenForEvent("blocked",struck)
    inst:ListenForEvent("explosion",function(_,data)
        if inst._nw_stored and M.can_break(inst,data and data.explosive) then
            inst._nw_break(data and data.explosive,true)
        end
    end)
end

function M.sound(owner,x,z,id,shift,beats)
    local sound,params,duration=require("nw/arsenal").tone(id,shift,beats)
    if not sound then return false end
    local fx=Effects.fx("nw_note_sound",x,z)
    if fx then
        fx.SoundEmitter:PlaySoundWithParams(sound,params)
        fx:DoTaskInTime(duration+C.sound_tail,fx.Remove)
        return true
    end
    return false
end

local Field=require("nw/field_effects")
local Stages=require("nw/field_stages")
local limits=require("nw/spell_limits")
local function finish(inst) Stages.finish(inst);inst:Remove() end
local function stop(inst,time) inst:DoTaskInTime(time,finish) end

local function crystal(inst,owner,p,x,z)
    inst._nw_break=function(triggerer,attacked)
        if inst._nw_spent then return end
        local owner=Stored.owner(inst)
        local x,_,z=inst.Transform:GetWorldPosition()
        if not owner and (triggerer or attacked) then
            local caster=require("nw/payload_caster")
            owner=caster.resolve(triggerer) or caster.neutral(x,z)
        end
        if not owner then return end
        inst._nw_spent=true
        Effects.blast(owner,x,z,p);finish(inst)
    end
    if p.id=="crystal_mine" then
        inst._nw_proximity={radius=p.radius,trigger=function() inst._nw_break() end}
        local delay=C.crystal.arm_delay
        inst._nw_armed_at=GetTime()+delay
        inst:DoPeriodicTask(C.crystal.scan_interval,function()
            local owner=Stored.owner(inst)
            if not owner or inst:IsAsleep() then return end
            local x,_,z=inst.Transform:GetWorldPosition()
            if #Target.query(owner,x,z,p.radius,p.flags,{exclude=inst})>0 then inst._nw_break() end
        end,delay)
    end
end

local function detonate(inst,owner,p,x,z)
    Stages.pulse(inst)
    local list=TheSim:FindEntities(x,0,z,p.radius,nil,{"INLIMBO"})
    for i=#list,1,-1 do
        local v=list[i]
        local stored=v._nw_stored
        if v:IsValid() and v._nw_break and stored
            and (stored.p.id=="crystal_mine" or stored.p.id=="sleep_crystal")
            and v:GetDistanceSqToPoint(x,0,z)<=p.radius^2 then v._nw_break(owner) end
    end
    stop(inst,C.detonate.lifetime)
end

local function payload(inst,owner,p,x,z,dx,dz,fire)
    local function release(triggerer)
        if inst._nw_spent then return end
        local x,_,z=inst.Transform:GetWorldPosition()
        if inst._nw_motion then dx,dz=inst._nw_motion.dx,inst._nw_motion.dz end
        inst._nw_spent=true
        if fire and fire(x,z,dx,dz,triggerer)==false then inst._nw_spent=false;return end
        finish(inst)
    end
    if p.id=="delay_seal" then inst:DoTaskInTime(Field.time(p,C.payload.delay),release)
    else inst._nw_break=release end
end

local function swarm(inst,owner,p,x,z)
    local escort=p.id=="fireflies"
    if escort and not inst._nw_motion then inst.entity:SetParent(owner.entity);inst.Transform:SetPosition(0,C.swarm.escort_height,0) end
    local count=escort and C.swarm.escort_count or C.swarm.count
    for n=1,count do inst:DoTaskInTime(Field.time(p,C.swarm.first_delay+(n-1)*C.swarm.interval),function()
        local sx,_,sz=inst.Transform:GetWorldPosition()
        local target=targets(owner,sx,sz,p.radius,p.flags)[1]
        if target then
            local tx,_,tz=target.Transform:GetWorldPosition()
            local dx,dz=tx-sx,tz-sz
            local length=math.sqrt(dx*dx+dz*dz)
            if length<C.distance_epsilon then dx,dz=1,0 else dx,dz=dx/length,dz/length end
            local shot=require("nw/field_effects").shot(p,p.id,C.swarm.speed,C.swarm.lifetime)
            require("nw/executor").execute({next_state={rng_state=1},root_block=1,projectile_count=1,
                blocks={{projectiles={shot}}}},owner,sx,sz,dx,dz,C.swarm.muzzle_height,nil,p._nw_root)
        end
    end) end
    stop(inst,Field.time(p,C.swarm.finish_delay+(count-1)*C.swarm.interval))
end

local function rain(inst,owner,p,x,z)
    inst:AddComponent("wateryprotection")
    local water=inst.components.wateryprotection
    water.addwetness=C.rain.wetness
    for _,t in ipairs(C.rain.pulses) do inst:DoTaskInTime(Field.time(p,t),function()
        Stages.pulse(inst)
        local x,_,z=inst.Transform:GetWorldPosition()
        Field.water(water,owner,p,x,z)
        for _,e in ipairs(Target.query(owner,x,z,p.radius,p.flags,{default=true,components={"health"}})) do
            if not e.components.moisture and not e.components.inventoryitem
                and not e:HasAnyTag("moistureimmunity","rainimmunity") and Target.object(e)~="building"
                and e:GetDistanceSqToPoint(x,0,z)<=p.radius^2 and (e._nw_dry_task or not e:HasTag("wet")) then
                if e._nw_dry_task then e._nw_dry_task:Cancel() else e:AddTag("wet") end
                e._nw_dry_task=e:DoTaskInTime(C.rain.wet_duration,function()
                    e:RemoveTag("wet");e._nw_dry_task=nil
                end)
            end
        end
    end) end
    stop(inst,Field.time(p,C.rain.lifetime))
end

local function guard(inst,owner,p,x,z)
    inst.entity:SetParent(owner.entity);inst.Transform:SetPosition(0,0,0)
    require("nw/field_effects").attach(inst,owner,p)
    require("nw/guard_ring").start(inst,owner,p)
    stop(inst,require("nw/field_effects").time(p,C.guard.lifetime))
end

local function decoy(inst,owner,p,x,z)
    inst:AddComponent("health");inst.components.health:SetMaxHealth(C.decoy.health);inst.components.health:SetInvincible(true)
    inst:AddComponent("combat")
    inst:DoPeriodicTask(C.decoy.scan_interval,function()
        local x,_,z=inst.Transform:GetWorldPosition()
        for _,e in ipairs(targets(owner,x,z,p.radius,p.flags,{components={"health","combat"}})) do
            if not p.secondary and not e:HasTag("epic") then e.components.combat:SetTarget(inst) end
        end
    end,0)
    inst:DoTaskInTime(Field.time(p,C.decoy.lifetime),function()
        local x,_,z=inst.Transform:GetWorldPosition()
        for _,e in ipairs(Effects.scan(x,z,p.radius,p.flags)) do
            local player=e:HasTag("player") and not e:HasTag("playerghost")
            if not e._nw_break and Target.object(e)~="building"
                and (player and not p.flags.targets or Target.selected(owner,e,p.flags))
                and e:GetDistanceSqToPoint(x,0,z)<=p.radius*p.radius then
                local ex,_,ez=e.Transform:GetWorldPosition()
                local dx,dz=ex-x,ez-z
                local distance=math.max(C.distance_epsilon,math.sqrt(dx*dx+dz*dz))
                local hitp=p
                if player and not p.flags.targets then
                    hitp=require("nw/util").copy(p)
                    hitp.flags.targets={self=true,players_other=true}
                end
                Hits.impact({owner=owner,p=hitp,age=0,dx=dx/distance,dz=dz/distance},e,ex,ez)
            end
        end
        finish(inst)
    end)
end

local function electricity(inst,owner,p,x,z)
    local cloud=p.id=="storm_cloud"
    if cloud then
        limits.track(inst,owner,"_nw_storms")
    end
    for i=1,cloud and C.electricity.cloud_count or C.electricity.ring_count do
        local when=Field.time(p,cloud and i*C.electricity.cloud_interval or i-C.electricity.ring_advance)
        if cloud then
            local warning=Stages.duration("storm_cloud","warning")*Stages.storm_time_scale(p)
            inst:DoTaskInTime(math.max(0,when-warning),function() Stages.warning(inst) end)
        end
        inst:DoTaskInTime(when,function()
            Stages.pulse(inst)
            local x,y,z=inst.Transform:GetWorldPosition()
            for _,e in ipairs(Target.query(owner,x,z,p.radius,p.flags,{breakables=true})) do
                local now=GetTime()
                if now>=(e._nw_storm_next or 0) then
                    e._nw_storm_next=now+C.electricity.hit_interval
                    Hits.electric(owner,e,x,z,p.damage*Effects.wet_mult(e,p.flags),p,false,
                        cloud and y or nil,cloud and Stages.storm_lift(p) or nil)
                    if cloud then break end
                end
            end
        end)
    end
    stop(inst,Field.time(p,cloud and C.electricity.cloud_lifetime or C.electricity.ring_lifetime))
end

local function vortex(inst,owner,p,x,z)
    Stages.pulse(inst)
    for _,e in ipairs(targets(owner,x,z,p.radius,p.flags,{components={"locomotor"}})) do
        if not e:HasTag("epic") and e.Physics then
            local ex,_,ez=e.Transform:GetWorldPosition()
            local dx,dz=x-ex,z-ez
            local l=math.sqrt(dx*dx+dz*dz)
            if l>C.vortex.min_distance then Hits.safe_move(e,dx/l,dz/l,math.min(C.vortex.max_step,l-C.vortex.min_distance)) end
        end
    end
    stop(inst,Field.time(p,C.vortex.lifetime))
end

M.actions={crystal_mine=crystal,sleep_crystal=crystal,detonate=detonate,
    delay_seal=payload,payload_egg=payload,bee_swarm=swarm,fireflies=swarm,
    rain_cloud=rain,guard_ring=guard,deer_decoy=decoy,shock_ring=electricity,storm_cloud=electricity,vortex=vortex,
    moon_fall=function(inst,owner,p,x,z)
        local deadline=Field.time(p,C.moon_fall.delay)
        inst:DoTaskInTime(math.max(0,deadline-Stages.fall_time),function() Stages.fall(inst) end)
        inst:DoTaskInTime(deadline,function() local x,_,z=inst.Transform:GetWorldPosition();Effects.blast(owner,x,z,p);finish(inst) end)
    end,
    bog_whip=function(inst,owner,p,x,z,dx,dz)
        require("nw/melee").launch(inst,owner,p,x,z,dx,dz,function() end)
    end,
}
return M
