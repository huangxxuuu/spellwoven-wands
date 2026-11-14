local C=require("nw/constants/native_effects").bounce
local Target=require("nw/targeting")
local M={}
local function pack(...) return {n=select("#",...),...} end
function M.accepts(owner,e,p,predicate)
    local flags=Target.flags(p)
    if not (flags and flags.targets) then return not predicate or predicate(owner,e) end
    return Target.accepts(owner,e,flags,{default=true,predicate=predicate})
end
function M.tag(inst,owner,p)
    local key=p and p.engraving
    local name=inst and (inst._nw_native_prefab or inst.prefab)
    local continuation=(key=="trident" and name=="trident")
        or (key=="staff_lunarplant" and (name=="staff_lunarplant" or name=="brilliance_projectile_fx"))
        or (key=="staff_tornado" and name=="tornado")
        or (key and key:find("^dumbbell") and name==key)
        or (p and p.source_weapon=="ruins_bat" and name=="shadowtentacle")
    local flags=Target.flags(p)
    if continuation then
        inst._nw_native_targets=flags and flags.targets
            and {owner=owner,flags=require("nw/util").copy(flags)} or nil
    end
end
function M.context(inst) return inst and inst._nw_native_targets end
function M.permits(inst,e)
    local source=M.context(inst)
    return not source or Target.accepts(source.owner,e,Target.flags(source))
end
local function source_for(attacker,weapon,projectile)
    return M.context(weapon) or M.context(projectile) or M.context(attacker)
end
function M.wrap_combat(combat)
    if combat._nw_targeting_wrapped then return end
    combat._nw_targeting_wrapped=true
    local key=combat.GetAttacked_Internal and "GetAttacked_Internal" or "GetAttacked"
    local attacked=combat[key]
    combat[key]=function(self,attacker,damage,weapon,...)
        local source=source_for(attacker,weapon)
        local target=self.redirected_from or self.inst
        if source and not Target.accepts(source.owner,target,Target.flags(source),{components={"health","combat"}}) then return false end
        return attacked(self,attacker,damage,weapon,...)
    end
    local attack=combat.DoAttack
    if not attack then return end
    combat.DoAttack=function(self,target,weapon,projectile,stimuli,...)
        local source=source_for(self.inst,weapon,projectile)
        if not source then return attack(self,target,weapon,projectile,stimuli,...) end
        target=target or self.target
        if not Target.accepts(source.owner,target,Target.flags(source),{components={"health","combat"}}) then return end
        if target:HasTag("player") then
            if not target.components.combat:CanBeAttacked() then return end
            local damage,special=self:CalcDamage(target,weapon)
            local result=target.components.combat:GetAttacked(self.inst,damage,weapon,stimuli,special)
            if weapon and weapon.components.weapon and target:IsValid() then
                weapon.components.weapon:OnAttack(self.inst,target,projectile)
            end
            return result
        end
        return attack(self,target,weapon,projectile,stimuli,...)
    end
end

function M.projectile(inst)
    local flight=inst.components.projectile
    if not flight or flight._nw_targeting_wrapped then return end
    flight._nw_targeting_wrapped=true
    local hit,update=flight.Hit,flight.OnUpdate
    if hit then flight.Hit=function(self,target,...)
        if not M.permits(inst,target) then return self:Miss(target) end
        return hit(self,target,...)
    end end
    if update then flight.OnUpdate=function(self,...)
        if self.target and not M.permits(inst,self.target) then return self:Miss(self.target) end
        return update(self,...)
    end end
end

function M.bounce(inst)
    if not M.context(inst) or inst._nw_target_bounce then return end
    M.projectile(inst)
    local flight=inst.components.projectile
    local hit=flight.onhit
    local search
    for i=1,debug and debug.getupvalue and C.upvalue_limit or 0 do
        local name,value=debug.getupvalue(hit,i)
        if not name then break end
        if name=="TryBounce" then search=value;break end
    end
    inst._nw_target_bounce=true
    if not search then
        flight.onhit=function(self,...) self.bounces=1;return hit(self,...) end
        return false
    end
    local function rebound(self,x,z,attacker,previous)
        local context=M.context(self)
        local candidates={}
        for _,e in ipairs(TheSim:FindEntities(x,0,z,C.search_radius,nil,
            {"INLIMBO","notarget","flight","invisible","noattack","hiding"})) do
            if e~=previous and e.entity:IsVisible() and Target.accepts(context.owner,e,Target.flags(context)) then
                local recent=0
                for i,v in ipairs(self.recenttargets or {}) do if v==e then recent=i;break end end
                candidates[#candidates+1]={entity=e,recent=recent,hostile=e:HasTag("hostile"),same=e.prefab==previous.prefab}
            end
        end
        table.sort(candidates,function(a,b)
            if a.hostile~=b.hostile then return a.hostile end
            if (a.recent==0)~=(b.recent==0) then return a.recent==0 end
            if a.recent~=b.recent then return a.recent<b.recent end
            if a.same~=b.same then return a.same end
            return a.entity.GUID<b.entity.GUID
        end)
        local choice=candidates[1]
        if not choice then self:Remove();return end
        local recent=self.recenttargets or {}
        if choice.recent>0 then table.remove(recent,choice.recent) end
        recent[#recent+1]=previous;self.recenttargets=recent
        self.Physics:Teleport(x,0,z);self:Show()
        flight:SetSpeed(C.speed);flight:SetBounced(true)
        flight.overridestartpos=Vector3(x,0,z)
        flight:Throw(self.owner,choice.entity,attacker)
    end
    flight.onhit=function(self,...)
        local schedule=self.DoTaskInTime
        self.DoTaskInTime=function(entity,time,fn,...)
            return schedule(entity,time,fn==search and rebound or fn,...)
        end
        local result=pack(pcall(hit,self,...))
        self.DoTaskInTime=schedule
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
end
return M
