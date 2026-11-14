local C=require("nw/constants/visuals/beam_visual")
local Path=require("nw/beam_path")
local Front=require("nw/beam_front")
local Glow=require("nw/projectile_glow")
local M={}
local FRAME=C.frame
local BANK=C.bank
local MATERIAL_SLICES=C.material_slices
local MATERIAL_FRAMES=C.material_frames
local SUBDIVISIONS=C.subdivisions
local NATIVE_LENGTH=C.native_length
local NATIVE_WIDTH=C.native_width
local BEAM_WIDTH_SCALE=C.beam_width_scale
local STAR_SCALE=C.star_scale
local HEAD_BANK=C.head_bank
local HEAD_WIDTH=C.head_width
local HEAD_PERIOD=C.head_period
local HEAD_RATE=C.head_rate
local HEAD_SORT_RADIUS=STAR_SCALE*C.head_sort_pixels/C.head_pixels
local HEAD_CONNECTOR_LENGTH=C.head_connector_length
local CONNECTOR_NATIVE_LENGTH=C.connector_native_length
local CONNECTOR_RESERVE=C.connector_reserve
local JOIN_EPS=C.join_eps
local JOIN_OVERLAP=C.join_overlap
local VISIBLE={visible=true}
local HIDDEN={visible=false}
local NATIVE_PERIOD=MATERIAL_FRAMES/C.animation_fps
local TIP_MAX_DISTANCE=Path.front_max_distance
local TIP_MAX_AGE=Path.front_max_age

local function new_piece(phase,animation)
    local fx=CreateEntity()
    fx:AddTag("can_offset_sort_pos")
    fx.entity:AddTransform();fx.entity:AddAnimState()
    fx.entity:SetCanSleep(false)
    fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
    local isbeam=animation:sub(1,5)=="beam_"
    local ishead=animation=="head"
    local bank=isbeam and BANK or HEAD_BANK
    fx.AnimState:SetBank(bank);fx.AnimState:SetBuild(bank)
    fx.AnimState:SetOrientation(ishead and ANIM_ORIENTATION.BillBoard or ANIM_ORIENTATION.OnGround)
    fx.AnimState:SetFinalOffset(ishead and C.head_offset or isbeam and C.beam_offset or C.connector_offset)
    fx.AnimState:SetMultColour(1,1,1,1)
    fx.AnimState:PlayAnimation(animation,true)
    if ishead then fx.AnimState:SetDeltaTimeMultiplier(HEAD_RATE) end
    fx.AnimState:SetTime(ishead and (phase*HEAD_RATE)%HEAD_PERIOD or phase%NATIVE_PERIOD)
    return fx
end

local function beam_piece(id,phase)
    local animation="beam_"..((id-1)%MATERIAL_SLICES).."_part_"
    local slices={}
    for index=1,SUBDIVISIONS do slices[index]=new_piece(phase,animation..(index-1)) end
    slices[1]._nw_beam_slices=slices
    return slices[1]
end

local function discard_piece(part)
    if not part then return end
    local slices=part.fx._nw_beam_slices
    if slices then
        for _,fx in ipairs(slices) do if fx:IsValid() then fx:Remove() end end
    elseif part.fx:IsValid() then part.fx:Remove() end
end

local function sort_at_head(fx,s,x,z,x1,z1,x2,z2,halfwidth)
    local anchor=s.ended and s.endpoint or s.anchor
    if s.head and anchor then
        local hx,hz=s.front_x,s.front_z
        local ax,az=x1-hx,z1-hz
        local bx,bz=x2-hx,z2-hz
        local px,pz=az*s.sort_c-ax*s.sort_s,(ax*s.sort_c+az*s.sort_s)*s.sort_pitch
        local qx,qz=bz*s.sort_c-bx*s.sort_s,(bx*s.sort_c+bz*s.sort_s)*s.sort_pitch
        local dx,dz=qx-px,qz-pz
        local length_sq=dx*dx+dz*dz
        local t=length_sq>0 and math.max(0,math.min(1,-(px*dx+pz*dz)/length_sq)) or 0
        if (px+t*dx)^2+(pz+t*dz)^2<=(anchor.radius*HEAD_SORT_RADIUS+halfwidth)^2 then
            fx.AnimState:SetSortWorldOffset(hx-x,0,hz-z)
            return
        end
    end
    fx.AnimState:SetSortWorldOffset(0,0,0)
