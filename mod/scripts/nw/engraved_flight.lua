local Impact=require("nw/engraved_impact")
local M={}
local native={voidcloth_boomerang="voidcloth_boomerang_proj",firestaff="fire_projectile",icestaff="ice_projectile",
    staff_lunarplant="brilliance_projectile_fx",staff_tornado="tornado"}
local skins={
    chum={"chum_pouch","spin_loop"},fishingrod={"fishingrod","idle"},oceanfishingrod={"oceanfishing_hook","spin_loop",2},
    trident={"gnarwail_horn","idle"},
    voidcloth_scythe={"nw_spell_world","scythe_spin",2},
    farm_hoe={"quagmire_hoe","idle"},minifan={"fan_wheel","spin_loop"},
    shieldofterror={"eye_shield","idle"},yoth_lance={"yoth_lance","idle"},
}
function M.visual(inst,key)
    local v=inst._visual
    if native[key] then v:Hide();return end
    if require("nw/tool_flight").supports(key) then
        require("nw/tool_flight").attach(inst,key)
        return
    end
    if key=="shieldofterror" or key=="lighter" then
        v.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
        v.AnimState:SetBank("nw_spell_world");v.AnimState:SetBuild("nw_spell_world")
        v.AnimState:PlayAnimation(key=="lighter" and "lighter_spin" or key.."_standing",true)
        local scale=key=="shieldofterror" and .75 or 1
        v.Transform:SetScale(scale,scale,scale)
        return
    end
    v.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
    local skin=skins[key]
    local bank=skin and skin[1] or key
    local anim=skin and skin[2] or "spin_loop"
    v.AnimState:SetBank(bank);v.AnimState:SetBuild(bank)
    if key=="oceanfishingrod" then
        v.AnimState:PlayAnimation("spin_pre",false);v.AnimState:PushAnimation("spin_loop",true)
    else v.AnimState:PlayAnimation(anim,true) end
    local scale=skin and skin[3] or 1
    v.Transform:SetScale(scale,scale,scale)
end
function M.aim_ground(inst,s,distance)
    local c=inst.components.complexprojectile
    local base=require("nw/definitions").spells[s.p.base or s.p.id].speed
    local time=math.max(.55,distance/base)
    c:SetGravity(-20)
    c.velocity.x=distance/time*s.p.speed/base
    c.velocity.y=(10*time*time-s.height)/time
    s.speed=c.velocity.x
    require("nw/flight").reset(s,s.dx,s.dz)
    c.velocity.x=math.sqrt(s.vx*s.vx+s.vz*s.vz)
    inst.Physics:SetMotorVel(c.velocity.x,c.velocity.y,0)
end

-- Drive detached native visuals with the same motor as the swept collision body.
-- Repeated Teleport calls bypass client interpolation and make outgoing shots jerk.
function M.sync_native(inst,s)
    local fx=s.native
    if not s.native_height or not fx or not fx:IsValid() then return end
    fx.Transform:SetRotation(inst.Transform:GetRotation())
    local vx,_,vz=inst.Physics:GetMotorVel()
    local scale=fx.Transform:GetScale()
    -- Motor velocity is in the native visual's scaled local coordinates.
    -- Giant art must cover the same world distance as its collision body.
    fx.Physics:SetMotorVel(vx/math.max(.001,scale),0,vz/math.max(.001,scale))
