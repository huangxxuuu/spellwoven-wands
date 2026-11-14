local C=require("nw/constants/native_effects")
local Projectile=require("nw/constants/projectiles")
local M={}
local Target=require("nw/targeting")
local Native=require("nw/native_targeting")
local Limits=require("nw/spell_limits")
local function limit_return(bolt)
    if bolt._nw_return_speed_limited then return end
    bolt._nw_return_speed_limited=true
    local function apply(inst)
        if inst:IsValid() then
            local vx,vy,vz=inst.Physics:GetMotorVel()
            Limits.set_motor_velocity(inst,vx,vy,vz)
        end
    end
    local returning=bolt.ReturnToThrower
    bolt.ReturnToThrower=function(inst,...)
        returning(inst,...);apply(inst)
    end
    local looper=bolt.components.updatelooper
    local update=looper.OnUpdate
    looper.OnUpdate=function(self,...)
        update(self,...);apply(self.inst)
    end
end
local function limit_bounce(bolt)
    local flight=bolt.components.projectile
    if flight._nw_speed_limited then return end
    flight._nw_speed_limited=true
    local set_speed=flight.SetSpeed
    flight.SetSpeed=function(self,speed)
        local scale=Limits.motor_scale(self.inst)
        set_speed(self,math.max(-Limits.max_speed,math.min(Limits.max_speed,speed))/scale)
    end
    if flight.speed then flight:SetSpeed(flight.speed) end
end
local filters={fishingrod="fishable",oceanfishingrod="oceanfishable",voidcloth_scythe="pickable"}
M.filters=filters
function M.accepts(key,e)
    if key=="fishingrod" then return e.components.fishable and not e.components.fishable:IsFrozenOver() end
    if key=="oceanfishingrod" then return e.components.oceanfishable and not e.components.oceanfishable:GetRod()
        and not e:HasTag("activeprojectile") and not e:HasTag("FX") end
    return e.components.pickable and e.components.pickable:CanBePicked() and e:HasOneOfTags(HARVESTABLE_PLANT_TARGET_TAGS)
end
local function at(name,x,z)
    local inst=SpawnPrefab(name)
    inst.Transform:SetPosition(x,0,z)
    return inst
end
function M.fade(x,z)
end
local function reel(owner,target,ocean)
    local x,_,z=target.Transform:GetWorldPosition()
    local fx=at(ocean and "nw_reel_ocean_fx" or "nw_reel_pond_fx",x,z)
    fx:FacePoint(owner.Transform:GetWorldPosition())
    if not ocean then
        local pond=target.components.fishable
        if pond.fishleft<=0 then return false end
        local fish=pond:HookFish(owner)
        if not fish then return false end
        pond:RemoveFish(fish)
        fish.entity:Show();fish.persists=true
        if fish.DynamicShadow then fish.DynamicShadow:Enable(true) end
        if fish.Physics then fish.Physics:SetActive(true) end
        local ox,_,oz=owner.Transform:GetWorldPosition()
        local dx,dz=ox-x,oz-z
        local distance=math.sqrt(dx*dx+dz*dz)
        if distance<C.reel.direction_epsilon then dx,dz,distance=1,0,1 end
        local radius=target:GetPhysicsRadius(C.reel.pond_radius)+fish:GetPhysicsRadius(C.reel.fish_radius)+C.reel.padding
        local fx,fz=x+dx/distance*radius,z+dz/distance*radius
        if fish.Physics then fish.Physics:Teleport(fx,0,fz)
        else fish.Transform:SetPosition(fx,0,fz) end
        owner:PushEvent("fishingcollect",{fish=fish})
        return true
    end
    local pos=target:GetPosition()
    local heading=(owner:GetPosition()-pos):GetNormalizedAndLength()
    local dest=pos+heading*C.reel.max_distance
    for i=0,C.reel.steps do
        local point=pos+heading*(i*C.reel.step)
        if TheWorld.Map:IsPassableAtPoint(point:Get()) then dest=point;break end
    end
    local fish=target.components.oceanfishable:MakeProjectile()
    if not fish then return false end
    if fish.components.weighable then fish.components.weighable:SetPlayerAsOwner(owner) end
    if fish.components.complexprojectile then
        local flight=fish.components.complexprojectile
        fish.Transform:SetPosition(pos:Get())
        flight:SetGravity(C.reel.gravity)
        flight:SetLaunchOffset(Vector3(0,C.reel.launch_height,0));flight:SetTargetOffset(Vector3(0,C.reel.target_height,0))
        flight:SetHorizontalSpeed(math.min(Limits.max_speed,math.max(C.reel.min_speed,flight:CalculateMinimumSpeedForDistance((dest-pos):Length()))))
        local onland=flight.onhitfn
        if onland then
            flight:SetOnHit(function(item,attacker,hit)
                item.Physics:Teleport(dest.x,0,dest.z)
                flight:SetOnHit(onland);onland(item,attacker,hit)
            end)
        end
        flight:Launch(dest,fish)
    else
        fish.Transform:SetPosition(dest:Get())
    end
    owner:PushEvent("fishcaught",{fish=fish})
    return true
