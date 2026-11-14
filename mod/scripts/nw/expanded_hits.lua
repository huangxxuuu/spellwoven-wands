local C=require("nw/constants/combat")
local Projectile=require("nw/constants/projectiles")
local Modifier=require("nw/constants/modifiers")
local Audio=require("nw/constants/audio").timing
local Target=require("nw/targeting")
local Effects=require("nw/spell_effects")
local Geometry=require("nw/geometry")
local M={}
local Size=require("nw/projectile_size")
local Damage=require("nw/balance_damage")

function M.safe_move(e,dx,dz,distance)
    if not e.Physics or e:GetCurrentPlatform() then return end
    local x,_,z=e.Transform:GetWorldPosition()
    local nearby=Effects.scan(x,z,distance+C.safe_move.query_padding)
    for i=math.ceil(distance*C.safe_move.steps_per_unit),1,-1 do
        local d=math.min(distance,i*C.safe_move.step)
        local tx,tz=x+dx*d,z+dz*d
        if TheWorld.Map:IsAboveGroundAtPoint(tx,0,tz) and not TheWorld.Map:IsGroundTargetBlocked(Vector3(tx,0,tz))
            and Effects.clear(x,z,tx,tz,nearby,nil,true) then
            e.Physics:Teleport(tx,0,tz)
            return
        end
    end
end

function M.electric(owner,e,x,z,damage,p,base_only,source_height,source_visual_lift)
    if Target.selectable_prop(owner,e,p and p.flags) then e._nw_break(owner);return end
    if not Target.selected(owner,e,p and p.flags) then return end
    local tx,_,tz=e.Transform:GetWorldPosition()
    source_height=source_height or C.electric.source_height
    local target_height=require("nw/electric_visual").target_height(e)
    local fx=Effects.fx("nw_arc_fx",x,z,source_height)
    if fx then
        Damage.tag(fx,p)
        fx:SetSpan(tx-x,tz-z,e,target_height-source_height,source_visual_lift)
        local loss=Effects.electric_attack(owner,e,p or {flags={}},damage,fx,
            {range=math.sqrt((tx-x)^2+(tz-z)^2)+C.electric.range_padding,source=e.GetPosition and e:GetPosition()})
        if p and base_only then
            require("nw/journal_damage").record(owner,p,loss)
        end
        if p and not base_only and e:IsValid() then
            Effects.native_hit(owner,e,p,loss,tx-x,tz-z)
            local status=require("nw/util").copy(p);status.damage=0
            M.impact({owner=owner,p=status,age=0,dx=tx-x,dz=tz-z},e,tx,tz)
            require("nw/explosions").hit(owner,p,tx,tz)
        end
    end
end

local function mark(e,p)
    e._nw_melee_root=p and p._nw_root
    if e._nw_melee_timeout then e._nw_melee_timeout:Cancel() end
    local function clear()
        e._nw_melee_timeout=nil
        e:RemoveEventCallback("attacked",e._nw_melee_listener)
        e._nw_melee_listener=nil
        e._nw_melee_root=nil
    end
    if not e._nw_melee_listener then
        e._nw_melee_listener=function(_,hit)
            local a,w=hit.attacker,hit.weapon
            if not (hit.from_doattack and a and a:HasTag("player") and (hit.damageresolved or 0)>0)
                or hit.stimuli=="electric" or (w and (w:HasTag("projectile") or
                (w.components.weapon and w.components.weapon.projectile))) then return end
            local root=e._nw_melee_root
            e._nw_melee_timeout:Cancel();clear()
            if not e.components.health:IsDead() then
                Damage.delta({_nw_root=root},e,-hit.damageresolved*Modifier.effects.melee_mark.bonus,nil,"nw_melee_mark",nil,a)
            end
        end
        e:ListenForEvent("attacked",e._nw_melee_listener)
    end
    e._nw_melee_timeout=e:DoTaskInTime(Modifier.effects.melee_mark.duration,clear)
end

function M.consume_melee(e)
    if not e._nw_melee_timeout then return 1 end
    e._nw_melee_timeout:Cancel();e._nw_melee_timeout=nil
    e:RemoveEventCallback("attacked",e._nw_melee_listener);e._nw_melee_listener=nil
    e._nw_melee_root=nil
    return Modifier.effects.melee_mark.multiplier
