local Effects=require("nw/spell_effects")
local M={}
function M.hit(s,target,x,z)
    require("nw/explosions").hit(s.owner,s.p,x,z)
    if s.p and s.p.event=="hit" and s.fire then
        local previous=s.hit_payload_fired
        s.hit_payload_fired=true
        local fired=s.fire(x,z,s.dx,s.dz,target)
        s.hit_payload_fired=previous or fired==true
    end
end
function M.timer(s,x,z,timers)
    local g=s.group
    if not s.fire or not g or not g.child then return end
    s.timer_done=true
    if not timers then s.fire(x,z,s.dx,s.dz);return end
    local old=timers[g]
    if not old or s.timer_rank<old.rank then
        timers[g]={fire=s.fire,x=x,z=z,dx=s.dx,dz=s.dz,rank=s.timer_rank}
    end
    g.timer_queued=true
end
function M.finish(s,x,z)
    if s.payload_finished then return end
    s.payload_finished=true
    if not s.p or not s.fire or not Effects.live(s.owner) then return end
    if s.p.event=="hit" then
        if not s.hit_payload_fired then s.fire(x,z,s.dx,s.dz) end
    elseif s.p.event=="timer" and not s.timer_done and not (s.group and s.group.timer_queued) then
        M.timer(s,x,z)
    end
end
return M