end
local function harvest(owner,e)
    local pt=e:GetPosition()
    local near=owner:GetDistanceSqToPoint(pt)<=C.harvest.inventory_range^2
    local _,items=e.components.pickable:Pick(TheWorld)
    for _,item in ipairs(items or {}) do
        item.Transform:SetPosition(pt:Get())
        local inv=owner.components.inventory
        if near and inv and item.components.inventoryitem then
            local size=item.components.stackable and item.components.stackable:StackSize() or 1
            local count=inv:CanAcceptCount(item,size)
            if count>0 then
                inv:GiveItem(count<size and item.components.stackable:Get(count) or item,nil,pt)
            end
        end
    end
end
local function wet(owner,x,z,scale,p)
    local staff=at("trident",x,z)
    require("nw/journal_damage").tag(staff,owner,p)
    staff.components.inventoryitem.owner=owner
    local pos=Vector3(x,0,z)
    local native=staff.DoWaterExplosionEffect
    local hitplayers={}
    local flags=Target.flags(p)
    local custom=scale<1 or flags and flags.targets
    staff.DoWaterExplosionEffect=function(self,e,caster,position)
        if not Native.accepts(owner,e,p) then return end
        if scale<1 and e:GetDistanceSqToPoint(x,0,z)>(TUNING.TRIDENT.SPELL.RADIUS*scale)^2 then return end
        if e:HasTag("player") then
            if not hitplayers[e] and not e:HasTag("playerghost") and e.components.combat then
                hitplayers[e]=true;e.components.combat:GetAttacked(caster,TUNING.TRIDENT.SPELL.DAMAGE,self)
            end
        elseif e.components.health and not e.components.combat then
            return require("nw/balance_damage").delta(p,e,-TUNING.TRIDENT.SPELL.DAMAGE*(p.base_damage_multiplier or 1),nil,self.prefab,nil,caster)
        else return native(self,e,caster,position) end
    end
    for _,e in ipairs(TheSim:FindEntities(x,0,z,TUNING.TRIDENT.SPELL.RADIUS*scale,nil,{"INLIMBO","outofreach","DECOR","FX"})) do
        if e~=staff and (e:HasTag("player") or not e:IsOnOcean(false) or not custom and e:GetDistanceSqToPoint(x,0,z)>TUNING.TRIDENT.SPELL.RADIUS^2)
            and (flags and flags.targets or e:HasTag("player") or not e.components.health or Target.allowed(owner,e)) then
            staff:DoWaterExplosionEffect(e,owner,pos)
        end
    end
    if custom then
        staff.components.spellcaster:SetSpellFn(function(inst,_,position)
            require("nw/native_size").trident(inst,owner,position,scale,p)
        end)
    end
    staff.components.spellcaster:CastSpell(nil,pos,owner)
    staff.components.inventoryitem.owner=nil;staff:Remove()
    require("nw/projectile_size").visual(at(TheWorld.Map:IsOceanAtPoint(x,0,z)
        and "crab_king_waterspout" or "groundpound_fx",x,z),scale)
    for _,e in ipairs(TheSim:FindEntities(x,0,z,C.trident.wet_radius*scale,nil,{"INLIMBO","FX"})) do
        if Native.accepts(owner,e,p) then DoDeltaMoistureToEntity(e,TUNING.WATERINGCAN_WATER_AMOUNT) end
    end
    local manager=TheWorld.components.farming_manager
    if manager and Target.allows_category(flags,"nature") then
        local map=TheWorld.Map
        local mx,_,mz=map:GetTileCenterPoint(x,0,z)
        local tiles=math.ceil(C.trident.wet_radius*scale/TILE_SCALE)
        for i=-tiles,tiles do for j=-tiles,tiles do
            local cx,cz=mx+i*TILE_SCALE,mz+j*TILE_SCALE
            if cx and math.max(0,math.abs(cx-x)-TILE_SCALE/2)^2+math.max(0,math.abs(cz-z)-TILE_SCALE/2)^2<=C.trident.wet_radius^2*scale*scale then
                manager:AddSoilMoistureAtPoint(cx,0,cz,TUNING.WATERINGCAN_WATER_AMOUNT)
            end
        end end
    end