end

function M.impact(s,e,ix,iz)
    local p,f=s.p,s.p.flags
    local hit={damage=p.damage,flags=f,freeze=p.freeze,burn_damage=p.burn_damage,burn_ticks=p.burn_ticks,journal_id=p.journal_id or p.id,_nw_root=p._nw_root}
    if p.id=="grow_orb" then hit.damage=hit.damage*(1+Projectile.effects.grow_orb.growth_damage/Projectile.effects.grow_orb.growth_base*math.min(s.age,Projectile.effects.grow_orb.growth_duration)) end
    local boomerang=p.engraving=="voidcloth_boomerang" and s.native
    if boomerang and not f.harmless then
        hit.damage=hit.damage+(boomerang.components.weapon.damage-Projectile.engraved.voidcloth_boomerang.damage)*(p.base_damage_multiplier or 1)*p.growth_mult*(p.effect_scale or 1)
    end
    local crit=f.crit and math.random()<Modifier.effects.crit.chance and Modifier.effects.crit.multiplier or 1
    hit.damage=hit.damage*crit
    if not f.harmless and f.chill_touch then hit.freeze=(hit.freeze or 0)+(f.chill_touch.cold or Modifier.rules.chill_increment) end
    if boomerang and e.components.health and e.components.combat then
        local factor=boomerang.components.damagetypebonus:GetBonus(e)*Effects.wet_mult(e,f)
        local planar=boomerang.components.planardamage:GetBaseDamage()*(p.planar or 0)/Projectile.engraved_special.boomerang_planar
        local health=e.components.health
        local before=health.currenthealth
        Damage.attack(p,s.owner,e,hit.damage*factor,boomerang,nil,{planar=planar*factor*crit})
        Effects.native_hit(s.owner,e,p,math.max(0,before-math.max(0,health.currenthealth)),s.dx,s.dz)
        Effects.fx("voidcloth_boomerang_impact_fx",ix,iz)
        if hit.freeze and e:IsValid() then Effects.direct(s.owner,e,{damage=0,freeze=hit.freeze,flags=f},s.dx,s.dz) end
    elseif p.id=="tri_electric" then
        if hit.damage>0 then M.electric(s.owner,e,ix,iz,hit.damage*Effects.wet_mult(e,f),p,true) end
        if hit.freeze then Effects.direct(s.owner,e,{damage=0,freeze=hit.freeze,flags=f},s.dx,s.dz) end
    elseif hit.damage>0 or hit.freeze then Effects.direct(s.owner,e,hit,s.dx,s.dz) end
    if not e:IsValid() or e.components.health and e.components.health:IsDead() then return end
    if f.melee_mark and e.components.health then mark(e,p) end
    if p.id=="slime" and not p.secondary and e.components.locomotor and not e:HasTag("epic") then
        local locomotor=e.components.locomotor
        locomotor:SetExternalSpeedMultiplier(e,"nw_slime",Projectile.effects.slime.speed_multiplier)
        if e._nw_slime then e._nw_slime:Cancel() end
        e._nw_slime=e:DoTaskInTime(Projectile.effects.slime.duration,function()
            locomotor:RemoveExternalSpeedMultiplier(e,"nw_slime");e._nw_slime=nil
        end)
    elseif require("nw/arsenal").notes[p.id] and p.id~="note_c" and not p.secondary then
        e._nw_note_until=GetTime()+Audio.mark_duration
        local fx=Effects.fx("nw_note_mark",ix,iz,Audio.mark_height)
        if fx then fx.entity:SetParent(e.entity);fx.Transform:SetPosition(0,Audio.mark_parent_height,0) end
    elseif p.id=="note_c" and (e._nw_note_until or 0)>GetTime() then
        e._nw_note_until=nil
        Target.damage(s.owner,e,(p.echo_damage or Projectile.cards.note_c.echo_damage)*(p.effect_scale or 1),p.flags,p)
    end
end

