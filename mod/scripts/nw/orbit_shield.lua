local M={}
local function position(owner,inst,index,count,initial)
    local x,_,z=owner.Transform:GetWorldPosition()
    local dt=FRAMES
    local angle=(GetTime()+(initial and 0 or dt))*3 + (index-1)*2*math.pi/count
    local tx,tz=x+2*math.cos(angle),z+2*math.sin(angle)
    if initial then inst.Physics:Teleport(tx,0,tz);return end
    local sx,_,sz=inst.Transform:GetWorldPosition()
    local dx,dz=tx-sx,tz-sz
    if dx*dx+dz*dz>64*64 then
        -- Follow a teleported owner without crossing the whole map.
        inst.Physics:TeleportRespectingInterpolation(tx,0,tz)
        inst.Physics:Stop()
    else
        inst.Transform:SetRotation(-math.atan2(dz,dx)/DEGREES)
        inst.Physics:SetMotorVel(math.sqrt(dx*dx+dz*dz)/dt,0,0)
    end
end
function M.add(inst,s)
    local owner=s.owner
    local list=owner._nw_shields or {}
    owner._nw_shields=list
    list[#list+1]=inst;s.armor=50
    inst.Physics:Stop()
    position(owner,inst,#list,#list,true)
    inst:ListenForEvent("onremove",function()
        for i,shield in ipairs(list) do if shield==inst then table.remove(list,i);break end end
        if #list==0 then owner._nw_shields=nil end
    end)
end
function M.update(inst,s,now,timers)
    local list=s.owner._nw_shields
    for i,shield in ipairs(list) do if shield==inst then position(s.owner,inst,i,#list);break end end
    local elapsed=math.max(0,math.min(now-s.time,s.remaining))
    s.age=(s.age or 0)+elapsed;s.remaining=s.remaining-elapsed;s.time=now
    local x,_,z=inst.Transform:GetWorldPosition()
    if require("nw/world_bounds").outside(x,z) then inst:Remove();return end
    local triggers=require("nw/projectile_triggers")
    if s.p.event=="timer" and not s.timer_done and s.age+.000001>=(s.p.time or .5) then triggers.timer(s,x,z,timers) end
    if s.remaining<=.000001 then triggers.finish(s,x,z);inst:Remove() end
end
-- Inventory:ApplyDamage is the game's pre-armour entry point (after dodge).
function M.install_inventory(inv)
    local original=inv.ApplyDamage
    inv.ApplyDamage=function(self,damage,attacker,weapon,special,...)
        local list=self.inst._nw_shields
        local combat=attacker and attacker.components.combat
        if list and combat then
            local area=combat._nw_attack_area
            local center=area and area.pos or combat.temppos or attacker:GetPosition()
            local radius=area and area.radius or combat:GetHitRange()
            local arc=not area and combat.hitarc
            local remaining=damage or 0
            local total=remaining+require("components/spdamageutil").CalcTotalDamage(special)
            for i=#list,1,-1 do
                local shield=list[i]
                if total<=0 then break end
                local sx,_,sz=shield.Transform:GetWorldPosition()
                local angle=math.atan2(center.z-sz,sx-center.x)*RADIANS
                if self.inst:GetDistanceSqToPoint(center)<=(radius+self.inst:GetPhysicsRadius(0))^2
                    and shield:GetDistanceSqToPoint(center)<=radius*radius
                    and (not arc or 2*DiffAngle(attacker.Transform:GetRotation(),angle)<=arc) then
                    local taken=math.min(total,shield._shot.armor)
                    local fraction=(total-taken)/total
                    remaining=remaining*fraction
                    if special then
                        local reduced={}
                        for k,n in pairs(special) do reduced[k]=n*fraction end
                        special=reduced
                    end
                    total=total-taken
                    shield._shot.armor=shield._shot.armor-taken
                    local fx=SpawnPrefab("round_puff_fx_sm");fx.Transform:SetPosition(shield.Transform:GetWorldPosition())
                    if shield._shot.armor<=0 then
                        require("nw/projectile_triggers").finish(shield._shot,sx,sz)
                        shield:Remove()
                    end
                end
            end
            damage=remaining
        end
        return original(self,damage,attacker,weapon,special,...)
    end
end
function M.install_combat(combat)
    local attack=combat.DoAttack
    combat.DoAttack=function(self,target,weapon,projectile,...)
        local flight=projectile and projectile.components.projectile
        if not flight then return attack(self,target,weapon,projectile,...) end
        local prior=self._nw_attack_area
        self._nw_attack_area={pos=projectile:GetPosition(),radius=flight.hitdist}
        local result=attack(self,target,weapon,projectile,...)
        self._nw_attack_area=prior
        return result
    end
    local original=combat.DoAreaAttack
    combat.DoAreaAttack=function(self,target,range,...)
        local old=self._nw_attack_area
        self._nw_attack_area={pos=target:GetPosition(),radius=range}
        local n=original(self,target,range,...)
        self._nw_attack_area=old
        return n
    end
end
return M