end
function M.finish(s,x,z)
    local key=s.p.engraving
    if key=="lighter" then
        require("nw/engraved_fire").burst(s.inst,s.owner,x,z,(s.p.fire_radius or Projectile.engraved_special.fire_radius)*require("nw/projectile_size").factor(s.p),nil,s.p)
    elseif key=="chum" then
        if TheWorld.Map:IsOceanAtPoint(x,0,z) then
            at("splash_green",x,z);at("chum_aoe",x,z):SetThrower(s.owner)
        else at("sand_puff",x,z) end
    elseif key=="trident" then wet(s.owner,x,z,require("nw/projectile_size").factor(s.p),s.p)
    elseif key=="orangestaff" then
        local ocean=TheWorld.Map:IsOceanAtPoint(x,0,z)
        if not ocean and not TheWorld.Map:IsPassableAtPoint(x,0,z,true) then return end
        local owner=s.owner
        local ox,_,oz=owner.Transform:GetWorldPosition()
        at("sand_puff",ox,oz)
        owner.Physics:Teleport(x,0,z)
        at("sand_puff",x,z)
        if ocean and not TheWorld.Map:GetPlatformAtPoint(x,z) and owner.components.drownable then
            owner:DoTaskInTime(0,function()
                if owner:IsValid() and owner.components.drownable then owner.components.drownable:CheckDrownable() end
            end)
        end
    elseif key=="farm_hoe" then
        local tiller=s.inst.components.farmtiller or s.inst:AddComponent("farmtiller")
        return tiller:Till(Vector3(x,0,z),s.owner)
    elseif s.p.ballistic then
        local bell=at(key,x,z)
        require("nw/journal_damage").tag(bell,s.owner,s.p)
        bell:PushEvent("onputininventory",{HasTag=function(_,tag) return tag=="mightiness_mighty" end})
        local flight=bell.components.complexprojectile
        flight.attacker=s.owner
        require("nw/giant_native").bell(bell,s.owner,require("nw/projectile_size").factor(s.p))
        if Native.context(bell) then
            require("nw/native_size").filtered(flight.onhitfn,1,C.bell.radius,x,z,function() return false end,bell,s.owner,nil)
        else
            require("nw/native_size").call(flight.onhitfn,require("nw/projectile_size").factor(s.p),C.bell.radius,x,z,bell,s.owner,nil)
        end
        local landing=at("nw_tool_land_"..key,x,z)
        require("nw/projectile_size").visual(landing,require("nw/projectile_size").factor(s.p))
        if bell:IsValid() then bell:Remove() end
    elseif key=="voidcloth_boomerang" and s.native and s.native:IsValid() then
        local bolt=s.native;s.native=nil;bolt._nw_controller=nil
        require("nw/journal_damage").tag(bolt,s.owner,s.p)
        limit_return(bolt)
        bolt:FacePoint(s.owner.Transform:GetWorldPosition())
        bolt:ReturnToThrower(s.owner)
        require("nw/world_bounds").watch(bolt)
    elseif key=="staff_tornado" and s.native and s.native:IsValid() then
        local tornado=s.native;s.native=nil;tornado._nw_controller=nil
        require("nw/journal_damage").tag(tornado,s.owner,s.p)
        tornado.Physics:Teleport(x,0,z)
        tornado.components.knownlocations:RememberLocation("target",Vector3(x,0,z))
        local locomotor=tornado.components.locomotor
        local scale=Limits.motor_scale(tornado)
        locomotor.walkspeed=math.min(Limits.max_speed,locomotor.walkspeed)/scale
        locomotor.runspeed=math.min(Limits.max_speed,locomotor.runspeed)/scale
        tornado:SetDuration(TUNING.TORNADO_LIFETIME)
        tornado.sg:GoToState("idle");tornado:RestartBrain("nw_directed")
        require("nw/world_bounds").watch(tornado)
    end