end

local function visible_length(part,s)
    return math.max(0,part.length-(s.front_clips[part.id] or 0))
end

local function join_overlap(left,right,s)
    if not left or not right or right.id~=left.id+1 then return 0 end
    local a,b=visible_length(left,s),visible_length(right,s)
    if a<=.001 or b<=.001 then return 0 end
    local ux,uz=(left.x2-left.x1)/left.length,(left.z2-left.z1)/left.length
    local vx,vz=(right.x2-right.x1)/right.length,(right.z2-right.z1)/right.length
    if math.abs(left.x1+ux*a-right.x1)>JOIN_EPS
        or math.abs(left.z1+uz*a-right.z1)>JOIN_EPS then return 0 end
    local base=left.width>=1 and right.width>=1
        and math.min(JOIN_OVERLAP,C.overlap_fraction*math.min(a,b)/SUBDIVISIONS) or 0
    local dot=math.max(-1,math.min(1,ux*vx+uz*vz))
    local halfwidth=BEAM_WIDTH_SCALE*math.max(left.radius*left.width,right.radius*right.width)
    local turn=halfwidth*math.sqrt((1-dot)/math.max(.000001,1+dot))
    return math.min(base+turn,halfwidth,C.join_length_limit*math.min(a,b))
end

local function draw(part,height,width,clip,s)
    local length=math.max(0,part.length-(clip or 0))
    local ux,uz=(part.x2-part.x1)/part.length,(part.z2-part.z1)/part.length
    local piece_length=length/SUBDIVISIONS
    local overlap=width>=1 and math.min(JOIN_OVERLAP,C.overlap_fraction*piece_length) or 0
    local previous=s.parts[part.id-1]
    local following=s.parts[part.id+1] or s.tip and s.tip.id==part.id+1 and s.tip
    local back=join_overlap(previous,part,s)
    local forward=join_overlap(part,following,s)
    local rotation=-math.deg(math.atan2(part.z2-part.z1,part.x2-part.x1))
    for index,fx in ipairs(part.fx._nw_beam_slices) do
        local begin=(index-1)*piece_length-(index==1 and back or overlap)
        local finish=index*piece_length+(index==SUBDIVISIONS and forward or overlap)
        local ax,az=part.x1+ux*begin,part.z1+uz*begin
        local bx,bz=part.x1+ux*finish,part.z1+uz*finish
        local x,z=(ax+bx)*.5,(az+bz)*.5
        fx.Transform:SetPosition(x,height,z)
        fx.Transform:SetRotation(rotation)
        fx.AnimState:SetScale((finish-begin)/(NATIVE_LENGTH/SUBDIVISIONS),2*part.radius*width*BEAM_WIDTH_SCALE/NATIVE_WIDTH)
        fx.AnimState:SetMultColour(1,1,1,width)
        sort_at_head(fx,s,x,z,ax,az,bx,bz,part.radius*width*BEAM_WIDTH_SCALE)
        Glow.update(fx,length>.001 and VISIBLE or HIDDEN)
    end
end

local function remove_part(s,id)
    local part=s.parts[id]
    if part then
        discard_piece(part)
        s.parts[id]=nil
        s.retired=math.max(s.retired,id)
    end
end

local function remove_tip(s)
    discard_piece(s.tip)
    s.tip=nil
end

local function remove_front(s)
    remove_tip(s)
    discard_piece(s.head)
    s.head=nil
    discard_piece(s.connector)
    s.connector=nil
    s.front_tail=nil;s.front_cut=nil;s.front_x=nil;s.front_z=nil
end

