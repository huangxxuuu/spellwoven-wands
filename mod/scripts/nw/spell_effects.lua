local C=require("nw/constants/combat")
local Modifier=require("nw/constants/modifiers")
local Fire=require("nw/constants/projectiles").effects.fire
local Instant=require("nw/constants/instant")
local Chain=Instant.chain
local Target=require("nw/targeting")
local Geometry=require("nw/geometry")
local Damage=require("nw/balance_damage")
local M={}
local Perf=require("nw/perf")
function M.live(owner)
    return owner and owner:IsValid() and (not owner.components.health or not owner.components.health:IsDead())
end
function M.near(x,z,r,objects)
    return TheSim:FindEntities(x,0,z,r,nil,Target.scan_exclude,Target.scan_tags(nil,objects))
end
function M.scan(x,z,r,flags,force_objects)
    local now=GetTime()
    local cache=TheWorld._nw_scans
    if not cache or cache.time~=now then cache={time=now};TheWorld._nw_scans=cache end
    local cx,cz=math.floor(x/C.query_cell_size),math.floor(z/C.query_cell_size)
    local pad=math.ceil(r)
    local tags=Target.scan_tags(flags,force_objects)
    local kind=flags and (flags.targets or flags._nw_target_bypass) and ":selected"
        or force_objects and ":objects" or ""
    local key=cx..":"..cz..":"..pad..kind
    if not cache[key] then
        cache[key]=TheSim:FindEntities(cx*C.query_cell_size+C.query_cell_size/2,0,cz*C.query_cell_size+C.query_cell_size/2,pad+math.sqrt(2*(C.query_cell_size/2)^2),nil,Target.scan_exclude,tags)
        if Perf.sample then Perf.sample.effect_queries=Perf.sample.effect_queries+1 end
    end
    return cache[key]
end
local function arc_target(owner,x,z,r,seen,aim_x,aim_z,flags)
    local best,best_side,best_dist=nil,2,math.huge
    for _,e in ipairs(M.scan(x,z,r,flags)) do
        if not seen[e] and Target.accepts(owner,e,flags,{breakables=true}) then
            local ex,_,ez=e.Transform:GetWorldPosition()
            local dx,dz=ex-x,ez-z
            local distance=dx*dx+dz*dz
            local side=aim_x and dx*aim_x+dz*aim_z<0 and 1 or 0
            if distance<=r*r and (side<best_side or side==best_side and
                (distance<best_dist or distance==best_dist and e.GUID<best.GUID)) then
                best,best_side,best_dist=e,side,distance
            end
        end
    end
    return best
end
function M.ally(owner,e,flags)
    if not Target.accepts(owner,e,flags,{default=true,components={"health"}}) then return false end
    local h=e.components.health
    if not h or h:IsDead() or h.currenthealth>=h:GetMaxWithPenalty() then return false end
    if flags and flags.targets then return true end
    if owner==e then return false end
    local f=e.components.follower
    return e:HasTag("player") or (f and f.leader and f.leader:HasTag("player"))
end
function M.fx(name,x,z,height)
    local fx=SpawnPrefab(name)
    if fx then
        fx.Transform:SetPosition(x,height or 0,z)
    end
    return fx
end
local function leech(owner,flags,loss)
    if flags.leech and loss>0 and M.live(owner) and owner.components.health then
        owner.components.health:DoDelta(loss*flags.leech.fraction,false,"nw_leech")
    end
end
function M.wet_mult(e,flags)
    return flags.wet_weak and (e:GetIsWet() or e:GetWetMultiplier()>0) and (flags.wet_weak.mult or Modifier.rules.wet_multiplier) or 1
end
local function valid_hit(owner,e,flags)
    return Target.selected(owner,e,flags)
end
local function deal(owner,e,n,flags,element,p)
    if not valid_hit(owner,e,flags) then return 0 end
    local h=e.components.health
    if not h then return 0 end
    n=n*M.wet_mult(e,flags)
    if element=="fire" then
        if e:HasTag("fireimmune") then return 0 end
        n=n*h:GetFireDamageScale()
    end
    if n<=0 then return 0 end
    local before=h.currenthealth
    if e.components.combat then Damage.attack(p,owner,e,n,nil,element)
    else Damage.delta(p,e,-n,nil,element or "nw_spell",nil,owner) end
    local loss=math.max(0,before-math.max(0,h.currenthealth))
    require("nw/journal_damage").record(owner,p,loss)
    leech(owner,flags,loss)
    return loss