end
local function bounce(s,e,x,z)
    local last=not s.hits_left or s.hits_left<=1
    local bolt=last and s.native or at("brilliance_projectile_fx",x,z)
    require("nw/journal_damage").tag(bolt,s.owner,s.p)
    bolt._nw_controller=nil
    require("nw/projectile_size").native(bolt,s.p)
    bolt.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
    if last then s.native=nil end
    bolt.Physics:Teleport(x,0,z)
    bolt.entity:SetCanSleep(false)
    local staff=at("staff_lunarplant",x,z)
    require("nw/journal_damage").tag(staff,s.owner,s.p)
    staff:RemoveFromScene()
    staff.components.inventoryitem.owner=s.owner
    bolt:ListenForEvent("onremove",function()
        staff.components.inventoryitem.owner=nil;staff:Remove()
    end)
    bolt.owner=staff;bolt.initial_hostile=e:HasTag("hostile");bolt.bounces=TUNING.STAFF_LUNARPLANT_BOUNCES
    local cp=bolt.components.projectile
    limit_bounce(bolt)
    cp.owner=staff
    Native.bounce(bolt)
    cp:Hit(e)
    if bolt:IsValid() then require("nw/world_bounds").watch(bolt) end
end
function M.hit(s,e,x,z)
    local key=s.p.engraving
    if key=="lighter" then
        require("nw/engraved_fire").burst(s.inst,s.owner,x,z,(s.p.fire_radius or Projectile.engraved_special.fire_radius)*require("nw/projectile_size").factor(s.p),e,s.p)
    elseif (key=="chum" or key=="trident") and s.hits_left and s.hits_left>1 then
        M.finish(s,x,z)
        return true
    elseif filters[key] then
        if not Native.accepts(s.owner,e,s.p,function(_,target) return M.accepts(key,target) end) then M.fade(x,z)
        elseif key=="voidcloth_scythe" then harvest(s.owner,e)
        elseif not reel(s.owner,e,key=="oceanfishingrod") then M.fade(x,z) end
        return true
    elseif key=="firestaff" or key=="icestaff" then
        local staff=at(key,x,z)
        staff.components.weapon.onattack(staff,s.owner,e,true)
        local projectile=at(key=="firestaff" and "fire_projectile" or "ice_projectile",x,z)
        projectile.components.projectile.onhit(projectile,s.owner,e)
        staff:Remove()
        return true
    elseif key=="staff_lunarplant" then bounce(s,e,x,z);return true
    end
    return s.p.no_impact_damage
end
return M
