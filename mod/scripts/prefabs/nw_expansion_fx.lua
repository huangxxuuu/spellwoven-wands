local fields=require("nw/expanded_fields")
local Effects=require("nw/spell_effects")
local Stored=require("nw/persistent_fields")
local assets={Asset("ANIM","anim/nw_spell_world.zip"),Asset("ANIM","anim/tentacle_arm.zip"),Asset("ANIM","anim/tentacle_arm_build.zip"),Asset("ANIM","anim/nw_objects.zip")}
local function make(card)
    local id=card.id
    local persistent=Stored.is(id)
    local function fn()
        local inst=CreateEntity()
        inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddNetwork()
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
        elseif id=="rain_cloud" or id=="payload_egg" or id=="crystal_mine" or id=="sleep_crystal" or id=="guard_ring" then
            inst.AnimState:SetBank("nw_spell_world");inst.AnimState:SetBuild("nw_spell_world")
            inst.AnimState:PlayAnimation(id=="guard_ring" and "shield_2" or id,true)
        else inst.AnimState:PlayAnimation("field_"..id,true) end

        inst.entity:SetPristine()
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
            if persistent then Stored.launch(self,owner,p,dx,dz,height,payload);return end
            self._nw_owner=owner
            local function expire() if self:IsValid() then self:Remove() end end
            self:ListenForEvent("death",expire,owner)
            self:ListenForEvent("onremove",expire,owner)
            self:ListenForEvent("ms_becameghost",expire,owner)
            self.Transform:SetPosition(x,0,z)
            if card.radius and id~="crystal_mine" and id~="sleep_crystal" and id~="guard_ring" and id~="rain_cloud" and id~="detonate" and id~="fireflies" and id~="bee_swarm" then
                local ring=SpawnPrefab("nw_field_boundary")
                ring.entity:SetParent(inst.entity)
                local scale=require("nw/fx_layout").blast_scale(card.radius)
                ring.AnimState:SetScale(scale,scale)
                self:ListenForEvent("onremove",function() if ring:IsValid() then ring:Remove() end end)
            end
            if id~="guard_ring" and require("nw/field_motion").start(self,owner,p,dx,dz)==false then return end
            fields.actions[id](self,owner,p,x,z,dx,dz,fire)
        end
        return inst
    end
    return Prefab("nw_"..id,fn,assets)
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
        if TheWorld.ismastersim then e.persists=false;e:DoTaskInTime(id=="nw_note_sound" and .7 or 2,e.Remove) end
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