end
local function clear_burn(e)
    local b=e._nw_burn
    if b then
        if b.task then b.task:Cancel() end
        e:RemoveEventCallback("onextinguish",clear_burn)
        e:RemoveEventCallback("death",clear_burn)
        e._nw_burn=nil
    end
end
local function burn_tick(e)
    local b=e._nw_burn
    if not b then return end
    b.task=nil
    local now=GetTime()
    local due=math.huge
    for i=#b,1,-1 do
        local stack=b[i]
        while stack.left>0 and stack.next<=now+Fire.burn_time_epsilon and M.live(stack.owner) and Target.valid(e) do
            stack.left=stack.left-1;stack.next=stack.next+Fire.burn_interval
            deal(stack.owner,e,stack.damage,stack.flags,"fire",stack)
            if e._nw_burn~=b then return end
        end
        if stack.left==0 or not M.live(stack.owner) or not Target.valid(e) then table.remove(b,i)
        else due=math.min(due,stack.next) end
    end
    if #b==0 then clear_burn(e) else b.task=e:DoTaskInTime(math.max(FRAMES,due-now),burn_tick) end
end
function M.evaporate(e,damage)
    local moisture=e.components.moisture
    if moisture and moisture:GetMoisture()>0 then
        moisture:DoDelta(-damage/Fire.evaporation_divisor)
        local x,_,z=e.Transform:GetWorldPosition()
        M.fx("wx78_heat_steam",x,z,Fire.steam_height)
        return moisture:GetMoisture()>0
    end
    return false
