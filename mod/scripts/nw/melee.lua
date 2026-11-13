local Effects=require("nw/spell_effects")
local Target=require("nw/targeting")
local G=require("nw/geometry")
local Perf=require("nw/perf")
local M={}
-- Distance to a swept circular sector, including the two radial edges.
local function sector(x,z,r,reach,a,b)
    local angle=math.atan2(z,x)
    while angle<a do angle=angle+2*math.pi end
    if angle<=b and x*x+z*z<=(reach+r)^2 then return true end
    return G.hit(0,0,reach*math.cos(a),reach*math.sin(a),x,z,r)
        or G.hit(0,0,reach*math.cos(b),reach*math.sin(b),x,z,r)
end
function M.contains(p,x,z,r,lo,hi)
    if p.width then
        return G.hit(p.reach*lo,0,p.reach*hi,0,x,z,r+p.width/2)~=nil
    end
    local arc=(p.arc or 360)*math.pi/180
    return sector(x,z,r,p.reach,arc*(lo-.5),arc*(hi-.5)) and true or false
end
local function prepare_native(inst,p,x,z)
    if not p.source_weapon or inst._nw_native_checked then return end
    inst._nw_native_checked=true
    local native=SpawnPrefab(p.source_weapon)
    if native then
        native.persists=false
        native:RemoveFromScene()
        native.Transform:SetPosition(x,0,z)
        if native.components.weapon then inst._nw_native=native end
        inst:ListenForEvent("onremove",function() if native:IsValid() then native:Remove() end end)
    end
end
local function strike(inst,owner,e,p,x,z,kx,kz)
    if p.source_weapon=="propsign" then
        if e.sg and e.sg:HasState("knockback") and not e:HasTag("epic") then
            e:PushEvent("knockback",{knocker=inst,radius=p.reach+1,strengthmult=p.pillow})
        end
        return
    end
    prepare_native(inst,p,x,z)
    local native=inst._nw_native
    local typed=native and native.components.damagetypebonus
    local dynamic=native and type(native.components.weapon.damage)=="function"
    if typed or dynamic then
        local factor=typed and typed:GetBonus(e) or 1
        if dynamic and p.native_base_damage and p.native_base_damage>0 then
            factor=factor*native.components.weapon.damage(native,owner,e)/p.native_base_damage
        end
        if factor~=1 then
            p=require("nw/util").copy(p)
            p.damage=p.damage*factor
            if p.planar then p.planar=p.planar*factor end
        end
    end
    if (p.electric or p.planar) and e.components.health and e.components.combat then
        local weapon=inst.components.weapon or inst:AddComponent("weapon")
        weapon:SetDamage(p.damage*Effects.wet_mult(e,p.flags))
        local element
        if p.electric=="always" then weapon:SetElectric();element="electric"
        elseif p.electric=="wet" then
            weapon:SetElectric(1,TUNING.SPEAR_WATHGRITHR_LIGHTNING_WET_DAMAGE_MULT)
            weapon.stimuli=nil
            element=e:GetWetMultiplier()>0 and "electric" or nil
        end
        if p.planar then
            local power=inst.components.planardamage or inst:AddComponent("planardamage")
            power:SetBaseDamage(p.planar)
        end
        local health=e.components.health
        local before=health.currenthealth
        owner.components.combat:DoAttack(e,inst,nil,element,nil,p.reach+1,Vector3(x,0,z))
        Effects.native_hit(owner,e,p,math.max(0,before-math.max(0,health.currenthealth)),kx,kz)
    else
        Effects.direct(owner,e,p,kx,kz)
    end
    if p.source_weapon=="ruins_bat" and e:IsValid() then
        if TryLuckRoll(owner,TUNING.SHADOW_TENTACLE_RUINS_BAT_CHANCE,LuckFormulas.ShadowTentacleSpawn) then
            local tentacle=SpawnPrefab("shadowtentacle")
            require("nw/journal_damage").tag(tentacle,owner,p)
            tentacle.owner=owner;tentacle.Transform:SetPosition(e.Transform:GetWorldPosition())
            tentacle.components.combat:SetTarget(e)
        end
        return
    end
    if native and e:IsValid() and (e.components.health or p.source_weapon=="torch" or p.source_weapon=="lighter") then
        if not ((p.source_weapon=="torch" or p.source_weapon=="lighter") and Effects.evaporate(e,p.damage*Effects.wet_mult(e,p.flags))) then
            native.components.weapon:OnAttack(owner,e)
        end
    end
    if p.pillow and e:IsValid() and e.sg and e.sg:HasState("knockback") and not e:HasTag("epic") then
        e:PushEvent("knockback",{knocker=inst,radius=1,strengthmult=p.pillow})
    end
