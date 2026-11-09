local Flight=require("nw/elemental_flight")
local FRAME=1/30
local LIFE=6*FRAME
local now,tick,created,removed,started,cancelled,tail_plays=0,nil,0,0,0,0,0
local dedicated=false
local heads={}
local noop=function() end
ANIM_ORIENTATION={BillBoard=2}
TheCamera={heading=0,pitch=35}
TheNet={IsDedicated=function() return dedicated end}
function GetTime() return now end
TheWorld={DoPeriodicTask=function(_,period,fn)
    assert(period==FRAME)
    assert(not tick,"one shared elemental scheduler")
    started=started+1;tick=fn
    return {Cancel=function() cancelled=cancelled+1;tick=nil end}
end}
local function sprite()
    local fx={valid=true,visible=true,entity={},Transform={},AnimState={},plays=0,times={}}
    for _,name in ipairs({"AddTransform","AddAnimState","SetCanSleep"}) do fx.entity[name]=noop end
    fx.entity.IsVisible=function() return fx.visible end
    fx.Transform.SetPosition=function(_,x,y,z) fx.x,fx.y,fx.z=x,y,z end
    fx.Transform.SetScale=function(_,x,y,z) fx.scale=x;assert(x==y and y==z) end
    fx.AnimState.SetBank=function(_,bank) fx.bank=bank end
    fx.AnimState.SetBuild=noop
    fx.AnimState.SetOrientation=function(_,orientation) fx.orientation=orientation end
    fx.AnimState.SetLightOverride=noop
    fx.AnimState.SetDeltaTimeMultiplier=function(_,rate)
        assert(rate>0 and rate<=1)
        fx.playback=rate
    end
    fx.AnimState.PlayAnimation=function(_,name,loop)
        fx.anim,fx.loop=name,loop;fx.plays=fx.plays+1
        if name:find("_tail_dir_",1,true) then tail_plays=tail_plays+1 end
    end
    fx.AnimState.SetTime=function(_,age)
        local clip=fx.anim and fx.anim:find("^tri_electric_dir_") and .4 or LIFE
        assert(age>=0 and age<clip+.00001)
        fx.times[#fx.times+1]=age;fx.age=age
    end
    fx.AddTag=noop
    fx.IsValid=function() return fx.valid end
    fx.Remove=function() assert(fx.valid);fx.valid=false;removed=removed+1 end
    return fx
end
function CreateEntity() created=created+1;return sprite() end
local function shot(id,guid,scale,heading)
    local s={GUID=guid or #heads+1,valid=true,x=0,z=0,vx=0,vz=0,rotation=0,scale=scale or 1}
    s.Transform={GetWorldPosition=function() return s.x,0,s.z end,GetRotation=function() return s.rotation end}
    s.Physics={GetVelocity=function() return s.vx,0,s.vz end}
    s._visual=sprite()
    s._height={value=function() return 1.6 end}
    s._size={value=function() return s.scale end}
    if heading then s._launch_heading={value=function() return heading+4 end} end
    s.IsValid=function() return s.valid end
    heads[#heads+1]=s
    Flight.attach(s,id)
    return s
end
local function near(a,b) assert(math.abs(a-b)<.000001,tostring(a).." ~= "..tostring(b)) end
local function advance(motions,dt)
    dt=dt or FRAME
    for _,s in ipairs(heads) do s.vx,s.vz=0,0 end
    for _,m in ipairs(motions or {}) do
        local s,dx,dz=m[1],m[2],m[3]
        s.x,s.z=s.x+dx,s.z+dz;s.vx,s.vz=dx/dt,dz/dt
        if dx~=0 or dz~=0 then s.rotation=-math.atan2(dz,dx)*180/math.pi end
    end
    now=now+dt
    if tick then tick(TheWorld) end
end
local function retire()
    for _,s in ipairs(heads) do s.valid=false end
    for _=1,28 do advance() end
    assert(not tick and not TheWorld._nw_elemental_flights)
    assert(created==removed,"every local trail is cleaned after its owner ends")
end

local fire=shot("fire",1)
local frost=shot("frost",2,2.5)
assert(started==1 and #TheWorld._nw_elemental_flights.shots==2)
Flight.attach(fire,"fire")
assert(#TheWorld._nw_elemental_flights.shots==2,"dirty refresh cannot duplicate attachment")
assert(fire._visual.bank=="nw_elemental_flight" and fire._visual.orientation==ANIM_ORIENTATION.BillBoard)
for _=1,2 do advance({{fire,.5,0},{frost,.5,0}}) end
local ember=fire._nw_elemental_flight.parts[1]
local ice=frost._nw_elemental_flight.parts[1]
assert(ember and ice)
local ex,ez,ix,iz=ember.fx.x,ember.fx.z,ice.fx.x,ice.fx.z
local old_head_plays=fire._visual.plays
local old_ember_plays=ember.fx.plays
advance({{fire,0,.5},{frost,0,.5}})
near(ember.fx.x,ex+.12*15*FRAME);near(ember.fx.z,ez)
near(ice.fx.x,ix);near(ice.fx.z,iz)
near(ice.fx.y,1.6);near(ice.fx.scale,2.5)
assert(ember.fx.plays==old_ember_plays,"old tail direction does not chase turning head")
assert(fire._visual.plays==old_head_plays+1)
near(fire._visual.age,(now-fire._nw_elemental_flight.started+FRAME)%LIFE)
local old_ice_dir=ice.fx.anim
TheCamera.heading=90
advance({{fire,0,.5},{frost,0,.5}})
assert(ice.fx.anim~=old_ice_dir,"a frozen world-space fragment still faces a turned camera correctly")
near(ice.fx.age,(now-ice.born)*ice.fx.playback)
near(ice.fx.x,ix);near(ice.fx.z,iz)
local plays=fire._visual.plays
advance({{fire,0,.5},{frost,0,.5}})
assert(fire._visual.plays==plays,"unchanged facing never restarts the head animation")
retire()

-- Giant particles retain their own lifetime and animation clock after the
-- carrier ends. The birth rate falls as the six-frame dissolve slows down.
local timings={
    {1,.2,24},
    {2.5,.31622776601683794,15.17893276880822},
    {5,.447213595499958,10.73312629199899},
    {7.5,.5477225575051661,8.763560920082657},
    {100,.6,8},
}
for _,row in ipairs(timings) do
    local scale,lifetime,rate=unpack(row)
    local life,interval=Flight.trail_timing(scale)
    near(life,lifetime);near(1/interval,rate)
    for _,kind in ipairs({"fire","frost"}) do
        local giant=shot(kind,40,scale)
        local before=tail_plays
        for _=1,30 do advance({{giant,.5,0}}) end
        assert(math.abs((tail_plays-before)-math.floor(rate+.000001))<=1,
            "giant tails must emit more slowly, not only disappear later")
        local occupied=0
        for _,part in pairs(giant._nw_elemental_flight.parts) do
            occupied=occupied+1
            near(part.lifetime,lifetime)
            near(part.fx.playback,.2/lifetime)
        end
        assert(occupied<=5,"giant tail duration must not increase per-shot occupancy")
        -- Force a turn after several head cycles. Its clock remains 0.2 s.
        advance({{giant,0,.5}})
        near(giant._visual.age,(now-giant._nw_elemental_flight.started+40%6*FRAME)%LIFE)
        retire()

        local ending=shot(kind,41,scale)
        while not ending._nw_elemental_flight.parts[1] do advance({{ending,.5,0}}) end
        local part=ending._nw_elemental_flight.parts[1]
        local fx,born=part.fx,part.born
        local px,pz=fx.x,fx.z
        local measured=now
        ending.valid=false
        while now-born<.2+.000001 do advance() end
        if scale==1 then
            assert(not fx.valid,"ordinary tails must still disappear after 0.2 s")
        else
            assert(fx.valid and tick,"giant tail must outlive the old 0.2 s cutoff")
            local drift=kind=="fire" and .12*15 or 0
            near(fx.x,px+drift*(now-measured));near(fx.z,pz)
            TheCamera.heading=(TheCamera.heading+90)%360
            advance()
            near(fx.age,(now-born)*.2/lifetime)
            while now-born+FRAME<lifetime-.00001 do advance() end
            assert(fx.valid,"tail must not disappear before its birth lifetime")
            advance()
            assert(not fx.valid,"tail must be cleaned at its own lifetime, including the 0.6 s cap")
        end
        retire()
    end
end

-- A replicated size reduction changes future births, not existing particles.
-- Faster new emissions must not overwrite the five longer-lived old slots.
local resizing=shot("frost",60,100)
for _=1,19 do advance({{resizing,.5,0}}) end
local oldparts={}
for _,part in pairs(resizing._nw_elemental_flight.parts) do
    oldparts[#oldparts+1]={part=part,born=part.born,x=part.fx.x,z=part.fx.z}
end
assert(#oldparts>0)
resizing.scale=1
for _=1,6 do
    advance({{resizing,.5,0}})
    for _,old in ipairs(oldparts) do
        if now-old.born<.6-.00001 then
            near(old.part.born,old.born)
            near(old.part.lifetime,.6)
            near(old.part.fx.scale,100)
            near(old.part.fx.playback,1/3)
            near(old.part.fx.x,old.x);near(old.part.fx.z,old.z)
            assert(old.part.fx.valid,"size changes cannot discard a live giant particle")
        end
    end
end
for _=1,24 do advance({{resizing,.5,0}}) end
local normalparts=0
for _,part in pairs(resizing._nw_elemental_flight.parts) do
    normalparts=normalparts+1
    near(part.lifetime,.2);near(part.fx.playback,1);near(part.fx.scale,1)
end
assert(normalparts>0,"resized projectile must resume normal-rate particle births")
retire()

-- Hidden shots and corrections create no streaks; high physical velocity is valid.
local fast=shot("fire",8)
fast._visual.visible=false
for _=1,3 do advance({{fast,.5,0}}) end
assert(TheWorld._nw_elemental_flights.count==0)
fast._visual.visible=true
fast.x=fast.x+30 -- teleport, with no physical velocity
advance()
assert(TheWorld._nw_elemental_flights.count==0)
for _=1,3 do advance({{fast,10,0}}) end -- 300 world units/s
assert(TheWorld._nw_elemental_flights.count>0,"legitimate fast projectiles retain trails")
advance({{fast,10,0}},.5)
assert(TheWorld._nw_elemental_flights.count==0,"a late frame does not emit a catch-up trail")
retire()

-- Unlimited default retains all tails beyond the former 128-segment cap.
local crowd={}
for i=1,40 do crowd[i]=shot(i%2==0 and "fire" or "frost",i+20,i%2==0 and 100 or 1) end
local peak=0
for _=1,30 do
    local moves={}
    for _,s in ipairs(crowd) do moves[#moves+1]={s,.5,0} end
    advance(moves)
    local count=TheWorld._nw_elemental_flights.count
    peak=math.max(peak,count)
    assert(count<=200 and created-removed==count)
end
assert(peak>128)
for _,s in ipairs(crowd) do assert(s._visual.anim and s._visual.loop) end
retire()

local function ordered_parts(s)
    local result={}
    for _,part in pairs(s._nw_elemental_flight.parts) do result[#result+1]=part end
    table.sort(result,function(a,b) return a.born<b.born end)
    return result
end
local function distance(ax,az,bx,bz) return math.sqrt((ax-bx)^2+(az-bz)^2) end
local function connected(s,heading,front_only)
    local parts=ordered_parts(s)
    local spacing,coverage=Flight.trail_spacing(s.scale)
    local _,offset=Flight.trail_motion("arrow")
    assert(#parts>0 and #parts<=128)
    if not front_only then
        for index=2,#parts do
            assert(distance(parts[index-1].x,parts[index-1].z,parts[index].x,parts[index].z)<=spacing+.000001,
                "adjacent short pieces must stay connected across sampling frames")
        end
    end
    local fresh=parts[#parts]
    local ax,az=s.x-offset*s.scale*math.cos(heading),s.z-offset*s.scale*math.sin(heading)
    assert(distance(fresh.x,fresh.z,ax,az)<=coverage/2+.000001,
        "the latest short piece must cover the unsampled gap at the arrow tail")
    return fresh
end

-- Motor facing may already describe the next turn. The arrow still follows
-- travelled motion; its trail follows the actual rear-anchor path independently.
local arrow=shot("arrow",120)
for camera=0,3 do
    TheCamera.heading=17+camera*90
    for step=0,23 do
        local heading=(step*15+7)*math.pi/180
        local dx,dz=25*FRAME*math.cos(heading),25*FRAME*math.sin(heading)
        arrow.x,arrow.z=arrow.x+dx,arrow.z+dz
        arrow.vx,arrow.vz=dx/FRAME,dz/FRAME
        arrow.rotation=-heading*180/math.pi-45 -- next motor direction differs
        now=now+FRAME;tick(TheWorld)
        local fresh=connected(arrow,heading)
        local head=tonumber(arrow._visual.anim:match("_dir_(%d+)$"))
        local tail=tonumber(fresh.fx.anim:match("_dir_(%d+)$"))
        assert(tail==Flight.direction(fresh.heading,"arrow"))
        local rel=heading-TheCamera.heading*math.pi/180
        local projected=math.atan2(math.cos(rel)*math.sin(TheCamera.pitch*math.pi/180),math.sin(rel))
        local error=(head*2*math.pi/128-projected+math.pi)%(2*math.pi)-math.pi
        assert(math.abs(error)<=math.pi/128+.000001,"long arrows need fine directional precision")
    end
end
local parts=ordered_parts(arrow)
local fading=parts[#parts]
local born=fading.born
arrow.valid=false
while now-born<.2+FRAME do advance() end
assert(fading.fx.valid,"ordinary arrow tails must remain after the old 0.2 second cutoff")
retire()

-- The same straight path must produce the same positions and interpolated
-- birth times at 30 Hz and at a lower sampling rate.
local function straight(dt)
    local s=shot("arrow",123)
    local start=now
    for _=1,math.floor(1.2/dt+.5) do advance({{s,25*dt,0}},dt) end
    connected(s,0)
    local result={}
    for _,part in ipairs(ordered_parts(s)) do result[#result+1]={x=part.x,t=part.born-start} end
    retire()
    return result
end
local regular,slow=straight(1/30),straight(.1)
assert(#regular==#slow)
for index,part in ipairs(regular) do near(part.x,slow[index].x);near(part.t,slow[index].t) end

-- Legal maximum-speed motion needs more than two births per frame and remains
-- connected even across a 0.2 s frame. A giant uses longer physical spacing.
for _,scale in ipairs({1,2.5,7.5}) do
    local s=shot("arrow",124,scale)
    local before=tail_plays
    advance({{s,12,0}},.2)
    assert(tail_plays-before>2 and tail_plays-before<=64)
    connected(s,0)
    for _=1,20 do advance({{s,2,0}});connected(s,0) end
    retire()
end

-- Teleport, hidden motion and pathological samples reset the path instead of
-- filling the gap with a straight line or accumulating a future backlog.
local cut=shot("arrow",125)
advance({{cut,.5,0}})
local before=tail_plays
cut.x=cut.x+40
advance()
assert(not cut._nw_elemental_flight.path and tail_plays==before)
advance({{cut,.5,0}})
for _,part in ipairs(ordered_parts(cut)) do
    assert(part.x<1 or part.x>39,"a teleport must never be connected")
end
cut._visual.visible=false
before=tail_plays
advance({{cut,4,0}})
assert(tail_plays==before and not cut._nw_elemental_flight.path)
cut._visual.visible=true
advance({{cut,.5,0}});connected(cut,0,true)
before=tail_plays
advance({{cut,50,0}},.2) -- deliberately above the natural 60-unit speed ceiling
assert(tail_plays-before==1,"oversized samples mark the new front without a catch-up streak")
advance({{cut,.5,0}})
local newest=ordered_parts(cut)
assert(newest[#newest].x>90)
retire()

-- A shared admission limit skips births and lets old arrow/fire tails fade.
local Budget=require("nw/trail_budget")
Budget.configure(500)
local arrows={}
local protected=shot("fire",129)
for index=1,8 do arrows[index]=shot("arrow",130+index) end
for _=1,30 do
    local moves={{protected,.5,0}}
    for _,s in ipairs(arrows) do moves[#moves+1]={s,25*FRAME,0} end
    advance(moves)
    local pool=TheWorld._nw_elemental_flights
    assert(pool.arrow_count<=pool.count and pool.count<=375)
    assert(created-removed==pool.count)
end
assert(TheWorld._nw_elemental_flights.count>0 and TheWorld._nw_elemental_flights.count<=375)
retire()
Budget.configure(0)

-- Scatter keeps big, medium and small ages visible together. GUID staggering
-- offsets the three pellets instead of replacing one synchronized crumb.
local pellets={shot("scatter",201),shot("scatter",202),shot("scatter",203)}
for _=1,24 do
    local moves={}
    for _,s in ipairs(pellets) do moves[#moves+1]={s,.5,0} end
    advance(moves)
end
local latest={}
for _,s in ipairs(pellets) do
    local ages={}
    local list=ordered_parts(s)
    assert(#list>=5 and #list<=6)
    for _,part in ipairs(list) do
        near(part.lifetime,.3)
        ages[math.floor((now-part.born)/part.lifetime*3+.000001)]=true
    end
    assert(ages[0] and ages[1] and ages[2],"scatter must show three overlapping ages")
    latest[#latest+1]=list[#list].born
end
assert(latest[1]~=latest[2] and latest[2]~=latest[3] and latest[1]~=latest[3])
retire()

-- Special bullets use travelled facing, retain several independently aged
-- fragments, and share the same bounded giant lifetime / cleanup rules.
local specials={"gust","spore_ball","flint_lance","slime","grow_orb","heal_bolt",
    "star_vortex","glass_disc","tri_electric","end_beam","soundwave","bee_swarm","fireflies"}
for _,kind in ipairs(specials) do
    local s=shot(kind,220,2.5)
    local state=s._nw_elemental_flight
    assert(state and not state.path)
    local life,interval=Flight.trail_timing(2.5,kind)
    local ordinary=Flight.trail_timing(1,kind)
    local slots=kind=="flint_lance" and 128 or math.ceil(life/interval-.000001)
    assert(life>ordinary and state.slots==slots)
    for _=1,15 do
        s.x=s.x+26*FRAME;s.vx=26;s.vz=0;s.rotation=90
        now=now+FRAME;tick(TheWorld)
        assert(s._visual.anim==kind.."_dir_"..Flight.direction(0,kind),"special head must follow actual motion")
    end
    local parts=ordered_parts(s)
    assert(#parts>=3 and #parts<=state.slots)
    assert(parts[1].born<parts[#parts].born,"special trails must overlap independent ages")
    local ages={}
    for _,part in ipairs(parts) do
        near(part.lifetime,life);near(part.fx.scale,2.5)
        ages[math.floor((now-part.born)/life*3+.000001)]=true
    end
    assert(ages[0] and ages[1] and ages[2],"special trails must show young, middle and fading fragments together")
    local count=(kind=="flint_lance" or kind=="end_beam") and 128 or 32
    assert(Flight.direction_count(kind)==count)
    if kind=="tri_electric" then
        near(Flight.head_period(kind),.4)
        near(state.phase,(s.GUID%12)*FRAME)
        -- A direction change during the second half keeps the 12-frame head
        -- clock while all independently aged tails still play six frames.
        advance({{s,0,26*FRAME}})
        near(s._visual.age,((now-state.started)+state.phase)%.4)
        assert(s._visual.age>.2)
        for _,part in pairs(state.parts) do near(part.playback,.2/life) end
    end
    retire()
end
-- Hook and authored rope keep turning together without detached trail entities,
-- including after a replicated giant-size change and camera rotation.
local hook=shot("land_hook",229,1,math.pi/2)
local hook_created,hook_tails=created,tail_plays
assert(Flight.direction_count("land_hook")==64)
assert(hook._visual.anim=="land_hook_dir_"..Flight.direction(math.pi/2,"land_hook"))
for _=1,3 do
    TheCamera.heading=TheCamera.heading+15
    advance()
    assert(hook._visual.anim=="land_hook_dir_"..Flight.direction(math.pi/2,"land_hook"),
        "initial heading must survive stationary samples and camera changes before motion arrives")
end
for _,scale in ipairs({1,2.5,1}) do
    hook.scale=scale
    for step=1,24 do
        local heading=step*math.pi/12
        TheCamera.heading=step*7
        advance({{hook,.5*math.cos(heading),.5*math.sin(heading)}})
        assert(hook._visual.anim=="land_hook_dir_"..Flight.direction(heading,"land_hook"))
        assert(hook._visual.loop)
        assert(not next(hook._nw_elemental_flight.parts))
        assert(TheWorld._nw_elemental_flights.count==0)
        assert(created==hook_created and tail_plays==hook_tails,"hook must never spawn detached trails")
    end
end
assert(hook._visual.plays>1,"hook and rope must retain directional animation updates")
retire()

for _,id in ipairs({"note_a","ocarina_b","note_c","ocarina_d","ocarina_e","ocarina_f",
    "ocarina_gsharp","ocarina_a2","ocarina_g"}) do
    assert(Flight.resolve(id)=="soundwave" and Flight.supports(id))
    local s=shot(id,230)
    assert(s._nw_elemental_flight.id=="soundwave" and s._visual.anim:find("^soundwave_dir_"))
    Flight.attach(s,"soundwave")
    assert(#TheWorld._nw_elemental_flights.shots==1,"aliases must not attach duplicate schedulers")
    retire()
end
for _,id in ipairs({"kantele_a","chord_d","kantele_dsharp","kantele_e","kantele_g","spark"}) do
    assert(not Flight.supports(id),"stationary instrument fields and spark keep their existing visuals")
end

dedicated=true
local server=shot("fire",100)
assert(not server._nw_elemental_flight and not tick)
assert(started==cancelled)
print("elemental flight: legacy tails, connected arrows, bounded budgets, special motion facing, giant age overlap, ocarina-only aliases and cleanup")
