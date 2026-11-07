-- Server-owned trail of the moving beam front. The existing projectile keeps
-- its payload reservation until the last damaging segment has faded.
local Path=require("nw/beam_path")
local Geometry=require("nw/geometry")
local Size=require("nw/projectile_size")
local Targeting=require("nw/targeting")
local Effects=require("nw/spell_effects")
local Fields=require("nw/expanded_fields")
local M={}

function M.is(p) return p and (p.base or p.id)=="end_beam" end

function M.start(inst,s)
    if not s.beam then s.beam={segments={},next_hit={},next_id=0,ended=false} end
    return s.beam
end

function M.publish(inst,s,now,force)
    if inst.PublishBeam then inst:PublishBeam(s.beam.segments,now,s.beam.ended,force) end
end

function M.record(s,x1,z1,x2,z2,now)
    local beam=s.beam
    if beam.ended or (x2-x1)^2+(z2-z1)^2<.00000001 then return end
    beam.next_id=beam.next_id+1
    local segment={id=beam.next_id,x1=x1,z1=z1,x2=x2,z2=z2,born=now,radius=Size.radius(s.p,s.age)}
    beam.segments[#beam.segments+1]=segment
    return segment
end

-- One clock for the entire beam: front, crossings, adjacent segments and
-- post-front residue can never multiply a target's half-second hit cadence.
function M.claim(s,target,now)
    if (s.beam.next_hit[target] or -math.huge)>now+.000001 then return false end
    s.beam.next_hit[target]=now+Path.interval
    s.hit=s.hit or {}
    s.hit[target]=(s.age or 0)+Path.interval -- Flight.seek uses projectile age.
    return true
end

function M.classify(s,target)
    if not target:IsValid() or target:IsInLimbo() or target==s.owner and s.ignore_self then return end
    local flags=s.p.flags or {}
    if target:HasTag("wall") and flags.phase_wall then return end
    local scope=flags.targets
    if Fields.can_break(target,s.owner) and (Targeting.breakable(target) or not scope or scope.building) then return "prop" end
    if flags.heal_ally and Effects.ally(s.owner,target)
        and not (s.group and s.group.healed and s.group.healed[target]) then return "ally" end
    if Targeting.selected_object(s.owner,target,flags) or Targeting.allowed(s.owner,target,flags) then return "target" end
end

function M.hit(inst,s,target,x,z,dx,dz,now,callback,kind)
    kind=kind or M.classify(s,target)
    if not kind or not M.claim(s,target,now) then return false end
    local olddx,olddz=s.dx,s.dz
    s.dx,s.dz=dx,dz
    callback(inst,s,target,x,z,kind)
    s.dx,s.dz=olddx,olddz
    return true
end

function M.stop(inst,s,x,z,now)
    if s.beam.ended then return false end
    s.beam.ended=true;s.beam.ended_at=now
    s.x,s.z=x,z
    if inst.StopBeamHead then inst:StopBeamHead() end
    if s.partner and s.partner:IsValid() and s.partner._shot and s.partner._shot.partner==inst then
        s.partner._shot.partner=nil
    end
    s.partner=nil
    inst.Physics:Stop()
    inst.Physics:SetMotorVel(0,0,0)
    inst.Physics:Teleport(x,0,z)
    return true
end

-- Called before the new front sweep, so old path contacts precede later path
-- contacts. Payloads may destroy a wall or the carrier during this traversal.
function M.step(inst,s,now,cache,query,hit)
    if not Effects.live(s.owner) then inst:Remove();return false end
    local beam=s.beam
    for index=#beam.segments,1,-1 do
        if now-beam.segments[index].born>=Path.lifetime-.000001 then table.remove(beam.segments,index) end
    end
    for target,deadline in pairs(beam.next_hit) do
        if deadline<=now or not target:IsValid() then
            beam.next_hit[target]=nil
            if s.hit then s.hit[target]=nil end
        end
    end
    local seen={}
    for _,segment in ipairs(beam.segments) do
        local radius=segment.radius*Path.width(now-segment.born)
        local contacts={}
        for _,target in ipairs(query(cache,segment.x1,segment.z1,segment.x2,segment.z2,s.p.flags.targets,radius)) do
            if target~=inst and not seen[target] and (beam.next_hit[target] or -math.huge)<=now+.000001 then
                local kind=M.classify(s,target)
                if kind then
                    local tx,_,tz=target.Transform:GetWorldPosition()
                    local t=Geometry.hit(segment.x1,segment.z1,segment.x2,segment.z2,tx,tz,
                        math.min(3,target:GetPhysicsRadius(.5))+radius)
                    if t then contacts[#contacts+1]={target=target,t=t,kind=kind};seen[target]=true end
                end
            end
        end
        table.sort(contacts,function(a,b) return a.t<b.t or a.t==b.t and a.target.GUID<b.target.GUID end)
        local dx,dz=segment.x2-segment.x1,segment.z2-segment.z1
        local length=math.sqrt(dx*dx+dz*dz)
        for _,contact in ipairs(contacts) do
            local target=contact.target
            -- Recheck after earlier collision payloads, which may remove or
            -- retarget an entity from this frame's cached candidate list.
            local kind=M.classify(s,target)
            if kind then
                M.hit(inst,s,target,segment.x1+dx*contact.t,segment.z1+dz*contact.t,
                    dx/length,dz/length,now,hit,kind)
            end
            if not inst:IsValid() then return false end
            if not Effects.live(s.owner) then inst:Remove();return false end
        end
    end
    if beam.ended and #beam.segments==0 then inst:Remove();return false end
    return true
end

return M
