local C=require("nw/constants/projectile_runtime").size
local M={}
function M.factor(p) return p and p.size_mult or 1 end
function M.radius(p,age)
    return ((p and p.hit_radius or C.hit_radius)+(p and p.id=="grow_orb" and C.grow_radius*math.min(C.grow_max_age,age or 0) or 0))*M.factor(p)
end
function M.visual(inst,scale)
    local old=inst._nw_size or 1
    if old==scale then return end
    local x,y,z=inst.Transform:GetScale()
    inst.Transform:SetScale(x*scale/old,y*scale/old,z*scale/old)
    inst._nw_size=scale
end
function M.native(inst,p)
    local scale=M.factor(p)
    M.visual(inst,scale)
    local cp=inst.components.projectile
    if cp and not inst._nw_hit_scaled then
        cp:SetHitDist(cp.hitdist*scale);inst._nw_hit_scaled=true
    end
end
function M.field(inst,p)
    local scale=M.factor(p)
    M.visual(inst,scale)
    if scale~=1 and not inst._nw_body_scaled then
        inst:SetPhysicsRadiusOverride(inst:GetPhysicsRadius(C.physics_radius)*scale)
        inst._nw_body_scaled=true
    end
end
return M
