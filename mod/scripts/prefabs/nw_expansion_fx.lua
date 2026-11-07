local fields=require("nw/expanded_fields")
local Effects=require("nw/spell_effects")
local Stored=require("nw/persistent_fields")
local Stages=require("nw/field_stages")
local assets={Asset("ANIM","anim/nw_spell_world.zip"),Asset("ANIM","anim/tentacle_arm.zip"),Asset("ANIM","anim/tentacle_arm_build.zip"),Asset("ANIM","anim/nw_objects.zip"),Asset("ANIM","anim/nw_elemental_flight.zip"),Asset("ANIM","anim/nw_field_stages.zip"),Asset("ANIM","anim/meteor_shadow.zip")}
local function make(card)
    local id=card.id
    local persistent=Stored.is(id)
    local insects=id=="bee_swarm" or id=="fireflies"
    local function fn()
        local inst=CreateEntity()
        inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddNetwork()
        if insects then inst._nw_insect_size=net_float(inst.GUID,"nw_insect_swarm.size","nw_insect_swarmdirty") end
        if id~="guard_ring" then MakeProjectilePhysics(inst,1,.1);inst._nw_ground_mask=true end
        inst.entity:SetCanSleep(persistent)
        if card.breakable then inst:AddTag("nw_breakable")
        elseif id=="deer_decoy" then inst:AddTag("nw_decoy");inst:AddTag("NOCLICK")
        else if not persistent then inst:AddTag("FX") end;inst:AddTag("NOCLICK") end
        inst.AnimState:SetBank("nw_objects");inst.AnimState:SetBuild("nw_objects")
        if id=="bog_whip" then
            inst.AnimState:SetBank("tentacle_arm");inst.AnimState:SetBuild("tentacle_arm_build")
            inst.AnimState:SetScale(.95,.95)
            inst.AnimState:PlayAnimation("atk_pre")
            inst.AnimState:PushAnimation("atk_loop",false)
            inst.AnimState:PushAnimation("atk_pst",false)
            inst.AnimState:SetDeltaTimeMultiplier(2.5)
        elseif Stages.has(id) then Stages.setup(inst,id)
        else inst.AnimState:PlayAnimation("field_"..id,true) end
        -- Hide only the old painted group; local members remain independently
        -- visible while the field keeps its network identity and gameplay.
        if insects then inst.AnimState:SetMultColour(1,1,1,0) end

        if id=="rain_cloud" then
            inst.entity:AddDynamicShadow();inst.DynamicShadow:SetSize(3.5,1.6)
            if not TheNet:IsDedicated() then
                local wet=CreateEntity();wet.entity:AddTransform();wet.entity:AddAnimState()
                wet:AddTag("FX");wet:AddTag("NOCLICK");wet.persists=false;wet.entity:SetParent(inst.entity)
                wet.AnimState:SetBank("nw_spell_world");wet.AnimState:SetBuild("nw_spell_world")
                wet.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround);wet.AnimState:SetFinalOffset(-1)
                wet.AnimState:PlayAnimation("wet_patch",true)
                inst:ListenForEvent("onremove",function() if wet:IsValid() then wet:Remove() end end)
            end
        end
        inst.entity:SetPristine()
        if insects then require("nw/insect_swarm_visual").attach(inst,id) end
        Stages.attach(inst,id)
        if not TheWorld.ismastersim then return inst end
        inst.persists=persistent
        if persistent then Stored.install(inst) end
        if card.breakable then fields.attackable(inst) end
        function inst:Launch(owner,p,x,z,dx,dz,cleanup,height,fire,payload)
            if persistent then cleanup() else self:ListenForEvent("onremove",cleanup) end
            self.Transform:SetPosition(x,0,z)
            if persistent and require("nw/ground_fields").sink(self) then return end
            if not Effects.live(owner) or not TheWorld.Map:IsPassableAtPoint(x,0,z,true) then self:Remove();return end
            require("nw/projectile_size").field(self,p)
            if insects then self._nw_insect_size:set(require("nw/projectile_size").factor(p)) end
            if persistent then Stored.launch(self,owner,p,dx,dz,height,payload);return end
            self._nw_owner=owner
            local function expire() if self:IsValid() then self:Remove() end end
            self:ListenForEvent("death",expire,owner)
            self:ListenForEvent("onremove",expire,owner)
            self:ListenForEvent("ms_becameghost",expire,owner)
            self.Transform:SetPosition(x,0,z)
            if id~="guard_ring" and require("nw/field_motion").start(self,owner,p,dx,dz)==false then return end
            Stages.start(self,id,p)
            fields.actions[id](self,owner,p,x,z,dx,dz,fire)
        end
        return inst
    end
    return Prefab("nw_"..id,fn,assets,{"nw_field_stage_fx","nw_guard_stage_fx"})
end
local function cue(id)
    return Prefab(id,function()
        local e=CreateEntity()
        e.entity:AddTransform()
        if id=="nw_note_sound" then e.entity:AddSoundEmitter() else
            e.entity:AddAnimState()
            e.AnimState:SetBank("nw_objects");e.AnimState:SetBuild("nw_objects")
            e.AnimState:PlayAnimation("chord_note",true)
        end
        e.entity:AddNetwork();e:AddTag("FX");e:AddTag("NOCLICK");e.entity:SetPristine()
        if TheWorld.ismastersim then
            e.persists=false
            -- Normal note cleanup is scheduled from its WAV duration by expanded_fields.sound.
            e:DoTaskInTime(id=="nw_note_sound" and 30 or 2,e.Remove)
        end
        return e
    end,assets)
end
local function boundary()
    local e=CreateEntity()
    e.entity:AddTransform();e.entity:AddAnimState();e.entity:AddNetwork()
    e.AnimState:SetBank("nw_objects");e.AnimState:SetBuild("nw_objects")
    e.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    e.AnimState:PlayAnimation("field_boundary",true)
    e.AnimState:SetMultColour(.85,.85,.8,.7)
    e:AddTag("FX");e:AddTag("NOCLICK");e.entity:SetPristine();e.persists=false
    return e
end
local out={Prefab("nw_field_boundary",boundary,assets),cue("nw_note_mark"),cue("nw_note_sound")}
for _,card in ipairs(require("nw/expansion")) do
    if card.kind=="field" then assert(fields.actions[card.id],card.id);out[#out+1]=make(card) end
end
return unpack(out)
