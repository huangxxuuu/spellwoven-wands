local Caps=require("nw/constants/limits")
local C=require("nw/constants/native").engraved
local Impact=require("nw/engraved_impact")
local M={}
local native=C.native
local skins=C.skins
function M.visual(inst,key)
    local v=inst._visual
    if native[key] then v:Hide();return end
    require("nw/projectile_glow").attach(v)
    if require("nw/tool_flight").supports(key) then
        require("nw/tool_flight").attach(inst,key)
        return
    end
    if key=="shieldofterror" or key=="lighter" then
        v.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
        v.AnimState:SetBank("nw_spell_world");v.AnimState:SetBuild("nw_spell_world")
        v.AnimState:PlayAnimation(key=="lighter" and "lighter_spin" or key.."_standing",true)
        local scale=key=="shieldofterror" and C.shield_scale or 1
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
    local time=math.max(C.min_flight_time,distance/base)
    c:SetGravity(C.aim_gravity)
    c.velocity.x=distance/time*s.p.speed/base
    c.velocity.y=(C.aim_vertical_factor*time*time-s.height)/time
    s.speed=c.velocity.x
    require("nw/flight").reset(s,s.dx,s.dz)
    c.velocity.x=math.sqrt(s.vx*s.vx+s.vz*s.vz)
    inst.Physics:SetMotorVel(c.velocity.x,c.velocity.y,0)
end

function M.sync_native(inst,s)
    local fx=s.native
    if not s.native_height or not fx or not fx:IsValid() then return end
    fx.Transform:SetRotation(inst.Transform:GetRotation())
    local vx,_,vz=inst.Physics:GetMotorVel()
    local scale=fx.Transform:GetScale()
    fx.Physics:SetMotorVel(vx/math.max(Caps.min_motor_scale,scale),0,vz/math.max(Caps.min_motor_scale,scale))
end
function M.launch(inst,s)
    local key=s.p.engraving
    s.inst=inst
    if key=="lighter" then
        local flame=SpawnPrefab("lighterfire")
        flame.entity:SetParent(inst.entity)
        flame.Transform:SetPosition(0,(s.p.ballistic and 0 or s.height)+C.lighter_lift*require("nw/projectile_size").factor(s.p),0)
        inst._nw_flame=flame
        inst:ListenForEvent("onremove",function() if flame:IsValid() then flame:Remove() end end)
    end
    if native[key] then
        local fx=SpawnPrefab(key=="staff_lunarplant" and native[key] or "nw_native_"..native[key]);s.native=fx;fx._nw_controller=inst
        if key=="staff_lunarplant" then
            fx.AnimState:SetLightOverride(0)
            fx.AnimState:ClearBloomEffectHandle()
            fx.AnimState:ClearSymbolBloom("light_bar")
            fx.AnimState:ClearSymbolBloom("glow")
        end
        require("nw/balance_damage").tag(fx,s.p)
        require("nw/projectile_size").native(fx,s.p)
        if key=="staff_tornado" then fx._nw_giant= s.p.size_mult end
        fx.AnimState:SetOrientation(key=="voidcloth_boomerang" and ANIM_ORIENTATION.Default or ANIM_ORIENTATION.BillBoard)
        fx.entity:SetCanSleep(false)
        if key=="staff_lunarplant" or key=="staff_tornado" or key=="voidcloth_boomerang" then
            s.native_height=key=="staff_tornado" and 0 or s.height
            fx.Physics:Teleport(s.x,s.native_height,s.z)
            M.sync_native(inst,s)
        else
            fx.entity:SetParent(inst.entity)
            fx.Transform:SetPosition(0,s.height,0)
        end
        if key~="staff_lunarplant" then require("nw/projectile_glow").native(fx) end
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
        c:SetGravity(C.ballistic_gravity);c.velocity.x=s.speed;c.velocity.y=s.speed*C.ballistic_vertical_mult
        c:SetOnHit(function()
            local x,_,z=inst.Transform:GetWorldPosition()
            if require("nw/world_bounds").clip(s.x,s.z,x,z) then inst:Remove();return end
            inst.Physics:Teleport(x,0,z)
            local success=Impact.finish(s,x,z)
            if key=="farm_hoe" and not success and s.remaining>0 then
                s.speed=math.sqrt(s.vx*s.vx+s.vz*s.vz)*C.hoe_speed_mult;s.motor_speed=nil
                s.vx,s.vz=s.vx*C.hoe_speed_mult,s.vz*C.hoe_speed_mult
                c.velocity.x=s.speed;c.velocity.y=C.hoe_rebound_speed;c.velocity.z=0
                inst.Physics:Teleport(x,C.hoe_rebound_height,z)
                inst.Physics:SetMotorVel(c.velocity.x,c.velocity.y,0)
                inst:StartUpdatingComponent(c)
            else
                if key=="farm_hoe" and not success then Impact.fade(x,z) end
                require("nw/projectile_triggers").finish(s,x,z)
                inst:Remove()
            end
        end)
        inst:StartUpdatingComponent(c)
        if key~="lighter" then s.hits_left=math.huge end
        inst.Physics:SetRestitution(0)
        M.aim_ground(inst,s,C.aim_distance)
    elseif key=="orangestaff" then s.hits_left=nil;s.bounces=0 end
end
return M
