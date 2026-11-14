-- Inserted into test_beam_visual.lua's local harness by the preview tool.
-- Records the real renderer; no duplicate implementation of its geometry.
local micro_parts=16
local micro_length=2/micro_parts
for scenario=1,5 do
    local kind=scenario==1 and "straight" or scenario==2 and "corner" or scenario==3 and "terminal"
        or scenario==4 and "client-lag" or "gentle-curve"
    TheWorld.ismastersim=nil
    if scenario==4 then TheWorld.ismastersim=false end
    now=1000+scenario*10
    local origin=now
    local shot=anchor(0,0)
    local records={}
    local distance=26/30
    for id=1,12 do
        records[#records+1]=segment(id,(id-13)*distance,(id-12)*distance,
            now-(12-id)/30,.12)
    end
    shot._beam_path:set(Path.encode(records,now))
    local visual=Beam.attach(shot)
    local lastx,lastz=0,0
    local curvex,curvez=0,0
    for index=0,(scenario==3 and 78 or 60) do
        now=origin+index/30
        local travel=scenario==3 and math.min(index,24) or index
        local x=scenario==2 and math.min(index,30)*distance or travel*distance
        local z=scenario==2 and math.max(index-30,0)*distance or 0
        if scenario==5 then
            -- Sustained forward flow with repeated gradual turns. Heading
            -- changes peak at 9.9 degrees per span, reversing into an S bend.
            if index>0 then
                local heading=math.rad(55)*math.sin(index*.18)
                curvex=curvex+distance*math.cos(heading)
                curvez=curvez+distance*math.sin(heading)
            end
            x,z=curvex,curvez
        end
        shot.x,shot.z=x,z
        local serverx=scenario==4 and (index+1)*distance or x
        if (index>0 or scenario==4) and (scenario~=3 or index<=24) then
            records[#records+1]=segment(12+index+(scenario==4 and 1 or 0),lastx,serverx,now,.12,lastz,z)
        end
        if scenario==3 and index==24 then shot._beam_ended:set(true) end
        lastx,lastz=serverx,z
        if index%3==0 then
            local live={}
            for _,record in ipairs(records) do
                if now-record.born<Path.lifetime then live[#live+1]=record end
            end
            shot._beam_path:set(Path.encode(live,now))
            shot:PushEvent("nw_beamdirty")
        else
            tick(now)
        end
        if scenario~=3 or index<69 then
            assert(visual.head and visual.connector,"front/residue has a continuous material connection")
        else
            assert(not visual.head and not visual.connector and not next(visual.parts),"star ends with last beam span")
        end
        local connection=visual.connector
        if connection then
        local terminal=visual.parts[connection.terminal]
            or visual.tip and visual.tip.id==connection.terminal and visual.tip
        assert(terminal and not terminal.fx.hidden)
        same_phase(connection.fx,terminal.fx)
        local function endpoint(fx,length,sign)
            local angle=-math.rad(fx.rotation)
            return fx.x+sign*.5*length*fx.sx*math.cos(angle),
                fx.z+sign*.5*length*fx.sx*math.sin(angle)
        end
        local slices=terminal.fx._nw_beam_slices
        assert(#slices==micro_parts,"each logical span exports sixteen continuous micro quads")
        for micro=2,#slices do
            same_phase(slices[micro],slices[1])
            local ax,az=endpoint(slices[micro-1],micro_length,1)
            local bx,bz=endpoint(slices[micro],micro_length,-1)
            local angle=-math.rad(slices[micro].rotation or 0)
            assert((bx-ax)*math.cos(angle)+(bz-az)*math.sin(angle)<=.00001,
                "actual adjacent micro quads meet or overlap")
            near((bx-ax)*math.sin(angle)-(bz-az)*math.cos(angle),0)
        end
        local tx,tz=endpoint(slices[#slices],micro_length,1)
        local cx,cz=endpoint(connection.fx,80/150,-1)
        near(tx,cx);near(tz,cz);near(connection.fx.sy,terminal.fx.sy)
        near(connection.fx.colour[4],terminal.fx.colour[4])
        local hx,hz=endpoint(connection.fx,80/150,1)
        near(hx,x);near(hz,z)
        end
        local sample={kind=kind,now=now,x=x,y=shot._height:value(),z=z,fx={},terminal=connection and connection.terminal}
        local function capture_fx(part,role)
            if not part then return end
            for micro,fx in ipairs(part.fx._nw_beam_slices or {part.fx}) do
            sample.fx[#sample.fx+1]={role=role,id=(part.id or 0)*micro_parts+micro-1,span_id=part.id,micro=micro,bank=fx.bank,
                animation=fx.animation,time=fx.time,timeset=fx.timeset,
                x=fx.x,y=fx.y,z=fx.z,sx=fx.sx,sy=fx.sy,rotation=fx.rotation or 0,
                hidden=fx.hidden or false,finaloffset=fx.finaloffset,
                orientation=fx.orientation==ANIM_ORIENTATION.BillBoard and "BillBoard" or "OnGround",
                rate=fx.rate or 1,sortoffset=fx.sortoffset,
                alpha=fx.colour and fx.colour[4] or 1}
            end
        end
        for _,part in pairs(visual.parts) do capture_fx(part,"part") end
        capture_fx(visual.tip,"tip");capture_fx(visual.connector,"connector");capture_fx(visual.head,"head")
        _BEAM_TRACE(sample)
    end
    shot:Remove()
end
TheWorld.ismastersim=nil
