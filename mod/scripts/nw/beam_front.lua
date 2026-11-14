local C=require("nw/constants/visuals/beam_front")
local M={}
local MAX_BACKTRACK=require("nw/beam_path").front_max_distance
local JOIN_EPS=C.join_eps
local EPS=.000001

local function finite(n)
    return type(n)=="number" and n==n and math.abs(n)<math.huge
end

local function geometry(part)
    if type(part)~="table" or not finite(part.x1) or not finite(part.z1)
        or not finite(part.x2) or not finite(part.z2)
        or not finite(part.length) or part.length<=EPS
        or not finite(part.radius) or part.radius<=0 then return end
    local dx,dz=part.x2-part.x1,part.z2-part.z1
    local length=math.sqrt(dx*dx+dz*dz)
    if not finite(length) or length<=EPS
        or math.abs(length-part.length)>JOIN_EPS then return end
    return dx/length,dz/length,length
end

function M.resolve(parts,anchor,x,z,heading)
    if type(parts)~="table" or type(anchor)~="table"
        or not finite(x) or not finite(z)
        or not finite(anchor.id) or anchor.id<1 or anchor.id%1~=0
        or not finite(anchor.x) or not finite(anchor.z)
        or not finite(anchor.dx) or not finite(anchor.dz)
        or not finite(anchor.radius) or anchor.radius<=0 then return end
    local tangent=math.sqrt(anchor.dx*anchor.dx+anchor.dz*anchor.dz)
    if not finite(tangent) or tangent<=EPS then return end
    local tx,tz=anchor.dx/tangent,anchor.dz/tangent
    local behind=(x-anchor.x)*tx+(z-anchor.z)*tz
    if behind>=-EPS then return end
    if heading~=nil then
        if not finite(heading) then return end
        local radians=heading*math.pi/180
        if math.cos(radians)*tx-math.sin(radians)*tz<=EPS then return end
    end

    local endx,endz=anchor.x,anchor.z
    local travelled=0
    for id=anchor.id,1,-1 do
        local part=parts[id]
        local dx,dz,length=geometry(part)
        if not dx or part.id~=nil and part.id~=id
            or math.abs(part.x2-endx)>JOIN_EPS
            or math.abs(part.z2-endz)>JOIN_EPS then return end
        local dot=dx*tx+dz*tz
        if id==anchor.id and dot<1-EPS or dot<-EPS then return end
        local along=(x-part.x1)*dx+(z-part.z1)*dz
        local lateral=math.abs((x-part.x1)*dz-(z-part.z1)*dx)
        local tolerance=math.max(C.minimum_lateral_tolerance,part.radius*C.radius_tolerance)
        if along>=-JOIN_EPS and along<=length+JOIN_EPS and lateral<=tolerance then
            local fraction=math.max(0,math.min(1,along/length))
            local visible=part.length*fraction
            local clip=part.length-visible
            if travelled+length*(1-fraction)>MAX_BACKTRACK+EPS then return end
            return {part=part,id=id,x=part.x1+(part.x2-part.x1)*fraction,
                z=part.z1+(part.z2-part.z1)*fraction,length=visible,clip=clip}
        end
        if along>JOIN_EPS then return end
        travelled=travelled+length
        if travelled>MAX_BACKTRACK+EPS then return end
        endx,endz=part.x1,part.z1
        tx,tz=dx,dz
    end
end

return M
