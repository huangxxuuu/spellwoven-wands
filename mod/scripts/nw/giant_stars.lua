-- Native temperature/aura searches have fixed radii. Keep all native tags and
-- interactions; add only the contribution those searches cannot account for,
-- at distance / scale, without creating extra heater entities.
local M={}
local function stars() return TheWorld._nw_giant_stars end
function M.pulse(inst)
    -- The native factory creates one 0.1 s light pulse before our wrapper runs.
    -- Keep that callback (including pulse-time synchronization) and scale its
    -- output, on both server and client, without a competing timer.
    for task in pairs(inst.pendingtasks or {}) do
        if task.period==.1 then
            local pulse=task.fn
            task.fn=function(e,...)
                pulse(e,...)
                local scale=e._nw_star_size:value()
                e.Light:SetRadius(e.Light:GetRadius()*(scale>0 and scale or 1))
            end
            return
        end
    end
    error("NW_STARS: native light pulse missing")
end
function M.apply(inst,p)
    local scale=require("nw/projectile_size").factor(p)
    inst._nw_star_size:set(scale)
    require("nw/projectile_size").field(inst,p)
    if scale==1 or inst._nw_giant_star then return end
    inst._nw_giant_star=scale
    local set=stars() or {};TheWorld._nw_giant_stars=set;set[inst]=true
    inst:ListenForEvent("onremove",function() set[inst]=nil;if not next(set) then TheWorld._nw_giant_stars=nil end end)
    local aura=inst.components.sanityaura
    aura.max_distsq=TUNING.SANITY_EFFECT_RANGE^2*scale^2
    aura.fallofffn=function(_,_,d2) return math.max(1,d2/(scale*scale)) end
    local prop=inst.components.propagator
    if prop then
        prop.propagaterange=prop.propagaterange*scale
        prop.damagerange=prop.damagerange*scale
    end
end
local function available(star)
    return star:IsValid() and not star:IsInLimbo()
end
function M.heat(c,item)
    local observer=c.inst
    local owner=observer.components.inventoryitem and observer.components.inventoryitem.owner
    if c.settemp~=nil or observer.is_teleporting or observer.components.health and observer.components.health:IsInvincible()
        or owner and (owner:HasTag("pocketdimension_container") or owner:HasTag("fridge") and not owner:HasTag("nocool")) then return 0,0 end
    local delta,power=0,0
    local current=item and c.temperature or c.current
    local overheat=item and c.maxtemp-20 or c.overheattemp
    local ignored=item and {"heatrock","INLIMBO"} or c.ignoreheatertags
    for star in pairs(stars() or {}) do
        if available(star) and not star:HasAnyTag(unpack(ignored)) then
            local h=star.components.heater
            local d2=observer:GetDistanceSqToInst(star)
            local heat=h:GetHeat(observer)
            if heat then
                local function contribution(scale)
                    local factor=1-d2/(100*scale^2)
                    if factor<=0 then return 0,0 end
                    if observer:GetIsWet() and not (item and c.nowetpenalty) then
                        local wet=TUNING.WET_HEAT_FACTOR_PENALTY
                        if heat>0 then factor=factor*wet elseif wet~=0 then factor=factor/wet end
                    end
                    if h:IsExothermic() then
                        return math.max(0,heat*factor-current),factor
                    elseif h:IsEndothermic() then
                        return math.min(0,(heat-overheat)*factor+overheat-current),0
                    end
                    return 0,0
                end
                local desired,p=contribution(star._nw_giant_star)
                local native,np=contribution(1)
                delta=delta+desired-native;power=power+p-np
            end
        end
    end
    return delta,power
end
function M.item_temperature(c)
    local calculate=c.GetTargetDeltaTemperature
    c.GetTargetDeltaTemperature=function(self,...)
        local delta,rate=calculate(self,...)
        if stars() then
            local extra,power=M.heat(self,true)
            delta=delta+extra;self.externalheaterpower=self.externalheaterpower+power
        end
        return delta,rate
    end
end
function M.temperature(c)
    local update=c.OnUpdate
    c.OnUpdate=function(self,...)
        if not stars() then return update(self,...) end
        local delta,power=M.heat(self)
        self.totalmodifiers=self.totalmodifiers+delta
        update(self,...)
        self.totalmodifiers=self.totalmodifiers-delta
        self.externalheaterpower=self.externalheaterpower+power
    end
end
function M.aura(c)
    if c.sanity_aura_immune_sources:Get() then return 0 end
    local sum=0
    for star in pairs(stars() or {}) do
        if available(star) and c.inst:GetDistanceSqToInst(star)>TUNING.SANITY_AURA_SEACH_RANGE^2 then
            local immune=false
            for tag,sources in pairs(c.sanity_aura_immunities or {}) do
                if sources:Get() and star:HasTag(tag) then immune=true;break end
            end
            if not immune then sum=sum+star.components.sanityaura:GetAura(c.inst) end
        end
    end
    return sum
end
function M.sanity(c)
    local recalc=c.Recalc
    c.Recalc=function(self,...)
        if not stars() then return recalc(self,...) end
        self.externalmodifiers:SetModifier(self.inst,M.aura(self),"nw_giant_star")
        recalc(self,...)
        self.externalmodifiers:RemoveModifier(self.inst,"nw_giant_star")
    end
end
return M
