local Front=require("nw/beam_front")
local Path=require("nw/beam_path")
local function near(a,b)
    assert(math.abs(a-b)<.000001,tostring(a).." ~= "..tostring(b))
end
local function segment(id,x1,z1,x2,z2,radius)
    return {id=id,x1=x1,z1=z1,x2=x2,z2=z2,
        length=math.sqrt((x2-x1)^2+(z2-z1)^2),radius=radius or .12,width=1}
end
local function anchor(part)
    return {id=part.id,x=part.x2,z=part.z2,dx=part.x2-part.x1,
        dz=part.z2-part.z1,radius=part.radius}
end
local function copy(value)
    if type(value)~="table" then return value end
    local result={}
    for k,v in pairs(value) do result[k]=copy(v) end
    return result
end
local function unchanged(actual,before)
    assert(type(actual)==type(before))
    if type(actual)~="table" then assert(actual==before);return end
    for k,v in pairs(before) do unchanged(actual[k],v) end
    for k in pairs(actual) do assert(before[k]~=nil) end
end

-- Half a world unit behind a fresh snapshot; tolerate only small lateral
-- interpolation error and place the head on the path, not beside it.
local parts={[1]=segment(1,0,0,1,0)}
local a=anchor(parts[1])
local savedparts,saveda=copy(parts),copy(a)
local r=Front.resolve(parts,a,.5,.03,0)
assert(r and r.part==parts[1] and r.id==1)
near(r.x,.5);near(r.z,0);near(r.length,.5);near(r.clip,.5)
assert(Front.resolve(parts,a,1,0,0)==nil)
assert(Front.resolve(parts,a,1.2,0,0)==nil)
assert(Front.resolve(parts,a,.5,0,180)==nil,"real reverse travel keeps its tip")
assert(Front.resolve(parts,a,.5,0,90)==nil,"perpendicular heading is not forward")
assert(Front.resolve(parts,a,.5,.061,0)==nil,"reject lateral jumps")
assert(Front.resolve(parts,a,.5,0),"heading is optional")
r=Front.resolve(parts,a,0,0,0)
assert(r and r.length==0 and r.clip==1,"exact start is a valid empty terminal")
unchanged(parts,savedparts);unchanged(a,saveda)

-- Multiple newly confirmed records can precede the locally interpolated
-- carrier. The return identifies precisely which later IDs to hide.
parts={}
for id=1,8 do parts[id]=segment(id,(id-1)*.5,0,id*.5,0) end
a=anchor(parts[8])
savedparts,saveda=copy(parts),copy(a)
r=Front.resolve(parts,a,1.25,0,0)
assert(r and r.id==3 and r.part==parts[3])
near(r.length,.25);near(r.clip,.25)
r=Front.resolve(parts,a,0,0,0)
assert(r and r.id==1 and r.length==0,"continuous records remain searchable")
unchanged(parts,savedparts);unchanged(a,saveda)

-- Walk around a continuous right-angle corner only while the point is at or
-- behind the newer segment's start. Never skip its interior on a lateral miss.
parts={[1]=segment(1,0,0,1,0),[2]=segment(2,1,0,1,1)}
a=anchor(parts[2])
r=Front.resolve(parts,a,.75,0,-90)
assert(r and r.id==1);near(r.x,.75);near(r.z,0)
assert(Front.resolve(parts,a,.75,.3,-90)==nil)
r=Front.resolve(parts,a,1,0,-90)
assert(r and r.id==2 and r.length==0,"shared vertex chooses newer segment")

-- A self-crossing has two exact spatial matches. Choose the first match
-- reached backwards from the anchor, not the older crossing branch.
parts={[1]=segment(1,-.5,0,.5,0),[2]=segment(2,.5,0,.5,-.5),
    [3]=segment(3,.5,-.5,0,-.5),[4]=segment(4,0,-.5,0,.5)}
