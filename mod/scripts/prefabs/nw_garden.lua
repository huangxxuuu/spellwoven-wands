local C=require("nw/constants/prefabs").garden
local Runtime=require("nw/constants/field_runtime")
local Physics=require("nw/constants/native").physics
local Effects=require("nw/spell_effects")
local Target=require("nw/targeting")
local Stages=require("nw/field_stages")
local HEAL_TARGETS={default=true,components={"health"}}
local SANITY_TARGETS={default=true,components={"sanity"}}
local assets={Asset("ANIM","anim/nw_objects.zip"),Asset("ANIM","anim/nw_field_stages.zip")}

local function nearest(owner,x,z,radius,flags)
    local list=Effects.scan(x,z,radius,flags)
    local best,dist=nil,radius*radius
    for _,e in ipairs(list) do
        if Target.selected(owner,e,flags) then
            local tx,_,tz=e.Transform:GetWorldPosition()
            local d=(tx-x)^2+(tz-z)^2
            if d<=dist and (d<dist or not best or e.GUID<best.GUID) and Effects.clear(x,z,tx,tz,list) then
                best,dist=e,d
            end
        end
    end
    return best
end

local function sentry(inst,owner,p,x,z)
    inst.components.follower:SetLeader(owner)
    inst.components.follower:StopLeashing()
    local limits=require("nw/spell_limits")
    limits.track(inst,owner,"_nw_sentries")
    local shots,closing,fire_until=0,false,0
    local lifetime=require("nw/field_effects").time(p,C.spore_sentry.lifetime)
    local deadline=GetTime()+lifetime
    local function wilt()
        if closing then return end
        closing=true
        local function finish()
            inst.AnimState:PlayAnimation("spore_wilt")
            inst:DoTaskInTime(C.spore_sentry.wilt_time,inst.Remove)
        end
        local remaining=fire_until-GetTime()
        if remaining>0 then inst:DoTaskInTime(remaining,finish) else finish() end
    end
    local function seek()
        if closing or GetTime()>=deadline then return end
        local x,_,z=inst.Transform:GetWorldPosition()
        local e=nearest(owner,x,z,p.radius,p.flags)
        if not e then inst:DoTaskInTime(C.spore_sentry.scan_interval,seek);return end
        local tx,_,tz=e.Transform:GetWorldPosition()
        inst.AnimState:SetScale(tx<x and -1 or 1,1)
        fire_until=GetTime()+C.spore_sentry.fire_time
        inst.AnimState:PlayAnimation("spore_fire")
        inst.AnimState:PushAnimation("spore_idle",true)
        inst:DoTaskInTime(C.spore_sentry.fire_delay,function()
            if closing or GetTime()>=deadline then return end
            local x,_,z=inst.Transform:GetWorldPosition()
            if Target.selected(owner,e,p.flags) then
                tx,_,tz=e.Transform:GetWorldPosition()
                local dx,dz=tx-x,tz-z
                local length=math.sqrt(dx*dx+dz*dz)
                if length<=p.radius and Effects.clear(x,z,tx,tz,Effects.scan(x,z,p.radius,p.flags)) then
                    if length<Runtime.distance_epsilon then dx,dz=1,0 else dx,dz=dx/length,dz/length end
                    local thorn=require("nw/field_effects").shot(p,"spore_sentry",C.spore_sentry.speed,C.spore_sentry.shot_lifetime)
                    local fired=require("nw/executor").execute({root_block=1,projectile_count=1,
                        next_state={rng_state=1},blocks={{projectiles={thorn}}}},owner,x,z,dx,dz,C.spore_sentry.muzzle_height,nil,p._nw_root)
                    if fired then
                        shots=shots+1
                        local combat=e.components.combat
                        if not e:HasTag("player") and combat and not combat.target and combat:CanTarget(inst) then
                            combat:SuggestTarget(inst)
                        end
                    end
                end
            end
            if shots>=C.spore_sentry.shots then wilt() else inst:DoTaskInTime(C.spore_sentry.shot_interval,seek) end
        end)
    end
    inst.AnimState:PlayAnimation("spore_grow")
    inst.AnimState:PushAnimation("spore_idle",true)
    inst:DoTaskInTime(C.spore_sentry.grow_time,seek)
    inst:DoTaskInTime(lifetime,wilt)