end
local function burn(owner,e,p)
    if e:HasTag("fireimmune") or e.components.health and e.components.health:GetFireDamageScale()<=0 then return end
    if not e.components.health then
        if e.components.burnable and not e.components.burnable:IsBurning() then e.components.burnable:Ignite(true,owner) end
        return
    end
    local b=e._nw_burn
    if not b then
        b={};e._nw_burn=b
        e:ListenForEvent("onextinguish",clear_burn);e:ListenForEvent("death",clear_burn)
        b.task=e:DoTaskInTime(Fire.burn_interval,burn_tick)
    end
    b[#b+1]={owner=owner,flags=Target.flags(p,"aftermath"),damage=p.burn_damage,left=p.burn_ticks,next=GetTime()+Fire.burn_interval,journal_id=p.journal_id or p.id,_nw_root=p._nw_root}
    local ice=e.components.freezable
    if ice and ice:IsFrozen() then ice:Unfreeze()
    elseif e.components.burnable and not e.components.burnable:IsBurning() then
        e.components.burnable:Ignite(true,owner)
    end
end
function M.clear(x,z,tx,tz,walls,ignore,land_only)
    local dx,dz=tx-x,tz-z
    local steps=math.max(1,math.ceil(math.sqrt(dx*dx+dz*dz)/C.clear_step))
    for i=1,steps do
        if not TheWorld.Map:IsPassableAtPoint(x+dx*i/steps,0,z+dz*i/steps,not land_only) then return false end
    end
    for _,e in ipairs(walls) do
        if e~=ignore and e:IsValid() and e:HasTag("wall") and e.components.health and not e.components.health:IsDead() then
            local wx,_,wz=e.Transform:GetWorldPosition()
            if Geometry.hit(x,z,tx,tz,wx,wz,e:GetPhysicsRadius(C.collision_radius)) then return false end
        end
    end
    return true
end
local function knock(e,dx,dz,k)
    if not e.sg or not e.sg:HasState("knockback") or e:HasAnyTag("epic","knockbackimmune","wall")
        or e.sg:HasAnyStateTag("frozen","flight","knockback","jumping","noknockback") then return end
    local x,_,z=e.Transform:GetWorldPosition()
    local distance=k.distance
    local nearby=M.near(x,z,distance+C.knockback.query_padding)
    while distance>C.knockback.min_distance and not M.clear(x,z,x+dx*distance,z+dz*distance,nearby,nil,true) do distance=distance-C.knockback.step end
    if distance<=C.knockback.min_distance then return end
    local anchor=CreateEntity()
    anchor.entity:AddTransform();anchor:AddTag("FX");anchor.persists=false
    anchor.Transform:SetPosition(x-dx*C.knockback.anchor_offset,0,z-dz*C.knockback.anchor_offset)
    e:PushEvent("knockback",{knocker=anchor,radius=C.knockback.radius,strengthmult=C.knockback.strength*distance})
    anchor:DoTaskInTime(C.knockback.anchor_lifetime,anchor.Remove)
end
function M.native_hit(owner,e,p,loss,dx,dz)
    require("nw/journal_damage").record(owner,p,loss)
    leech(owner,p.flags,loss)
    if (loss>0 or p.flags.targets or p.flags._nw_target_bypass) and p.flags.knockback
        and e:IsValid() and not (e.components.health and e.components.health:IsDead()) then
        local d=math.max(C.direction_epsilon,math.sqrt(dx*dx+dz*dz))
        knock(e,dx/d,dz/d,p.flags.knockback)
    end
end
function M.electric_attack(owner,e,p,damage,fx,options)
    options=options or {}
    if Target.selectable_prop(owner,e,p.flags) then e._nw_break(owner);return 0 end
    if (not options.backfire or p.flags.targets) and not Target.selected(owner,e,p.flags) then return 0 end
    local h=e.components.health
    if not h or h:IsDead() then return 0 end
    local before=h.currenthealth
    fx.components.weapon:SetDamage(damage)
    if e.components.combat and owner.components.combat then
        if options.backfire or e:HasTag("player") and p.flags.targets then
            e.components.combat:GetAttacked(options.attacker or owner,damage,fx,"electric")
        else owner.components.combat:DoAttack(e,fx,fx,nil,nil,options.range,options.source) end
    else Damage.delta(p,e,-damage,nil,"electric",nil,owner) end
    return math.max(0,before-math.max(0,h.currenthealth))
end
function M.direct(owner,e,p,dx,dz)
    if Target.selectable_prop(owner,e,p.flags) then e._nw_break(owner);return end
    if not Target.selected(owner,e,p.flags) then return end
    local loss=deal(owner,e,p.damage,p.flags,p.burn_damage and "fire" or p.freeze and "ice" or nil,p)
    if not e:IsValid() or e.components.health and e.components.health:IsDead() then return end
    local still_wet=p.burn_damage and valid_hit(owner,e,p.flags) and M.evaporate(e,p.damage*M.wet_mult(e,p.flags))
    if loss<=0 and not (p.freeze or p.flags.targets or p.flags._nw_target_bypass or Target.selected_object(owner,e,p.flags)) then return end
    if p.burn_damage and not still_wet then burn(owner,e,p) end
    if p.freeze then
        clear_burn(e)
        local b=e.components.burnable
        if b and b:IsBurning() then b:Extinguish() elseif b and b:IsSmoldering() then b:SmotherSmolder() end
        local f=e.components.freezable
        if f then f:AddColdness(p.freeze);f:SpawnShatterFX() end
    end
    if p.flags.knockback then knock(e,dx,dz,p.flags.knockback) end
end
local blast_targets={default_predicate=function(owner,e,flags)
    return e:HasTag("player") or Target.selected(owner,e,flags)
end}
function M.blast(owner,x,z,p)
    local crystal=p.id=="sleep_crystal" or p.id=="crystal_mine"
    if crystal then
        p=require("nw/util").copy(p)
        p.flags=Target.flags(p,"aftermath")
    end
    local quiet=p.quiet_burst or p.id=="spore_ball" or p.id=="end_beam"
    local fx=M.fx(crystal and "nw_crystal_burst_fx" or p.id=="moon_fall" and "nw_moon_impact_fx"
        or quiet and "nw_soft_blast_fx" or "nw_blast_fx",x,z)
    if fx then fx:SetRadius(p.radius) end
    local nearby=crystal and TheSim:FindEntities(x,0,z,p.radius,nil,Target.scan_exclude)
        or M.scan(x,z,p.radius,p.flags)
    for _,e in ipairs(nearby) do
        local egg=Target.selectable_prop(owner,e,p.flags)
        if egg and e:GetDistanceSqToPoint(x,0,z)<=p.radius*p.radius then
            e._nw_break(owner)
        elseif Target.accepts(owner,e,p.flags,blast_targets) and not (p.no_structures and Target.object(e)=="building") and e:GetDistanceSqToPoint(x,0,z)<=p.radius*p.radius then
            local ex,_,ez=e.Transform:GetWorldPosition()
            local dx,dz=ex-x,ez-z
            local distance=math.max(C.direction_epsilon,math.sqrt(dx*dx+dz*dz))
            local hitp=p
            if e:HasTag("player") and not p.flags.targets and not crystal then
                hitp=require("nw/util").copy(p)
                hitp.flags.targets={self=true,players_other=true}
            end
            require("nw/expanded_hits").impact({owner=owner,p=hitp,age=0,dx=dx/distance,dz=dz/distance},e,ex,ez)
            require("nw/explosions").hit(owner,p,ex,ez)
        end
    end
end
function M.chain(owner,first,x,z,p,aim_x,aim_z,prefer_front,fire,onfinish)
    local seen={}
    local source_height=Chain.source_height
    p=require("nw/util").copy(p)
    local hop=0
    local fog_path={}
    local hit={owner=owner,p=p,fire=fire}
    local function finish()
        if onfinish then local done=onfinish;onfinish=nil;done() end
    end
    local function step()
        if not M.live(owner) then finish();return end
        hop=hop+1
        local e
        if hop==1 and first and Target.accepts(owner,first,p.flags,{breakables=true}) and
            first:GetDistanceSqToPoint(x,0,z)<=p.radius*p.radius then
            e=first
        else
            e=arc_target(owner,x,z,p.radius,seen,hop==1 and prefer_front and aim_x or nil,aim_z,p.flags)
        end
        local rain_backfire=hop>1 and not seen[owner] and TheWorld.state and TheWorld.state.israining
            and owner.GetIsWet and owner:GetIsWet() and owner:GetDistanceSqToPoint(x,0,z)<=p.radius*p.radius
            and (not p.flags.targets or Target.selected(owner,owner,p.flags))
            and math.random()<Chain.backfire_chance
        if rain_backfire then e=owner end
        local tx,_,tz
        local target_height=Chain.ground_height
        if e then
            tx,_,tz=e.Transform:GetWorldPosition()
            target_height=require("nw/electric_visual").target_height(e)
        else
            local angle=math.atan2(aim_z,aim_x)+(math.random()*2-1)*Chain.empty_spread_degrees*DEGREES
            tx,tz=x+p.radius*math.cos(angle),z+p.radius*math.sin(angle)
            M.fx("nw_ground_shock_fx",tx,tz)
        end
        local dx,dz=tx-x,tz-z
        local fx=M.fx("nw_arc_fx",x,z,source_height)
        if not fx then finish();return end
        Damage.tag(fx,p)
        fx:SetSpan(dx,dz,e,target_height-source_height)
        if p.flags.dark then
            local fog=require("nw/dark_fog")
            fog.leave(owner,x,z,p)
            fog.leave(owner,tx,tz,p)
            fog.trail(fog_path,{owner=owner,p=p},x,z,tx,tz,true)
        end
        if e then
            local loss=M.electric_attack(owner,e,p,(hop==1 and p.damage or p.jump_damage)*M.wet_mult(e,p.flags),fx,
                {backfire=rain_backfire,attacker=fx,range=p.radius,source=Vector3(x,0,z)})
            M.native_hit(owner,e,p,loss,dx,dz)
            local distance=math.sqrt(dx*dx+dz*dz)
            hit.dx,hit.dz=aim_x,aim_z
            if distance>C.direction_epsilon then hit.dx,hit.dz=dx/distance,dz/distance end
            require("nw/projectile_triggers").hit(hit,e,tx,tz)
            seen[e]=true
        end
        x,z=tx,tz
        source_height=target_height
        if hop<math.min(Instant.cards.chain.max_targets,p.max_targets) and M.live(owner) then TheWorld:DoTaskInTime(Chain.interval,step)
        else finish() end
    end
    step()
end
function M.afterlight(owner,x,z)
    local Budget=require("nw/entity_limits")
    local release=Budget.acquire(owner,"fields")
    if not release then return end
    local light=M.fx("nw_afterlight",x,z)
    local limits=require("nw/spell_limits")
    if light then Budget.bind(light,release);limits.track(light,owner,"_nw_lights") else release() end
end
return M