end
function M.launch(inst,owner,p,x,z,dx,dz,onremove)
    require("nw/balance_damage").tag(inst,p)
    require("nw/projectile_size").visual(inst,require("nw/projectile_size").factor(p))
    if Perf.sample then Perf.sample.melee=Perf.sample.melee+1 end
    inst.Transform:SetPosition(x,0,z);inst.Transform:SetRotation(-math.atan2(dz,dx)/DEGREES)
    inst:ListenForEvent("onremove",onremove)
    if p.source_weapon=="nightstick" or p.source_weapon=="torch" or p.source_weapon=="lighter" or p.source_weapon=="queen_torch" then
        local glow=SpawnPrefab("nw_flyinglight")
        glow.entity:SetParent(inst.entity)
        glow.Transform:SetPosition(0,1.1,0)
        if p.source_weapon=="nightstick" or p.source_weapon=="queen_torch" then glow.Light:SetColour(.5,.68,1) end
    end
    local start,previous,seen=GetTime(),0,{}
    local worked=false
    inst:DoPeriodicTask(2*FRAMES,function()
        if not Effects.live(owner) then inst:Remove();return end
        if inst._nw_motion then
            local px,_,pz=inst.Transform:GetWorldPosition()
            if p.source_weapon=="lighter" then require("nw/engraved_fire").absorb(owner,x,z,px,pz,p.reach) end
            x,z=px,pz
            dx,dz=inst._nw_motion.dx,inst._nw_motion.dz
        end
        local age=GetTime()-start
        local progress=math.min(1,math.max(0,age-(p.strike_delay or 0))/p.windup)
        if not worked and progress>=1 then
            worked=true
            if p.source_weapon=="lighter" then
                local fire=require("nw/engraved_fire")
                fire.absorb(owner,x,z,x+dx*p.reach,z+dz*p.reach,p.reach)
                fire.burst(inst,owner,x,z,p.reach)
            end
            require("nw/weapon_work").strike(inst,owner,p,x,z,dx,dz)
        end
        if progress>previous then
            local nearby=Effects.scan(x,z,p.reach+3.6,p.flags)
            for _,e in ipairs(nearby) do
                local prop=require("nw/expanded_fields").can_break(e,owner)
                    and (Target.egg(e) or not p.flags.targets or p.flags.targets.building)
                if not seen[e] and (prop or Target.allowed(owner,e,p.flags) or Target.selected_object(owner,e,p.flags)) then
                    local tx,_,tz=e.Transform:GetWorldPosition()
                    local rx,rz=tx-x,tz-z
                    -- Projectile sweep includes a .12 contact margin. Preserve
                    -- that same contact when a payload spawns at the near edge.
                    if M.contains(p,rx*dx+rz*dz,rz*dx-rx*dz,e:GetPhysicsRadius(.5)+.12,previous,progress)
                        and Effects.clear(x,z,tx,tz,nearby,e) then
                        seen[e]=true
                        local kx,kz=dx,dz
                        if not p.width then
                            local distance=math.sqrt(rx*rx+rz*rz)
                            if distance>.001 then kx,kz=-rz/distance,rx/distance end
                        end
                        local bonus=e._nw_melee_timeout and require("nw/expanded_hits").consume_melee(e)
                        if prop then e._nw_break(owner)
                        elseif bonus then
                            local hit=require("nw/util").copy(p);hit.damage=hit.damage*bonus
                            strike(inst,owner,e,hit,x,z,kx,kz)
                        else strike(inst,owner,e,p,x,z,kx,kz) end
                        require("nw/explosions").hit(owner,p,tx,tz)
                    end
                end
            end
            previous=progress
        end
        if age>=p.duration then inst:Remove() end
    end,0)
end
return M