end

local function ring(inst,owner,p,x,z)
    Stages.start(inst,"vital_ring",p)
    local function pulse()
        Stages.pulse(inst)
        local x,_,z=inst.Transform:GetWorldPosition()
        for _,e in ipairs(Target.query(owner,x,z,p.radius,p.flags,HEAL_TARGETS)) do
            local h=e.components.health
            if h and not h:IsDead() and h.currenthealth<h:GetMaxWithPenalty()
                and (e==owner or Effects.ally(owner,e,p.flags)) then
                h:DoDelta(C.vital_ring.heal,false,"nw_vital_ring")
            end
        end
    end
    for n=1,C.vital_ring.pulses do inst:DoTaskInTime(require("nw/field_effects").time(p,n),pulse) end
    inst:DoTaskInTime(require("nw/field_effects").time(p,C.vital_ring.lifetime),function() Stages.finish(inst);inst:Remove() end)
end

local function note(inst,owner,p,x,z)
    inst.AnimState:PlayAnimation("chord_note")
    local now=GetTime()
    require("nw/expanded_fields").sound(owner,x,z,p.id,p.pitch,p.beats)
    for _,e in ipairs(Target.query(owner,x,z,p.radius,p.flags,SANITY_TARGETS)) do
        if (p.flags.targets or e:HasTag("player")) and Effects.live(e) and e.components.sanity and not e:HasTag("playerghost")
            and now+C.chord.time_epsilon>=(e._nw_chord_next or 0) then
            e._nw_chord_next=now+C.chord.cooldown
            e.components.sanity:DoDelta(C.chord.sanity)
        end
    end
    inst:DoTaskInTime(C.chord.lifetime,inst.Remove)
end

local function prefab(id,activate)
    local function fn()
        local inst=CreateEntity()
        inst.entity:AddTransform();inst.entity:AddAnimState()
        if id=="chord_d" then inst.entity:AddSoundEmitter() end
        if id~="chord_d" then MakeProjectilePhysics(inst,Physics.mass,Physics.radius) end
        inst.entity:AddNetwork()
        inst.entity:SetCanSleep(false)
        inst.AnimState:SetBank("nw_objects");inst.AnimState:SetBuild("nw_objects")
        if id=="vital_ring" then Stages.setup(inst,id) end
        if id=="spore_sentry" then
            inst.AnimState:SetBank(Stages.bank);inst.AnimState:SetBuild(Stages.bank)
            inst:AddTag("nw_sentry")
        else inst:AddTag("FX");inst:AddTag("NOCLICK") end
        inst.entity:SetPristine()
        Stages.attach(inst,id)
        if not TheWorld.ismastersim then return inst end
        inst.persists=false
        if id=="spore_sentry" then
            inst:AddComponent("inspectable")
            inst:AddComponent("health");inst.components.health:SetMaxHealth(C.spore_sentry.health)
            inst.components.health.nofadeout=true
            inst:AddComponent("combat")
            inst:AddComponent("follower")
            inst:ListenForEvent("death",inst.Remove)
        end
        function inst:Launch(owner,p,x,z,dx,dz,cleanup)
            self:ListenForEvent("onremove",cleanup)
            if not Effects.live(owner) or (id=="spore_sentry" and not TheWorld.Map:IsPassableAtPoint(x,0,z,true)) then
                self:Remove();return
            end
            local function expire() if self:IsValid() then self:Remove() end end
            self:ListenForEvent("death",expire,owner)
            self:ListenForEvent("onremove",expire,owner)
            self:ListenForEvent("ms_becameghost",expire,owner)
            self.Transform:SetPosition(x,0,z)
            require("nw/projectile_size").field(self,p)
            if p.kind=="field" and require("nw/field_motion").start(self,owner,p,dx,dz)==false then return end
            activate(self,owner,p,x,z)
        end
        return inst
    end
    return Prefab("nw_"..id,fn,assets,{"nw_vital_stage_fx"})
end
return prefab("spore_sentry",sentry),prefab("vital_ring",ring),prefab("chord_d",note)
