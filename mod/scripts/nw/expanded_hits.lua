local Target=require("nw/targeting")
local Effects=require("nw/spell_effects")
local Geometry=require("nw/geometry")
local M={}
local Size=require("nw/projectile_size")

-- Sample the entire displacement, including the strip between the two ends.
function M.safe_move(e,dx,dz,distance)
    if not e.Physics or e:GetCurrentPlatform() then return end
    local x,_,z=e.Transform:GetWorldPosition()
    local nearby=Effects.scan(x,z,distance+2)
    for i=math.ceil(distance*4),1,-1 do
        local d=math.min(distance,i*.25)
        local tx,tz=x+dx*d,z+dz*d
        if TheWorld.Map:IsAboveGroundAtPoint(tx,0,tz) and not TheWorld.Map:IsGroundTargetBlocked(Vector3(tx,0,tz))
            and Effects.clear(x,z,tx,tz,nearby,nil,true) then
            e.Physics:Teleport(tx,0,tz)
            return
        end
    end
end

function M.electric(owner,e,x,z,damage,p,base_only,source_height,source_visual_lift)
    if Target.breakable(e) then e._nw_break(owner);return end
    local tx,_,tz=e.Transform:GetWorldPosition()
    source_height=source_height or .65
    local target_height=require("nw/electric_visual").target_height(e)
    local fx=Effects.fx("nw_arc_fx",x,z,source_height)
    if fx then
        fx:SetSpan(tx-x,tz-z,e,target_height-source_height,source_visual_lift)
        fx.components.weapon:SetDamage(damage)
        local before=e.components.health and e.components.health.currenthealth or 0
        if e:HasTag("player") and p and p.flags.targets then e.components.combat:GetAttacked(owner,damage,fx,"electric")
        else owner.components.combat:DoAttack(e,fx,fx,nil,nil,math.sqrt((tx-x)^2+(tz-z)^2)+1,e:GetPosition()) end
        if p and base_only then
            require("nw/journal_damage").loss(owner,p,e.components.health,before)
        end
        if p and not base_only and e:IsValid() and e.components.health then
            Effects.native_hit(owner,e,p,math.max(0,before-math.max(0,e.components.health.currenthealth)),tx-x,tz-z)
            local status=require("nw/util").copy(p);status.damage=0
            M.impact({owner=owner,p=status,age=0,dx=tx-x,dz=tz-z},e,tx,tz)
            require("nw/explosions").hit(owner,p,tx,tz)
        end
    end
end

local function mark(e)
    if e._nw_melee_timeout then e._nw_melee_timeout:Cancel() end
    local function clear()
        e._nw_melee_timeout=nil
        e:RemoveEventCallback("attacked",e._nw_melee_listener)
        e._nw_melee_listener=nil
    end
    if not e._nw_melee_listener then
        e._nw_melee_listener=function(_,hit)
            local a,w=hit.attacker,hit.weapon
            if not (hit.from_doattack and a and a:HasTag("player") and (hit.damageresolved or 0)>0)
                or hit.stimuli=="electric" or (w and (w:HasTag("projectile") or
                (w.components.weapon and w.components.weapon.projectile))) then return end
            e._nw_melee_timeout:Cancel();clear()
            if not e.components.health:IsDead() then
                e.components.health:DoDelta(-hit.damageresolved*.2,nil,"nw_melee_mark",nil,a)
            end
        end
        e:ListenForEvent("attacked",e._nw_melee_listener)
    end
    e._nw_melee_timeout=e:DoTaskInTime(2,clear)
end

function M.consume_melee(e)
    if not e._nw_melee_timeout then return 1 end
    e._nw_melee_timeout:Cancel();e._nw_melee_timeout=nil
    e:RemoveEventCallback("attacked",e._nw_melee_listener);e._nw_melee_listener=nil
    return 1.2
end