local function leave_pool(s)
    local pool=s.pool
    if not pool then return end
    s.pool=nil
    for index=#pool.shots,1,-1 do
        if pool.shots[index]==s then
            pool.shots[index]=pool.shots[#pool.shots]
            pool.shots[#pool.shots]=nil
            break
        end
    end
    if #pool.shots==0 then
        pool.task:Cancel()
        pool.world:RemoveEventCallback("onremove",pool.onremove)
        if pool.world._nw_beam_visuals==pool then pool.world._nw_beam_visuals=nil end
    end
end

local function refresh_tip(s,now,height)
    local anchor=s.ended and s.endpoint or s.anchor
    if not anchor or s.ended and not next(s.parts)
        or not s.ended and now-s.received+anchor.age>TIP_MAX_AGE then remove_front(s);return false end
    local x,_,z=s.inst.Transform:GetWorldPosition()
    if s.ended then x,z=anchor.x,anchor.z end
    local dx,dz=x-anchor.x,z-anchor.z
    local length=math.sqrt(dx*dx+dz*dz)
    if length>TIP_MAX_DISTANCE then remove_front(s);return false end
    s.front_tail=nil;s.front_cut=nil
    if not s.ended and TheWorld.ismastersim==false then
        local heading=s.inst.Transform.GetRotation and s.inst.Transform:GetRotation() or nil
        local resolved=Front.resolve(s.parts,anchor,x,z,heading)
        if resolved then
            local part=resolved.part
            x,z=resolved.x,resolved.z
            local previous=s.parts[part.id-1]
            if resolved.length<.001 and previous
                and math.abs(previous.x2-x)<=JOIN_EPS and math.abs(previous.z2-z)<=JOIN_EPS then
                part=previous;resolved.length=part.length;resolved.clip=0
            end
            s.front_tail={id=part.id,fx=part.fx,x1=part.x1,z1=part.z1,x2=x,z2=z,
                length=resolved.length,radius=part.radius,width=part.width}
            s.front_cut=resolved.clip
        end
    end
    s.front_x,s.front_z=x,z
    if not s.head then s.head={fx=new_piece(now,"head")} end
    local head=s.head.fx
    head.Transform:SetPosition(x,height,z)
    local headscale=2*anchor.radius*STAR_SCALE/HEAD_WIDTH
    head.AnimState:SetScale(headscale,headscale)
    Glow.update(head)
    if s.ended then remove_tip(s);return true end
    if s.front_tail then remove_tip(s);return true end
    if length<.001 then remove_tip(s);return true end
    local tip_id=anchor.id+1
    if s.tip and s.tip.id~=tip_id then remove_tip(s) end
    if not s.tip then s.tip={id=tip_id,fx=beam_piece(tip_id,now)} end
    local tip=s.tip
    tip.x1,tip.z1,tip.x2,tip.z2=anchor.x,anchor.z,x,z
    tip.radius,tip.length=anchor.radius,length
    return true
end

local function front_clips(s,now,height)
    local clips=s.front_clips
    for id in pairs(clips) do clips[id]=nil end
    if s.front_tail then
        for id,part in pairs(s.parts) do
            if id>s.front_tail.id then clips[id]=part.length end
        end
        clips[s.front_tail.id]=s.front_cut
    end
    local function absent()
        discard_piece(s.connector);s.connector=nil
        return clips,0
    end
    if not s.head then return absent() end
    local anchor=s.ended and s.endpoint or s.anchor
    local tail=s.front_tail or s.tip or anchor and s.parts[anchor.id]
    if not tail or tail.length<.001 then return absent() end
    local hx,hz=s.front_x,s.front_z
    if math.abs(tail.x2-hx)>JOIN_EPS or math.abs(tail.z2-hz)>JOIN_EPS then return absent() end
    local dx,dz=(tail.x2-tail.x1)/tail.length,(tail.z2-tail.z1)/tail.length
    local wanted=HEAD_CONNECTOR_LENGTH*anchor.radius
    local run,total={},0
    local part=tail
    local x,z=hx,hz
    while part do
        local px,pz=part.x2-part.x1,part.z2-part.z1
        local dot=(px*dx+pz*dz)/part.length
        local lateral=math.abs((part.x1-hx)*dz-(part.z1-hz)*dx)
        if math.abs(part.x2-x)>JOIN_EPS or math.abs(part.z2-z)>JOIN_EPS
            or dot<1-.000001 or lateral>math.min(JOIN_EPS,tail.radius*.01)
            or math.abs(part.width-tail.width)>.000001
            or math.abs(part.radius*part.width-tail.radius*tail.width)>.000001 then break end
        run[#run+1]=part;total=total+part.length
        if total>=wanted+CONNECTOR_RESERVE then break end
        x,z=part.x1,part.z1
        part=s.parts[part.id-1]
    end
    local remaining=math.min(wanted,total-CONNECTOR_RESERVE)
    if remaining<=CONNECTOR_RESERVE then return absent() end
    local terminal,cut
    for _,candidate in ipairs(run) do
        if remaining<candidate.length then
            cut=math.min(remaining,math.max(0,candidate.length-CONNECTOR_RESERVE))
            terminal=candidate
            break
        end
        clips[candidate.id]=(clips[candidate.id] or 0)+candidate.length
        remaining=remaining-candidate.length
    end
    if not terminal then
        for id in pairs(clips) do clips[id]=nil end
        if s.front_tail then
            for id,part in pairs(s.parts) do if id>s.front_tail.id then clips[id]=part.length end end
            clips[s.front_tail.id]=s.front_cut
        end
        return absent()
    end
    clips[terminal.id]=(clips[terminal.id] or 0)+cut
    local fraction=(terminal.length-cut)/terminal.length
    local jx=terminal.x1+(terminal.x2-terminal.x1)*fraction
    local jz=terminal.z1+(terminal.z2-terminal.z1)*fraction
    local length=math.sqrt((hx-jx)^2+(hz-jz)^2)
    local animation="connector_"..((terminal.id-1)%MATERIAL_SLICES)
    if not s.connector then s.connector={fx=new_piece(now,animation),animation=animation} end
    local connector=s.connector
    if connector.animation~=animation then
        connector.fx.AnimState:PlayAnimation(animation,true)
        connector.fx.AnimState:SetTime(now%NATIVE_PERIOD)
        connector.animation=animation
    end
    connector.terminal=terminal.id
    local fx=connector.fx
    fx.Transform:SetPosition((jx+hx)*.5,height,(jz+hz)*.5)
    fx.Transform:SetRotation(-math.deg(math.atan2(hz-jz,hx-jx)))
    fx.AnimState:SetScale(length/CONNECTOR_NATIVE_LENGTH,2*terminal.radius*terminal.width*BEAM_WIDTH_SCALE/NATIVE_WIDTH)
    fx.AnimState:SetMultColour(1,1,1,terminal.width)
    fx.AnimState:SetSortWorldOffset(hx-(jx+hx)*.5,0,hz-(jz+hz)*.5)
    Glow.update(fx)
    return clips,s.tip and clips[s.tip.id] or 0
end

local function update(s,now)
    if not s.inst:IsValid() then M.detach(s.inst);return false end
    local camera=TheCamera
    local heading=(camera and camera.heading or 0)*math.pi/180
    s.sort_c,s.sort_s=math.cos(heading),math.sin(heading)
    s.sort_pitch=math.sin((camera and camera.pitch or C.camera_pitch)*math.pi/180)
    local height=s.inst._height:value()
    local remaining=false
    for id,part in pairs(s.parts) do
        local age=math.max(0,now-part.born)
        local width=Path.width(age)
        if age>=Path.lifetime-.000001 or width<=0 then remove_part(s,id)
        else part.width=width;remaining=true end
    end
    local tip=refresh_tip(s,now,height)
    if s.tip then s.tip.width=1 end
    local clips,tipclip=front_clips(s,now,height)
    for id,part in pairs(s.parts) do draw(part,height,part.width,clips[id],s) end
    if s.tip then draw(s.tip,height,1,tipclip,s) end
    return remaining or tip or not s.ended and s.anchor and now-s.received+s.anchor.age<=TIP_MAX_AGE
end

local function tick(world)
    local pool=world._nw_beam_visuals
    if not pool then return end
    local now=GetTime()
    for index=#pool.shots,1,-1 do
        local s=pool.shots[index]
        if not update(s,now) then leave_pool(s) end
    end
end

local function enter_pool(s)
    if s.pool then return end
    local pool=TheWorld._nw_beam_visuals
    if not pool then
        pool={world=TheWorld,shots={}}
        TheWorld._nw_beam_visuals=pool
        pool.task=TheWorld:DoPeriodicTask(FRAME,tick)
        pool.onremove=function()
            for index=#pool.shots,1,-1 do M.detach(pool.shots[index].inst) end
        end
        TheWorld:ListenForEvent("onremove",pool.onremove)
    end
    s.pool=pool
    pool.shots[#pool.shots+1]=s
end

function M.detach(inst)
    local s=inst._nw_beam_visual
    if not s then return end
    for id in pairs(s.parts) do remove_part(s,id) end
    remove_front(s)
    leave_pool(s)
    inst:RemoveEventCallback("nw_beamdirty",s.onrefresh)
    inst:RemoveEventCallback("nw_projectiledirty",s.onrefresh)
    inst:RemoveEventCallback("onremove",s.onremove)
    s.world:RemoveEventCallback("onremove",s.onworldremove)
    inst._nw_beam_visual=nil
end

function M.refresh(inst)
    if TheNet:IsDedicated() or not inst._beam_path then return end
    local s=inst._nw_beam_visual
    if not s then return M.attach(inst) end
    s.ended=s.ended or inst._beam_ended:value()
    if s.ended then remove_tip(s) end
    local snapshot=Path.decode(inst._beam_path:value())
    local now=GetTime()
    if snapshot and (not s.stamp or snapshot.time>=s.stamp) then
        if not s.stamp or snapshot.time>s.stamp then s.received=now end
        s.stamp=snapshot.time
        local seen={}
        local newest
        for _,segment in ipairs(snapshot.segments) do
            local id=segment.id
            seen[id]=true
            if not newest or id>newest.id then newest=segment end
            local part=s.parts[id]
            if part or id>s.retired then
                local dx,dz=segment.x2-segment.x1,segment.z2-segment.z1
                local length=math.sqrt(dx*dx+dz*dz)
                if segment.age<Path.lifetime and segment.radius>0 and length>.001 then
                    local born=now-segment.age
                    if not part then
                        part={id=id,fx=beam_piece(id,now),born=born}
                        s.parts[id]=part
                    elseif born<part.born then
                        part.born=born
                    end
                    part.x1,part.z1,part.x2,part.z2=segment.x1,segment.z1,segment.x2,segment.z2
                    part.radius,part.length=segment.radius,length
                else
                    remove_part(s,id)
                    s.retired=math.max(s.retired,id)
                end
            end
        end
        for id in pairs(s.parts) do if not seen[id] then remove_part(s,id) end end
        s.anchor=newest and {id=newest.id,x=newest.x2,z=newest.z2,
            dx=newest.x2-newest.x1,dz=newest.z2-newest.z1,radius=newest.radius,age=newest.age} or nil
        if s.ended and s.anchor then
            s.endpoint=s.anchor
        end
    end
    if update(s,now) then enter_pool(s) else leave_pool(s) end
end

function M.attach(inst)
    if TheNet:IsDedicated() or not inst._beam_path or not inst:IsValid() then return end
    local previous=inst._nw_beam_visual
    if previous then return previous end
    local s={inst=inst,world=TheWorld,parts={},front_clips={},retired=0,received=-math.huge,ended=false}
    s.onrefresh=function() M.refresh(inst) end
    s.onremove=function() M.detach(inst) end
    s.onworldremove=s.onremove
    inst._nw_beam_visual=s
    inst:ListenForEvent("nw_beamdirty",s.onrefresh)
    inst:ListenForEvent("nw_projectiledirty",s.onrefresh)
    inst:ListenForEvent("onremove",s.onremove)
    s.world:ListenForEvent("onremove",s.onworldremove)
    M.refresh(inst)
    return s
end

return M