end
function M.launch(inst,s)
    local key=s.p.engraving
    s.inst=inst
    if key=="lighter" then
        local flame=SpawnPrefab("lighterfire")
        flame.entity:SetParent(inst.entity)
        flame.Transform:SetPosition(0,(s.p.ballistic and 0 or s.height)+.08*require("nw/projectile_size").factor(s.p),0)
        inst._nw_flame=flame
        inst:ListenForEvent("onremove",function() if flame:IsValid() then flame:Remove() end end)
    end
    if native[key] then
        local fx=SpawnPrefab(native[key]);s.native=fx;fx._nw_controller=inst
        -- Native staff/boomerang art is not a light source. Only this Mod shot
        -- follows ambient light; keep actual lights such as lighterfire intact.
        fx.AnimState:SetLightOverride(0)
        fx.AnimState:ClearBloomEffectHandle()
        if key=="staff_lunarplant" then
            fx.AnimState:ClearSymbolBloom("light_bar")
            fx.AnimState:ClearSymbolBloom("glow")
        elseif key=="voidcloth_boomerang" then
            fx.AnimState:SetSymbolLightOverride("lightning",0)
        end
        require("nw/balance_damage").tag(fx,s.p)
        require("nw/projectile_size").native(fx,s.p)
        if key=="staff_tornado" then fx._nw_giant= s.p.size_mult end
        -- The native boomerang's .4..1 scale and upright artwork match its return
        -- phase. Do not enlarge the outgoing art by changing its projection.
        fx.AnimState:SetOrientation(key=="voidcloth_boomerang" and ANIM_ORIENTATION.Default or ANIM_ORIENTATION.BillBoard)
        fx.entity:SetCanSleep(false)
        if key=="staff_lunarplant" or key=="staff_tornado" or key=="voidcloth_boomerang" then
            -- These continue under native physics after our directed phase. Parenting
            -- a physics body can leave its native motor immobilized after detachment.
            s.native_height=key=="staff_tornado" and 0 or s.height
            fx.Physics:Teleport(s.x,s.native_height,s.z)
            M.sync_native(inst,s)
        else
            fx.entity:SetParent(inst.entity)
            fx.Transform:SetPosition(0,s.height,0)
        end
        if key=="voidcloth_boomerang" then
            fx.SoundEmitter:PlaySound("rifts4/voidcloth_boomerang/throw_lp","loop")
        elseif key=="staff_tornado" then
            fx.WINDSTAFF_CASTER=s.owner;fx.WINDSTAFF_CASTER_ISPLAYER=s.owner:HasTag("player")
            fx:StopBrain("nw_directed")
            fx.sg:GoToState("empty");fx.AnimState:PlayAnimation("tornado_loop",true)
            if fx.task then fx.task:Cancel();fx.task=nil end
        end
        inst:ListenForEvent("onremove",function() if s.native and s.native:IsValid() then s.native:Remove() end end)
    end
    if key=="shieldofterror" then require("nw/orbit_shield").add(inst,s) end
    if key=="voidcloth_scythe" then s.hits_left=math.huge end
    if s.p.ballistic then
        inst._height:set(0)
        inst.Physics:Teleport(s.x,s.height,s.z)
        local c=inst:AddComponent("complexprojectile")
        c:SetGravity(-35);c.velocity.x=s.speed;c.velocity.y=s.speed*.85
        c:SetOnHit(function()
            local x,_,z=inst.Transform:GetWorldPosition()
            if require("nw/world_bounds").clip(s.x,s.z,x,z) then inst:Remove();return end
            inst.Physics:Teleport(x,0,z)
            local success=Impact.finish(s,x,z)
            if key=="farm_hoe" and not success and s.remaining>0 then
                s.speed=math.sqrt(s.vx*s.vx+s.vz*s.vz)*.8;s.motor_speed=nil
                s.vx,s.vz=s.vx*.8,s.vz*.8
                c.velocity.x=s.speed;c.velocity.y=6;c.velocity.z=0
                inst.Physics:Teleport(x,.1,z)
                inst.Physics:SetMotorVel(c.velocity.x,c.velocity.y,0)
                inst:StartUpdatingComponent(c)
            else
                if key=="farm_hoe" and not success then Impact.fade(x,z) end
                require("nw/projectile_triggers").finish(s,x,z)
                inst:Remove()
            end
        end)
        inst:StartUpdatingComponent(c)
        -- Thrown tools pass through targets; the lighter still terminates on a
        -- hit unless a piercing modifier explicitly grants additional impacts.
        if key~="lighter" then s.hits_left=math.huge end
        inst.Physics:SetRestitution(0)
        M.aim_ground(inst,s,12)
    elseif key=="orangestaff" then s.hits_left=nil;s.bounces=0 end
end
return M
