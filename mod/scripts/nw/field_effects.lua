local Caps=require("nw/constants/limits")
local C=require("nw/constants/field_runtime")
local Copy=require("nw/util").copy
local Limits=require("nw/spell_limits")
local M={}
function M.water(water,owner,p,x,z)
    if not (p.flags and p.flags.targets) then water:SpreadProtectionAtPoint(x,0,z,p.radius);return end
    local Target=require("nw/targeting")
    for _,e in ipairs(TheSim:FindEntities(x,0,z,p.radius,nil,water.ignoretags)) do
        if Target.accepts(owner,e,p.flags,{default=true}) then water:ApplyProtectionToEntity(e) end
    end
    local farm=TheWorld.components and TheWorld.components.farming_manager
    if farm and water.addwetness and Target.allows_category(p.flags,"nature") then
        farm:AddSoilMoistureAtPoint(x,0,z,water.addwetness)
    end
    if water.onspreadprotectionfn then water.onspreadprotectionfn(water.inst,x,0,z) end
end
function M.time(p,seconds) return seconds*(p.field_lifetime_mult or 1) end
function M.shot(p,id,speed,lifetime)
    local m=p.child_modifiers or {}
    local shot={id=id,journal_id=p.journal_id or p.id,kind="projectile",damage=p.damage or 0,
        speed=math.max(Caps.min_speed,math.min(Limits.max_speed,speed*(m.speed_mult or 1)+(m.speed_add or 0))),
        lifetime=lifetime*(m.lifetime_mult or 1)*require("nw/projectile_size").factor(p),
        flags=Copy(p.flags or {}),spread=0,size_mult=p.size_mult,max_range=math.max(C.shot.min_range,p.radius or 0),_nw_root=p._nw_root}
    for _,key in ipairs({"burn_damage","burn_ticks","freeze","planar","effect_scale"}) do shot[key]=p[key] end
    return shot
end
function M.attach(inst,caster,p,resolve)
    if inst._nw_field_effects_attached then return end
    inst._nw_field_effects_attached=true
    local f=p.flags or {}
    require("nw/dark_fog").attach(inst,caster,p)
    if f.light then
        local glow=SpawnPrefab("nw_flyinglight")
        glow.entity:SetParent(inst.entity)
        inst:ListenForEvent("onremove",function() if glow:IsValid() then glow:Remove() end end)
    end
    if not (f.halo or f.twin_arc or f.side_embers) then return end
    local s={owner=caster,p=p,x=0,z=0,dx=1,dz=0,height=C.attached.height,travelled=0,
        context={side_left=C.attached.side_left,side_groups=0,arcs={}}}
    inst._nw_effects=s
    inst:DoPeriodicTask(C.attached.interval,function()
        if inst._nw_stored and inst:IsAsleep() then return end
        if resolve then s.owner=resolve() else s.owner=caster end
        if not s.owner or not s.owner:IsValid() then return end
        local x,_,z=inst.Transform:GetWorldPosition();s.x,s.z=x,z
        local motion=inst._nw_motion
        if motion then s.dx,s.dz,s.travelled=motion.dx,motion.dz,motion.travelled end
        require("nw/expanded_hits").step(s,GetTime())
    end,0)
end
return M
