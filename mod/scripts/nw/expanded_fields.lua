local Effects=require("nw/spell_effects")
local Target=require("nw/targeting")
local Hits=require("nw/expanded_hits")
local Stored=require("nw/persistent_fields")
local M={crystal_limit=0}

function M.can_break(inst,actor)
    if not inst._nw_break then return false end
    if inst._nw_stored and (inst._nw_stored.p.id=="payload_egg" or inst._nw_stored.p.id=="sleep_crystal") then return true end
    local owner=inst._nw_stored and Stored.owner(inst) or inst._nw_owner
    return actor==owner and actor~=nil
end

local function enemies(owner,x,z,r,flags)
    local list={}
    for _,e in ipairs(Effects.scan(x,z,r,flags)) do
        if Target.allowed(owner,e,flags) and e:GetDistanceSqToPoint(x,0,z)<=r*r then list[#list+1]=e end
    end
    table.sort(list,function(a,b)
        local da,db=a:GetDistanceSqToPoint(x,0,z),b:GetDistanceSqToPoint(x,0,z)
        return da<db or da==db and a.GUID<b.GUID
    end)
    return list
end

function M.attackable(inst)
    inst:AddComponent("inspectable")
    inst:AddComponent("health");inst.components.health:SetMaxHealth(1)
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

function M.sound(owner,x,z,id,shift)
    local sound,params,duration=require("nw/arsenal").tone(id,shift)
    if not sound then return false end
    local fx=Effects.fx("nw_note_sound",x,z)
    if fx then
        fx.SoundEmitter:PlaySoundWithParams(sound,params)
        fx:DoTaskInTime(duration+.1,fx.Remove)
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
        -- An unavailable placer only pauses autonomous/command activation.
        -- A physical attack can still detonate a dormant crystal.
        if not owner and p.id=="sleep_crystal" and (triggerer or attacked) then
            local caster=require("nw/payload_caster")
            owner=caster.resolve(triggerer) or caster.neutral(x,z)
        end
        if not owner then return end
        inst._nw_spent=true
        Effects.blast(owner,x,z,p);finish(inst)
    end
    if p.id=="crystal_mine" then
        local delay=0
        inst._nw_armed_at=GetTime()+delay
        inst:DoPeriodicTask(.15,function()
            local owner=Stored.owner(inst)
            if not owner or inst:IsAsleep() then return end
            local x,_,z=inst.Transform:GetWorldPosition()
            if #enemies(owner,x,z,p.radius,p.flags)>0 then inst._nw_break() end
        end,delay)
    end
end

local function detonate(inst,owner,p,x,z)
    Stages.pulse(inst)
    -- A blast can synchronously remove several other crystals. Their onremove
    -- callbacks mutate the ownership list, so iterate a stable entity snapshot.
    local list={}
    for _,v in ipairs(Stored.crystals(owner)) do list[#list+1]=v end
    local ox,_,oz=owner.Transform:GetWorldPosition()
    for i=#list,1,-1 do
        local v=list[i]
        if v:IsValid() and v:GetDistanceSqToPoint(ox,0,oz)<=p.aim_range^2 and v:GetDistanceSqToPoint(x,0,z)<=p.radius^2 then v._nw_break() end
    end
    stop(inst,.22)
end

local function payload(inst,owner,p,x,z,dx,dz,fire)
    local function release(triggerer)
        if inst._nw_spent then return end
        local x,_,z=inst.Transform:GetWorldPosition()
        if inst._nw_motion then dx,dz=inst._nw_motion.dx,inst._nw_motion.dz end
        -- Mark before launching so a synchronous payload cannot open us twice.
        inst._nw_spent=true
        if fire and fire(x,z,dx,dz,triggerer)==false then inst._nw_spent=false;return end
        finish(inst)
    end
    if p.id=="delay_seal" then inst:DoTaskInTime(Field.time(p,.75),release)
    else inst._nw_break=release end
end

local function swarm(inst,owner,p,x,z)
    local escort=p.id=="fireflies"
    if escort and not inst._nw_motion then inst.entity:SetParent(owner.entity);inst.Transform:SetPosition(0,1,0) end
    local count=escort and 2 or 3
    for n=1,count do inst:DoTaskInTime(Field.time(p,.35+(n-1)*.55),function()
        local sx,_,sz=inst.Transform:GetWorldPosition()
        local target=enemies(owner,sx,sz,p.radius,p.flags)[1]
        if target then
            local tx,_,tz=target.Transform:GetWorldPosition()
            local dx,dz=tx-sx,tz-sz
            local length=math.sqrt(dx*dx+dz*dz)
            if length<.001 then dx,dz=1,0 else dx,dz=dx/length,dz/length end
            local shot=require("nw/field_effects").shot(p,p.id,16,.42)
            require("nw/executor").execute({next_state={rng_state=1},root_block=1,projectile_count=1,
                blocks={{projectiles={shot}}}},owner,sx,sz,dx,dz,.85)
        end
    end) end
    stop(inst,Field.time(p,.45+(count-1)*.55))
end

local function rain(inst,owner,p,x,z)
    inst:AddComponent("wateryprotection")
    local water=inst.components.wateryprotection
    water.addwetness=35
    for _,t in ipairs({.3,1.8}) do inst:DoTaskInTime(Field.time(p,t),function()
        Stages.pulse(inst)
        local x,_,z=inst.Transform:GetWorldPosition()
        water:SpreadProtectionAtPoint(x,0,z,p.radius)
        -- DST tracks numeric moisture for players and items. Ordinary creatures
        -- use the native wet tag for electric damage. Only undo tags we added.
        for _,e in ipairs(Effects.scan(x,z,p.radius)) do
            if e.components.health and not e.components.moisture and not e.components.inventoryitem
                and not e:HasAnyTag("moistureimmunity","rainimmunity","wall","structure")
                and e:GetDistanceSqToPoint(x,0,z)<=p.radius^2 and (e._nw_dry_task or not e:HasTag("wet")) then
                if e._nw_dry_task then e._nw_dry_task:Cancel() else e:AddTag("wet") end
                e._nw_dry_task=e:DoTaskInTime(2.5,function()
                    e:RemoveTag("wet");e._nw_dry_task=nil
                end)
            end
        end
    end) end
    stop(inst,Field.time(p,3))
end

local function guard(inst,owner,p,x,z)
    inst.entity:SetParent(owner.entity);inst.Transform:SetPosition(0,0,0)
    require("nw/field_effects").attach(inst,owner,p)
    require("nw/guard_ring").start(inst,owner,p)
    stop(inst,require("nw/field_effects").time(p,2))
end

local function decoy(inst,owner,p,x,z)
    inst:AddComponent("health");inst.components.health:SetMaxHealth(500);inst.components.health:SetInvincible(true)
    inst:AddComponent("combat")
    inst:DoPeriodicTask(.5,function()
        local x,_,z=inst.Transform:GetWorldPosition()
        for _,e in ipairs(enemies(owner,x,z,p.radius,p.flags)) do
            if not p.secondary and not e:HasTag("epic") then e.components.combat:SetTarget(inst) end
        end
    end,0)
    inst:DoTaskInTime(Field.time(p,3),function()
        local x,_,z=inst.Transform:GetWorldPosition()
        -- A single gentle spin contact, not an explosion: no burst prefab,
        -- explosion callbacks or crystal/egg chain reactions at expiration.
        for _,e in ipairs(Effects.scan(x,z,p.radius,p.flags)) do
            local player=e:HasTag("player") and not e:HasTag("playerghost")
            if not e._nw_break and not e:HasTag("structure") and not e:HasTag("wall")
                and (player or Target.allowed(owner,e,p.flags))
                and e:GetDistanceSqToPoint(x,0,z)<=p.radius*p.radius then
                local ex,_,ez=e.Transform:GetWorldPosition()
                local dx,dz=ex-x,ez-z
                local distance=math.max(.001,math.sqrt(dx*dx+dz*dz))
                local hitp=p
                if player then
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
        limits.track(inst,owner,"_nw_storms",limits.storms)
        if limits.world_storms>0 then limits.track(inst,TheWorld,"_nw_storms",limits.world_storms) end
    end
    for i=1,cloud and 3 or 2 do
        local when=Field.time(p,cloud and i*.8 or i-.15)
        if cloud then inst:DoTaskInTime(math.max(0,when-.30),function() Stages.warning(inst) end) end
        inst:DoTaskInTime(when,function()
            Stages.pulse(inst)
            local x,y,z=inst.Transform:GetWorldPosition()
            for _,e in ipairs(Effects.scan(x,z,p.radius,p.flags)) do
                local now=GetTime()
                if Target.hittable(owner,e,p.flags) and e:GetDistanceSqToPoint(x,0,z)<=p.radius*p.radius and now>=(e._nw_storm_next or 0) then
                    e._nw_storm_next=now+.45
                    -- The cloud's height is painted into its billboard (330 px).
                    -- Keep this visual lift separate from world Y; the renderer
                    -- projects it with the local camera's pitch on every client.
                    Hits.electric(owner,e,x,z,p.damage*Effects.wet_mult(e,p.flags),p,false,
                        cloud and y or nil,cloud and 330/150*require("nw/projectile_size").factor(p) or nil)
                    if cloud then break end
                end
            end
        end)
    end
    stop(inst,Field.time(p,cloud and 2.55 or 2))
end

local function vortex(inst,owner,p,x,z)
    Stages.pulse(inst)
    for _,e in ipairs(enemies(owner,x,z,p.radius,p.flags)) do
        if not e:HasTag("epic") and e.Physics then
            local ex,_,ez=e.Transform:GetWorldPosition()
            local dx,dz=x-ex,z-ez
            local l=math.sqrt(dx*dx+dz*dz)
            if l>.25 then Hits.safe_move(e,dx/l,dz/l,math.min(1,l-.25)) end
        end
    end
    stop(inst,Field.time(p,.4))
end

M.actions={crystal_mine=crystal,sleep_crystal=crystal,detonate=detonate,
    delay_seal=payload,payload_egg=payload,bee_swarm=swarm,fireflies=swarm,
    rain_cloud=rain,guard_ring=guard,deer_decoy=decoy,shock_ring=electricity,storm_cloud=electricity,vortex=vortex,
    moon_fall=function(inst,owner,p,x,z)
        local deadline=Field.time(p,.8)
        inst:DoTaskInTime(math.max(0,deadline-Stages.fall_time),function() Stages.fall(inst) end)
        inst:DoTaskInTime(deadline,function() local x,_,z=inst.Transform:GetWorldPosition();Effects.blast(owner,x,z,p);finish(inst) end)
    end,
    bog_whip=function(inst,owner,p,x,z,dx,dz)
        require("nw/melee").launch(inst,owner,p,x,z,dx,dz,function() end)
    end,
}
return M
