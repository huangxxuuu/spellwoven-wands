local M={}
function M.applies(p)
    return p and (p.id=="payload_egg" or p.id=="crystal_mine" or p.id=="sleep_crystal" or p.id=="gunpowder")
end
function M.surface(x,z)
    local map=TheWorld.Map
    if not map or not map.IsOceanAtPoint then return "land" end
    local boat=map.GetPlatformAtPoint and map:GetPlatformAtPoint(x,z)
    if boat then return boat end
    return map:IsOceanAtPoint(x,0,z) and "ocean" or "land"
end
function M.sink(inst)
    local x,_,z=inst.Transform:GetWorldPosition()
    if M.surface(x,z)~="ocean" then return false end
    -- Native splash, then remove without breaking/releasing a stored payload.
    local splash=SpawnPrefab("splash_sink")
    if splash then splash.Transform:SetPosition(x,0,z) end
    inst:Remove()
    return true
end
function M.clip(s,x,z,nx,nz)
    if not M.applies(s.p) then return end
    local surface=M.surface(x,z)
    local n=math.max(1,math.ceil(math.sqrt((nx-x)^2+(nz-z)^2)/.2))
    for i=1,n do
        local t=i/n
        if M.surface(x+(nx-x)*t,z+(nz-z)*t)~=surface then
            local lo,hi=(i-1)/n,t
            for _=1,10 do
                local mid=(lo+hi)/2
                if M.surface(x+(nx-x)*mid,z+(nz-z)*mid)==surface then lo=mid else hi=mid end
            end
            return math.max(0,lo-.001/math.max(.001,math.sqrt((nx-x)^2+(nz-z)^2)))
        end
    end
end
return M