function M.impact(s,e,ix,iz)
    local p,f=s.p,s.p.flags
    local hit={damage=p.damage,flags=f,freeze=p.freeze,burn_damage=p.burn_damage,burn_ticks=p.burn_ticks,journal_id=p.journal_id or p.id}
    if p.id=="grow_orb" then hit.damage=hit.damage*(1+14/12*math.min(s.age,1)) end
    local boomerang=p.engraving=="voidcloth_boomerang" and s.native
    if boomerang and not f.harmless then
        hit.damage=hit.damage+(boomerang.components.weapon.damage-5)*p.growth_mult*(p.effect_scale or 1)
    end
    local crit=f.crit and math.random()<.15 and 1.5 or 1
    hit.damage=hit.damage*crit
    if not f.harmless and f.chill_touch then hit.freeze=(hit.freeze or 0)+(f.chill_touch.cold or .2) end
    if boomerang and e.components.health and e.components.combat then
        local factor=boomerang.components.damagetypebonus:GetBonus(e)*Effects.wet_mult(e,f)
        local planar=boomerang.components.planardamage:GetBaseDamage()*(p.planar or 0)/5
        local health=e.components.health
        local before=health.currenthealth
        e.components.combat:GetAttacked(s.owner,hit.damage*factor,boomerang,nil,{planar=planar*factor*crit})
        Effects.native_hit(s.owner,e,p,math.max(0,before-math.max(0,health.currenthealth)),s.dx,s.dz)
        Effects.fx("voidcloth_boomerang_impact_fx",ix,iz)
        if hit.freeze and e:IsValid() then Effects.direct(s.owner,e,{damage=0,freeze=hit.freeze,flags=f},s.dx,s.dz) end
    elseif p.id=="tri_electric" then
        if hit.damage>0 and e.components.combat then M.electric(s.owner,e,ix,iz,hit.damage*Effects.wet_mult(e,f),p,true) end
        if hit.freeze then Effects.direct(s.owner,e,{damage=0,freeze=hit.freeze,flags=f},s.dx,s.dz) end
    elseif hit.damage>0 or hit.freeze then Effects.direct(s.owner,e,hit,s.dx,s.dz) end
    if not e:IsValid() or not e.components.health or e.components.health:IsDead() then return end
    if f.melee_mark then mark(e) end
    if p.id=="slime" and not p.secondary and e.components.locomotor and not e:HasTag("epic") then
        local locomotor=e.components.locomotor
        locomotor:SetExternalSpeedMultiplier(e,"nw_slime",.75)
        if e._nw_slime then e._nw_slime:Cancel() end
        e._nw_slime=e:DoTaskInTime(1.5,function()
            locomotor:RemoveExternalSpeedMultiplier(e,"nw_slime");e._nw_slime=nil
        end)
    elseif require("nw/arsenal").notes[p.id] and p.id~="note_c" and not p.secondary then
        e._nw_note_until=GetTime()+2
        local fx=Effects.fx("nw_note_mark",ix,iz,.8)
        if fx then fx.entity:SetParent(e.entity);fx.Transform:SetPosition(0,1,0) end
    elseif p.id=="note_c" and (e._nw_note_until or 0)>GetTime() then
        e._nw_note_until=nil
        Target.damage(s.owner,e,8*(p.effect_scale or 1),p.flags,p)
    end
end

function M.finish(s,x,z)
    local p=s.p
    if p.end_damage then Effects.blast(s.owner,x,z,{damage=p.end_damage,radius=1.5*Size.factor(p),flags=p.flags,quiet_burst=(p.base or p.id)=="end_beam",journal_id=p.journal_id or p.id}) end
    if p.id=="land_hook" then
        local ox,_,oz=s.owner.Transform:GetWorldPosition()
        local dx,dz=x-ox,z-oz
        local l=math.sqrt(dx*dx+dz*dz)
        if l>.25 then M.safe_move(s.owner,dx/l,dz/l,math.min(4,l-.2)) end
    end
end

local function side_shot(s,angle)
    local co,si=math.cos(angle),math.sin(angle)
    local p={id="fire",journal_id=s.p.journal_id or s.p.id,kind="projectile",speed=12,lifetime=.55,damage=4*(s.p.effect_scale or 1),spread=0,flags={targets=s.p.flags.targets},size_mult=s.p.size_mult}
    return require("nw/executor").execute({next_state={rng_state=1},root_block=1,
        projectile_count=1,blocks={{projectiles={p}}}},s.owner,s.x,s.z,s.dx*co-s.dz*si,s.dx*si+s.dz*co,s.height)
end
function M.step(s,now)
    local f,ctx=s.p.flags,s.context
    if f.side_embers and ctx and ctx.side_left>=2 and (ctx.side_groups or 0)<2 and (s.side_count or 0)<2 and s.travelled>=3*(1+(s.side_count or 0)) then
        s.side_count=(s.side_count or 0)+1
        ctx.side_left=ctx.side_left-2;ctx.side_groups=(ctx.side_groups or 0)+1
        side_shot(s,math.pi/2);side_shot(s,-math.pi/2)
    end
    if not (f.halo or s.partner) or (s.fx_next or 0)>now then return end
    s.fx_next=now+.15
    if f.halo then
        if not s.halo_hits then s.halo_hits={} end
        local radius=.8*Size.factor(s.p)
        for _,e in ipairs(Effects.scan(s.x,s.z,radius,f)) do
            if Target.hittable(s.owner,e,f) and e:GetDistanceSqToPoint(s.x,0,s.z)<=radius*radius and (s.halo_hits[e] or 0)<=now then
                s.halo_hits[e]=now+.5;Target.damage(s.owner,e,3*(s.p.effect_scale or 1),f,s.p)
            end
        end
    end
    local partner=s.partner
    if partner and partner:IsValid() then
        local x,_,z=partner.Transform:GetWorldPosition()
        local dx,dz=x-s.x,z-s.z
        if dx*dx+dz*dz<=9 then
            local fx=Effects.fx("nw_arc_fx",s.x,s.z,s.height)
            if fx then fx:SetSpan(dx,dz) end
            for _,e in ipairs(Effects.scan((x+s.x)/2,(z+s.z)/2,2.5,f)) do
                if Target.hittable(s.owner,e,f) and (ctx.arcs[e] or 0)<=now then
                    local tx,_,tz=e.Transform:GetWorldPosition()
                    if Geometry.hit(s.x,s.z,x,z,tx,tz,e:GetPhysicsRadius(.5)+.15) then
                        ctx.arcs[e]=now+.5;M.electric(s.owner,e,s.x,s.z,4*(s.p.effect_scale or 1)*Effects.wet_mult(e,f),s.p,true)
                    end
                end
            end
        end
    end
end
return M