a=anchor(parts[4])
r=Front.resolve(parts,a,0,0,-90)
assert(r and r.id==4)
assert(Front.resolve(parts,a,.3,0,-90)==nil,"do not skip latest branch to older crossing")
parts[3]=nil
assert(Front.resolve(parts,a,0,-.7,-90)==nil,"missing ID ends the search")
parts[3]=segment(3,.5,-.5,.1,-.5)
assert(Front.resolve(parts,a,0,-.7,-90)==nil,"disconnected endpoints end the search")

-- Teleports and long winding routes cannot select a distant historical head,
-- even if a long segment itself straddles the shared search boundary.
local limit=Path.front_max_distance
parts={[1]=segment(1,0,0,limit+2,0)};a=anchor(parts[1])
assert(Front.resolve(parts,a,1.999,0,0)==nil)
r=Front.resolve(parts,a,2,0,0)
assert(r);near(r.clip,limit)
assert(Front.resolve(parts,a,-limit,0,0)==nil)
parts={[1]=segment(1,0,0,limit*.6,0),[2]=segment(2,limit*.6,0,limit*.6,limit*.6)};a=anchor(parts[2])
assert(Front.resolve(parts,a,limit*.1,0,-90)==nil,"limit follows path length, not straight-line distance")

-- At the maximum speed a normal two-frame interpolation lag exceeds four
-- units, but remains inside the snapshot window and its connected history.
local step=require("nw/spell_limits").max_speed/30
parts={}
for id=1,3 do parts[id]=segment(id,(id-1)*step,0,id*step,0) end
a=anchor(parts[3]);r=Front.resolve(parts,a,step,0,0)
assert(r and r.id==2 and r.length==0,"two-frame lag resolves the newest shared endpoint")

-- Radius-dependent tolerance has a small floor for thin beams.
parts={[1]=segment(1,0,0,1,0,.01)};a=anchor(parts[1])
assert(Front.resolve(parts,a,.5,.019,0))
assert(Front.resolve(parts,a,.5,.021,0)==nil)

-- Rotation invariance also checks DST's negative-Z heading convention.
for _,heading in ipairs({-135,-90,-45,0,45,90,135,180,270}) do
    local theta=heading*math.pi/180
    local dx,dz=math.cos(theta),-math.sin(theta)
    parts={[1]=segment(1,3,7,3+dx,7+dz)};a=anchor(parts[1])
    r=Front.resolve(parts,a,3+.5*dx,7+.5*dz,heading)
    assert(r);near(r.length,.5);near(r.clip,.5)
    assert(Front.resolve(parts,a,3+.5*dx,7+.5*dz,heading+180)==nil)
end

-- Invalid/stale input returns nil without touching the records or throwing.
parts={[1]=segment(1,0,0,1,0)};a=anchor(parts[1])
assert(Front.resolve(nil,a,.5,0,0)==nil)
assert(Front.resolve(parts,nil,.5,0,0)==nil)
for _,field in ipairs({"id","x","z","dx","dz","radius"}) do
    local invalid=copy(a);invalid[field]=0/0
    assert(Front.resolve(parts,invalid,.5,0,0)==nil)
end
for _,bad in ipairs({math.huge,-math.huge,"bad"}) do
    assert(Front.resolve(parts,a,bad,0,0)==nil)
    assert(Front.resolve(parts,a,.5,0,bad)==nil)
end
local invalid=copy(a);invalid.dx=0
assert(Front.resolve(parts,invalid,.5,0,0)==nil)
invalid=copy(a);invalid.dx=-1
assert(Front.resolve(parts,invalid,1.5,0,180)==nil)
invalid=copy(a);invalid.x=1.1
assert(Front.resolve(parts,invalid,.5,0,0)==nil)
for _,field in ipairs({"x1","z1","x2","z2","length","radius"}) do
    local badparts=copy(parts);badparts[1][field]=math.huge
    assert(Front.resolve(badparts,a,.5,0,0)==nil)
end
local badparts=copy(parts);badparts[1].length=0
assert(Front.resolve(badparts,a,.5,0,0)==nil)
badparts=copy(parts);badparts[1].length=2
assert(Front.resolve(badparts,a,.5,0,0)==nil)
assert(Front.resolve({},a,.5,0,0)==nil)

print("beam_front: interpolation lag, turns, crossings, bounds and immutability passed")
