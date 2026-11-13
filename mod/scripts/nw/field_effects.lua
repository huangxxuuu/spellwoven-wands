-- Shared field timing and emitted-projectile modifiers. Values compiled on the
-- field are already damage/size adjusted; do not apply those multipliers twice.
local Copy=require("nw/util").copy
local M={}
function M.time(p,seconds) return seconds*(p.field_lifetime_mult or 1) end
function M.shot(p,id,speed,lifetime)
    local m=p.child_modifiers or {}
    local shot={id=id,journal_id=p.journal_id or p.id,kind="projectile",damage=p.damage or 0,
        speed=math.max(2,math.min(60,speed*(m.speed_mult or 1)+(m.speed_add or 0))),
        lifetime=lifetime*(m.lifetime_mult or 1)*require("nw/projectile_size").factor(p),
        flags=Copy(p.flags or {}),spread=0,size_mult=p.size_mult,max_range=math.max(30,p.radius or 0),_nw_root=p._nw_root}
    for _,key in ipairs({"burn_damage","burn_ticks","freeze","planar","effect_scale"}) do shot[key]=p[key] end
    return shot
end
-- Stationary fields must also retain lighting and continuous effect modifiers.
-- This owns only their effects; the shared flight loop still owns all movement.
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
    local s={owner=caster,p=p,x=0,z=0,dx=1,dz=0,height=.6,travelled=0,
        context={side_left=4,side_groups=0,arcs={}}}
    inst._nw_effects=s
    inst:DoPeriodicTask(.15,function()
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
