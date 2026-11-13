local Geometry=require("nw/geometry")
local M={}
local function source(e)
    local c=e.components
    local p=c.projectile or c.complexprojectile
    local owner=e._shot and e._shot.owner or p and (p.owner or p.attacker)
        or e.owner or e.attacker or e._nw_owner
    if owner and owner.components.inventoryitem then owner=owner.components.inventoryitem.owner or owner end
    return owner,p
end
function M.accepts(e,owner)
    if not e:IsValid() or e==owner or e._nw_intercepted then return false end
    -- A directed native visual and its swept controller are one projectile.
    if e._nw_controller and e._nw_controller:IsValid() then return false end
    local actor,p=source(e)
    if not (p or e._shot or e:HasTag("projectile") or e:HasTag("activeprojectile")) then return false end
    if not e._shot and p and not actor and not e:HasTag("projectile") and not e:HasTag("activeprojectile") then return false end
    if p and p.IsThrown and not p:IsThrown() then return false end
    if actor==owner then return false end
    if actor and actor.components.follower and actor.components.follower.leader==owner then return false end
    return true
end
function M.consume(ring,e)
    if not ring:IsValid() or ring._nw_guard_left<=0 then return false end
    ring._nw_guard_left=ring._nw_guard_left-1
    e._nw_intercepted=true
    -- Raw removal only: never invoke Hit, Miss, Detonate, or carrier completion.
    -- Our projectile onremove handler still releases its reservations/visuals.
    e:Remove()
    require("nw/field_stages").guard(ring,ring._nw_guard_left)
    if ring._nw_guard_left==0 then ring:Remove()
    end
    return true
end
function M.intercept(e,x,z,nx,nz,target)
    for ring in pairs(TheWorld._nw_guards or {}) do
        local owner=ring._nw_guard_owner
        if ring:IsValid() and owner and owner:IsValid() and M.accepts(e,owner) then
            local ox,_,oz=owner.Transform:GetWorldPosition()
            local radius=ring._nw_guard_radius
            local contact=(not target or target==owner) and Geometry.hit(x,z,nx,nz,ox,oz,radius)
            if contact then
                return M.consume(ring,e),contact
            end
        end
    end
    return false
end
function M.start(inst,owner,p)
    TheWorld._nw_guards=TheWorld._nw_guards or {}
    TheWorld._nw_guards[inst]=true
    inst._nw_guard_owner=owner;inst._nw_guard_radius=p.radius
    inst._nw_guard_left=2
    inst:ListenForEvent("onremove",function() TheWorld._nw_guards[inst]=nil end)
    inst:DoPeriodicTask(FRAMES,function()
        if not owner:IsValid() then inst:Remove();return end
        local x,_,z=owner.Transform:GetWorldPosition()
        for _,e in ipairs(TheSim:FindEntities(x,0,z,p.radius+3,nil,{"INLIMBO","DECOR"})) do
            if M.accepts(e,owner) then
                local ex,_,ez=e.Transform:GetWorldPosition()
                local vx,vy,vz=0,0,0
                if e.Physics then vx,vy,vz=e.Physics:GetVelocity() end
                if (ex-x)^2+(ez-z)^2<=p.radius^2 or (ex-x)*vx+(ez-z)*vz<0 then
                    if Geometry.hit(ex,ez,ex+vx*FRAMES,ez+vz*FRAMES,x,z,p.radius) then
                        M.consume(inst,e)
                        if not inst:IsValid() then return end
                    end
                end
            end
        end
    end,0)
end
function M.install(env)
    for _,component in ipairs({"projectile","complexprojectile"}) do
        env.AddComponentPostInit(component,function(c)
            local hit=c.Hit
            if not hit then return end
            c.Hit=function(self,target,...)
                local x,_,z=self.inst.Transform:GetWorldPosition()
                if M.intercept(self.inst,x,z,x,z,target) then return end
                return hit(self,target,...)
            end
        end)
    end
end
return M
