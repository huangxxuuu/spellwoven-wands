-- Server-side consequences of a directional engraving. Native objects used for a
-- single cast never enter the player's inventory or leave a collectible tool.
local M={}
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
    -- Ordinary impacts and expiry no longer add the native smoky puff/sound.
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
        if distance<.001 then dx,dz,distance=1,0,1 end
        local radius=target:GetPhysicsRadius(1.95)+fish:GetPhysicsRadius(.1)+.15
        local fx,fz=x+dx/distance*radius,z+dz/distance*radius
        if fish.Physics then fish.Physics:Teleport(fx,0,fz)
        else fish.Transform:SetPosition(fx,0,fz) end
        owner:PushEvent("fishingcollect",{fish=fish})
        return true
    end
    local pos=target:GetPosition()
    local heading=(owner:GetPosition()-pos):GetNormalizedAndLength()
    local dest=pos+heading*20
    for i=0,80 do
        local point=pos+heading*(i*.25)
        if TheWorld.Map:IsPassableAtPoint(point:Get()) then dest=point;break end
    end
    local fish=target.components.oceanfishable:MakeProjectile()
    if not fish then return false end
    if fish.components.weighable then fish.components.weighable:SetPlayerAsOwner(owner) end
    if fish.components.complexprojectile then
        local flight=fish.components.complexprojectile
        fish.Transform:SetPosition(pos:Get())
        flight:SetGravity(-30)
        flight:SetLaunchOffset(Vector3(0,.5,0));flight:SetTargetOffset(Vector3(0,.2,0))
        flight:SetHorizontalSpeed(math.max(12,flight:CalculateMinimumSpeedForDistance((dest-pos):Length())))
        local onland=flight.onhitfn
        if onland then
            flight:SetOnHit(function(item,attacker,hit)
                item.Physics:Teleport(dest.x,0,dest.z)
                flight:SetOnHit(onland);onland(item,attacker,hit)
            end)
        end
        flight:Launch(dest,fish)
    else
        -- Some floating items have no fishing projectile of their own.
        fish.Transform:SetPosition(dest:Get())
    end
    owner:PushEvent("fishcaught",{fish=fish})
    return true
end
local function harvest(owner,e)
    local pt=e:GetPosition()
    local near=owner:GetDistanceSqToPoint(pt)<=64
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
local function wet(owner,x,z,scale)
    local staff=at("trident",x,z)
    staff.components.inventoryitem.owner=owner
    local pos=Vector3(x,0,z)
    -- The native cast handles ocean targets itself. Extend its impact to dry land once.
    for _,e in ipairs(TheSim:FindEntities(x,0,z,TUNING.TRIDENT.SPELL.RADIUS*scale,nil,{"INLIMBO","outofreach","DECOR","FX"})) do
        if e~=staff and e~=owner and (not e:IsOnOcean(false) or e:GetDistanceSqToPoint(x,0,z)>TUNING.TRIDENT.SPELL.RADIUS^2)
            and (not e.components.health or require("nw/targeting").allowed(owner,e)) then
            staff:DoWaterExplosionEffect(e,owner,pos)
        end
    end
    staff.components.spellcaster:CastSpell(nil,pos,owner)
    staff.components.inventoryitem.owner=nil;staff:Remove()
    require("nw/projectile_size").visual(at("crab_king_waterspout",x,z),scale)
    for _,e in ipairs(TheSim:FindEntities(x,0,z,2*scale,nil,{"INLIMBO","FX"})) do
        DoDeltaMoistureToEntity(e,TUNING.WATERINGCAN_WATER_AMOUNT)
    end
    local manager=TheWorld.components.farming_manager
    if manager then
        local map=TheWorld.Map
        -- A plot can straddle a tile edge. Wet each intersecting tile once.
        local mx,_,mz=map:GetTileCenterPoint(x,0,z)
        local tiles=math.ceil(2*scale/TILE_SCALE)
        for i=-tiles,tiles do for j=-tiles,tiles do
            local cx,cz=mx+i*TILE_SCALE,mz+j*TILE_SCALE
            if cx and math.max(0,math.abs(cx-x)-TILE_SCALE/2)^2+math.max(0,math.abs(cz-z)-TILE_SCALE/2)^2<=4*scale*scale then
                manager:AddSoilMoistureAtPoint(cx,0,cz,TUNING.WATERINGCAN_WATER_AMOUNT)
            end
        end end
    end
