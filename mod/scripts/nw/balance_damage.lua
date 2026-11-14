local M=require("nw/util").copy(require("nw/constants/balance").repeated_hit)
local function balanced() return require("nw/balance").is_balanced() end
function M.multiplier(previous_hits)
    return M.floor+(1-M.floor)*M.decay^previous_hits
end
function M.root(inherited)
    if inherited then return inherited end
    if not balanced() then return end
    return TheWorld.components.nw_identity:Next()
end
function M.tag(inst,p)
    if inst and p then inst._nw_root=p._nw_root end
end
function M.parameters(p,root)
    if not root or p._nw_root==root then return p end
    local copy={}
    for k,v in pairs(p) do copy[k]=v end
    copy._nw_root=root
    return copy
end
local function prune(inst)
    inst._nw_balance_cleanup=nil
    local hits=inst._nw_balance_hits
    if not hits then return end
    local now=GetTime()
    local next_expiry=math.huge
    for root,hit in pairs(hits) do
        if now-hit.last>=M.timeout then hits[root]=nil
        else next_expiry=math.min(next_expiry,hit.last+M.timeout) end
    end
    if next(hits)==nil then inst._nw_balance_hits=nil
    elseif inst.DoTaskInTime then inst._nw_balance_cleanup=inst:DoTaskInTime(math.max(0,next_expiry-now),prune) end
end
function M.factor(inst,root)
    if not root or not balanced() then return 1 end
    local hit=inst._nw_balance_hits and inst._nw_balance_hits[root]
    if not hit or GetTime()-hit.last>=M.timeout then return 1 end
    return M.multiplier(hit.count)
end
local function commit(inst,root)
    local hits=inst._nw_balance_hits or {}
    inst._nw_balance_hits=hits
    local now=GetTime()
    local hit=hits[root]
    if not hit or now-hit.last>=M.timeout then hit={count=0};hits[root]=hit end
    hit.count=hit.count+1;hit.last=now
    if not inst._nw_balance_cleanup and inst.DoTaskInTime then
        inst._nw_balance_cleanup=inst:DoTaskInTime(M.timeout,prune)
    end
end
local function pack(...) return {n=select("#",...),...} end
local function wrap_health(health)
    if health._nw_balance_wrapped or not health.DoDelta then return end
    health._nw_balance_wrapped=true
    local delta=health.DoDelta
    health.DoDelta=function(self,amount,...)
        local token=self._nw_balance_token
        if not token or not amount or amount>=0 then return delta(self,amount,...) end
        self._nw_balance_token=nil;token.observed=true
        local before=self.currenthealth
        local result=pack(delta(self,amount,...))
        if before and self.currenthealth<before then commit(token.target,token.root) end
        return unpack(result,1,result.n)
    end
end
local function resolve(inst,root,fn,...)
    local health=inst.components and inst.components.health
    if not health then return fn(...) end
    wrap_health(health)
    local previous=health._nw_balance_token
    local token={target=inst,root=root}
    health._nw_balance_token=token
    local before=health.currenthealth
    local result=pack(pcall(fn,...))
    health._nw_balance_token=previous
    if not token.observed and before and health.currenthealth<before then commit(inst,root) end
    if not result[1] then error(result[2],0) end
    return unpack(result,2,result.n)
end
function M.wrap_combat(combat)
    if combat._nw_balance_wrapped then return end
    combat._nw_balance_wrapped=true
    local key=combat.GetAttacked_Internal and "GetAttacked_Internal" or "GetAttacked"
    local attacked=combat[key]
    combat[key]=function(self,attacker,damage,weapon,stimuli,spdamage,...)
        local pending=self._nw_balance_pending
        local root
        if pending and pending.attacker==attacker and pending.weapon==weapon then
            root=pending.root;self._nw_balance_pending=nil
        else root=weapon and weapon._nw_root or attacker and attacker._nw_root end
        local from=self.redirected_from
        local forwarded=from and from.components and from.components.combat
            and from.components.combat._nw_balance_forward
        if forwarded then
            root=forwarded.root
            damage=damage and damage/forwarded.factor
            if spdamage then
                local restored={}
                for k,v in pairs(spdamage) do restored[k]=type(v)=="number" and v/forwarded.factor or v end
                spdamage=restored
            end
        end
        if not root or not balanced() then return attacked(self,attacker,damage,weapon,stimuli,spdamage,...) end
        local factor=M.factor(self.inst,root)
        local scaled
        if spdamage then
            scaled={}
            for k,v in pairs(spdamage) do scaled[k]=type(v)=="number" and v*factor or v end
        end
        local previous=self._nw_balance_forward
        self._nw_balance_forward={root=root,factor=factor}
        local result=pack(pcall(resolve,self.inst,root,attacked,self,attacker,damage and damage*factor,weapon,stimuli,scaled,...))
        self._nw_balance_forward=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
end
function M.attack(p,owner,target,damage,weapon,stimuli,spdamage)
    local combat=target.components.combat
    local root=p and p._nw_root
    if not root or not balanced() then return combat:GetAttacked(owner,damage,weapon,stimuli,spdamage) end
    M.wrap_combat(combat)
    local previous=combat._nw_balance_pending
    combat._nw_balance_pending={root=root,attacker=owner,weapon=weapon}
    local result=pack(pcall(combat.GetAttacked,combat,owner,damage,weapon,stimuli,spdamage))
    combat._nw_balance_pending=previous
    if not result[1] then error(result[2],0) end
    return unpack(result,2,result.n)
end
function M.delta(p,target,amount,...)
    local h=target.components.health
    local root=p and p._nw_root
    if not root or not balanced() or amount>=0 then return h:DoDelta(amount,...) end
    return resolve(target,root,h.DoDelta,h,amount*M.factor(target,root),...)
end
function M.install(env)
    env.AddComponentPostInit("combat",function(combat)
        if TheWorld.ismastersim then M.wrap_combat(combat) end
    end)
end
return M