function M.finish(s,x,z)
    local p=s.p
    if p.end_damage then Effects.blast(s.owner,x,z,{damage=p.end_damage,radius=Projectile.effects.end_beam.end_radius*Size.factor(p),flags=p.flags,quiet_burst=(p.base or p.id)=="end_beam",journal_id=p.journal_id or p.id,_nw_root=p._nw_root}) end
    if p.id=="land_hook" then
        local ox,_,oz=s.owner.Transform:GetWorldPosition()
        local dx,dz=x-ox,z-oz
        local l=math.sqrt(dx*dx+dz*dz)
        if l>Projectile.effects.land_hook.min_distance then M.safe_move(s.owner,dx/l,dz/l,math.min(Projectile.effects.land_hook.max_distance,l-Projectile.effects.land_hook.stop_margin)) end
    end
end

local function side_shot(s,angle)
    local co,si=math.cos(angle),math.sin(angle)
    local modifier=s.p.flags.side_embers
    local damage=type(modifier)=="table" and modifier.effect_damage or Modifier.cards.side_embers.effect_damage
    local p={id="fire",journal_id=s.p.journal_id or s.p.id,kind="projectile",speed=Modifier.effects.side_embers.speed,lifetime=Modifier.effects.side_embers.lifetime,damage=damage*(s.p.effect_scale or 1),spread=0,flags={targets=s.p.flags.targets},size_mult=s.p.size_mult}
    return require("nw/executor").execute({next_state={rng_state=1},root_block=1,
        projectile_count=1,blocks={{projectiles={p}}}},s.owner,s.x,s.z,s.dx*co-s.dz*si,s.dx*si+s.dz*co,s.height,nil,s.p._nw_root)
end
function M.step(s,now)
    local f,ctx=s.p.flags,s.context
    if f.side_embers and ctx and ctx.side_left>=Modifier.effects.side_embers.group_size and (ctx.side_groups or 0)<Modifier.effects.side_embers.max_groups and (s.side_count or 0)<Modifier.effects.side_embers.max_groups and s.travelled>=Modifier.effects.side_embers.distance_interval*(1+(s.side_count or 0)) then
        s.side_count=(s.side_count or 0)+1
        ctx.side_left=ctx.side_left-Modifier.effects.side_embers.group_size;ctx.side_groups=(ctx.side_groups or 0)+1
        side_shot(s,math.pi/2);side_shot(s,-math.pi/2)
    end
    if not (f.halo or s.partner) or (s.fx_next or 0)>now then return end
    s.fx_next=now+Modifier.effects.effect_interval
    if f.halo then
        if not s.halo_hits then s.halo_hits={} end
        local radius=Modifier.effects.halo.radius*Size.factor(s.p)
        for _,e in ipairs(Target.query(s.owner,s.x,s.z,radius,f,{breakables=true})) do
            if (s.halo_hits[e] or 0)<=now then
                local damage=type(f.halo)=="table" and f.halo.effect_damage or Modifier.cards.searing_halo.effect_damage
                s.halo_hits[e]=now+Modifier.effects.halo.interval;Target.damage(s.owner,e,damage*(s.p.effect_scale or 1),f,s.p)
            end
        end
    end
    local partner=s.partner
    if partner and partner:IsValid() then
        local x,_,z=partner.Transform:GetWorldPosition()
        local dx,dz=x-s.x,z-s.z
        if dx*dx+dz*dz<=Modifier.effects.twin_arc.max_distance^2 then
            local fx=Effects.fx("nw_arc_fx",s.x,s.z,s.height)
            if fx then fx:SetSpan(dx,dz) end
            for _,e in ipairs(Effects.scan((x+s.x)/2,(z+s.z)/2,Modifier.effects.twin_arc.scan_radius,f)) do
                if Target.accepts(s.owner,e,f,{breakables=true}) and (ctx.arcs[e] or 0)<=now then
                    local tx,_,tz=e.Transform:GetWorldPosition()
                    if Geometry.hit(s.x,s.z,x,z,tx,tz,e:GetPhysicsRadius(C.collision_radius)+Modifier.effects.twin_arc.hit_padding) then
                        local damage=type(f.twin_arc)=="table" and f.twin_arc.effect_damage or Modifier.cards.twin_arc.effect_damage
                        ctx.arcs[e]=now+Modifier.effects.twin_arc.interval;M.electric(s.owner,e,s.x,s.z,damage*(s.p.effect_scale or 1)*Effects.wet_mult(e,f),s.p,true)
                    end
                end
            end
        end
    end
end
return M