end
function M.finish(s,x,z)
    local key=s.p.engraving
    if key=="lighter" then
        require("nw/engraved_fire").burst(s.inst,s.owner,x,z,(s.p.fire_radius or 3)*require("nw/projectile_size").factor(s.p))
    elseif key=="chum" then
        at("splash_green",x,z)
        if TheWorld.Map:IsOceanAtPoint(x,0,z) then at("chum_aoe",x,z):SetThrower(s.owner) end
    elseif key=="trident" then wet(s.owner,x,z,require("nw/projectile_size").factor(s.p))
    elseif key=="orangestaff" then
        -- Natural expiry can happen while the shot is in the void margin.
        if not TheWorld.Map:IsPassableAtPoint(x,0,z,true) then return end
        local owner=s.owner
        local ox,_,oz=owner.Transform:GetWorldPosition()
        at("sand_puff",ox,oz)
        owner.Physics:Teleport(x,0,z)
        at("sand_puff",x,z)
        if TheWorld.Map:IsOceanAtPoint(x,0,z) and not TheWorld.Map:GetPlatformAtPoint(x,z)
            and owner.components.drownable then owner.components.drownable:CheckDrownable() end
    elseif key=="farm_hoe" then
        local tiller=s.inst.components.farmtiller or s.inst:AddComponent("farmtiller")
        return tiller:Till(Vector3(x,0,z),s.owner)
    elseif s.p.ballistic then
        local bell=at(key,x,z)
        -- The native pickup callback enables the corresponding landing routine for mighty throws.
        bell:PushEvent("onputininventory",{HasTag=function(_,tag) return tag=="mightiness_mighty" end})
        local flight=bell.components.complexprojectile
        flight.attacker=s.owner
        require("nw/giant_native").bell(bell,s.owner,require("nw/projectile_size").factor(s.p))
        flight.onhitfn(bell,s.owner,nil)
        if bell:IsValid() then bell:Remove() end
    elseif key=="voidcloth_boomerang" and s.native and s.native:IsValid() then
        local bolt=s.native;s.native=nil
        -- Keep the rendered body's position/interpolation through the handoff.
        -- Native ReturnToThrower sets velocity before its first steering update.
        bolt:FacePoint(s.owner.Transform:GetWorldPosition())
        bolt:ReturnToThrower(s.owner)
        require("nw/world_bounds").watch(bolt)
    elseif key=="staff_tornado" and s.native and s.native:IsValid() then
        local tornado=s.native;s.native=nil
        tornado.Physics:Teleport(x,0,z)
        tornado.components.knownlocations:RememberLocation("target",Vector3(x,0,z))
        tornado:SetDuration(TUNING.TORNADO_LIFETIME)
        tornado.sg:GoToState("idle");tornado:RestartBrain("nw_directed")
        require("nw/world_bounds").watch(tornado)
    end
end
local function bounce(s,e,x,z)
    local last=not s.hits_left or s.hits_left<=1
    local bolt=last and s.native or at("brilliance_projectile_fx",x,z)
    require("nw/projectile_size").native(bolt,s.p)
    bolt.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
    if last then s.native=nil end
    bolt.Physics:Teleport(x,0,z)
    bolt.entity:SetCanSleep(false)
    local staff=at("staff_lunarplant",x,z)
    staff:RemoveFromScene()
    staff.components.inventoryitem.owner=s.owner
    bolt:ListenForEvent("onremove",function()
        staff.components.inventoryitem.owner=nil;staff:Remove()
    end)
    bolt.owner=staff;bolt.initial_hostile=e:HasTag("hostile");bolt.bounces=TUNING.STAFF_LUNARPLANT_BOUNCES
    local cp=bolt.components.projectile
    cp.owner=staff
    cp:Hit(e)
    if bolt:IsValid() then require("nw/world_bounds").watch(bolt) end
end
function M.hit(s,e,x,z)
    local key=s.p.engraving
    if key=="lighter" then
        require("nw/engraved_fire").burst(s.inst,s.owner,x,z,(s.p.fire_radius or 3)*require("nw/projectile_size").factor(s.p))
    elseif (key=="chum" or key=="trident") and s.hits_left and s.hits_left>1 then
        M.finish(s,x,z)
        return true
    elseif filters[key] then
        if not M.accepts(key,e) then M.fade(x,z)
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
