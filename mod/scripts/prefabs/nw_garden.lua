local Effects=require("nw/spell_effects")
local Target=require("nw/targeting")
local assets={Asset("ANIM","anim/nw_objects.zip")}

local function nearest(owner,x,z,radius,flags)
    local list=Effects.scan(x,z,radius,flags)
    local best,dist=nil,radius*radius
    for _,e in ipairs(list) do
        if Target.allowed(owner,e,flags) then
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
    limits.track(inst,owner,"_nw_sentries",limits.sentries)
    local shots,closing=0,false
    local function wilt()
        if closing then return end
        closing=true
        inst.AnimState:PlayAnimation("spore_wilt")
        inst:DoTaskInTime(.3,inst.Remove)
    end
    local function seek()
        if closing then return end
        local x,_,z=inst.Transform:GetWorldPosition()
        local e=nearest(owner,x,z,p.radius,p.flags)
        if not e then inst:DoTaskInTime(.3,seek);return end
        local tx,_,tz=e.Transform:GetWorldPosition()
        inst.AnimState:SetScale(tx<x and -1 or 1,1)
        inst.AnimState:PlayAnimation("spore_fire")
        inst.AnimState:PushAnimation("spore_idle",true)
        inst:DoTaskInTime(.2,function()
            if closing then return end
            local x,_,z=inst.Transform:GetWorldPosition()
            if Target.allowed(owner,e,p.flags) then
                tx,_,tz=e.Transform:GetWorldPosition()
                local dx,dz=tx-x,tz-z
                local length=math.sqrt(dx*dx+dz*dz)
                if length<=p.radius and Effects.clear(x,z,tx,tz,Effects.scan(x,z,p.radius)) then
                    if length<.001 then dx,dz=1,0 else dx,dz=dx/length,dz/length end
                    local thorn={id="spore_sentry",kind="projectile",speed=14,lifetime=.36*require("nw/projectile_size").factor(p),
                        damage=p.damage,flags={targets=p.flags.targets},spread=0,size_mult=p.size_mult,max_range=math.max(30,p.radius)}
                    local fired=require("nw/executor").execute({root_block=1,projectile_count=1,
                        next_state={rng_state=1},blocks={{projectiles={thorn}}}},owner,x,z,dx,dz,.62)
                    if fired then
                        shots=shots+1
                        local combat=e.components.combat
                        if not e:HasTag("player") and combat and not combat.target and combat:CanTarget(inst) then
                            combat:SuggestTarget(inst)
                        end
                    end
                end
            end
            if shots>=3 then wilt() else inst:DoTaskInTime(.6,seek) end
        end)
    end
    inst.AnimState:PlayAnimation("spore_grow")
    inst.AnimState:PushAnimation("spore_idle",true)
    inst:DoTaskInTime(.6,seek)
    inst:DoTaskInTime(5.7,wilt)
end

local function ring(inst,owner,p,x,z)
    inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    inst.AnimState:PlayAnimation("vital_pulse",true)
    local function pulse()
        local x,_,z=inst.Transform:GetWorldPosition()
        for _,e in ipairs(Effects.scan(x,z,p.radius)) do
            local h=e.components.health
            if h and not h:IsDead() and h.currenthealth<h:GetMaxWithPenalty()
                and (e==owner or Effects.ally(owner,e)) and e:GetDistanceSqToPoint(x,0,z)<=p.radius^2 then
                h:DoDelta(2,false,"nw_vital_ring")
            end
        end
    end
    for n=1,3 do inst:DoTaskInTime(n,pulse) end
    inst:DoTaskInTime(3.1,inst.Remove)
end

local function note(inst,owner,p,x,z)
    inst.AnimState:PlayAnimation("chord_note")
    local now=GetTime()
    inst.SoundEmitter:PlaySoundWithParams(require("nw/arsenal").tone(p.id,p.pitch))
    for _,e in ipairs(Effects.scan(x,z,p.radius)) do
        if e:HasTag("player") and Effects.live(e) and e.components.sanity and not e:HasTag("playerghost")
            and e:GetDistanceSqToPoint(x,0,z)<=p.radius^2 and now+.001>=(e._nw_chord_next or 0) then
            e._nw_chord_next=now+3
            e.components.sanity:DoDelta(1)
        end
    end
    inst:DoTaskInTime(.65,inst.Remove)
end

local function prefab(id,activate)
    local function fn()
        local inst=CreateEntity()
        inst.entity:AddTransform();inst.entity:AddAnimState()
        if id=="chord_d" then inst.entity:AddSoundEmitter() end
        if id~="chord_d" then MakeProjectilePhysics(inst,1,.1) end
        inst.entity:AddNetwork()
        inst.entity:SetCanSleep(false)
        inst.AnimState:SetBank("nw_objects");inst.AnimState:SetBuild("nw_objects")
        if id=="spore_sentry" then inst:AddTag("nw_sentry")
        else inst:AddTag("FX");inst:AddTag("NOCLICK") end
        inst.entity:SetPristine()
        if not TheWorld.ismastersim then return inst end
        inst.persists=false
        if id=="spore_sentry" then
            inst:AddComponent("inspectable")
            inst:AddComponent("health");inst.components.health:SetMaxHealth(60)
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
    return Prefab("nw_"..id,fn,assets)
end
return prefab("spore_sentry",sentry),prefab("vital_ring",ring),prefab("chord_d",note)
