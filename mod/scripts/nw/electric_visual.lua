-- One replicated strike anchor; all native-art arc pieces live on the client.
local M={pixels_per_unit=150,arc_pixels=112,directions=256}
local TAU=2*math.pi
local HEIGHT={tiny=.3,small=.75,med=1.25,large=2}

function M.target_height(target)
    local _,y=target.Transform:GetWorldPosition()
    local size,height
    if GetCombatFxSize then _,size,height=GetCombatFxSize(target) end
    return y+(HEIGHT[size] or .75)*(height=="low" and .5 or height=="high" and 1.4 or 1)
end

function M.project(dx,dy,dz,heading,pitch)
    local c,s=math.cos(heading),math.sin(heading)
    return dz*c-dx*s,(dx*c+dz*s)*math.sin(pitch)-dy*math.cos(pitch)
end

function M.span(dx,dy,dz,lift,heading,pitch)
    -- A billboard cloud's artwork is displaced in screen pixels, unlike a
    -- genuine Transform height. Undo pitch only for that visual displacement.
    local raised=(lift or 0)/math.max(.05,math.cos(pitch))
    local sx,sy=M.project(dx,dy-raised,dz,heading,pitch)
    local length=math.sqrt(sx*sx+sy*sy)
    if length<.001 then return 0,0,0,raised end
    local count=math.max(1,math.ceil(length/1.05))
    local direction=math.floor(math.atan2(sy,sx)/TAU*M.directions+.5)%M.directions
    -- Small overlap hides endpoint taper and direction quantization.
    return count,length/count*M.pixels_per_unit/M.arc_pixels*1.08,direction,raised
end

local function local_fx(parent,bank,build)
    local fx=CreateEntity()
    fx.entity:AddTransform();fx.entity:AddAnimState();fx.entity:SetCanSleep(false)
    fx.entity:SetParent(parent.entity)
    fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
    fx.AnimState:SetBank(bank);fx.AnimState:SetBuild(build)
    fx.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
    fx.AnimState:SetLightOverride(1);fx.AnimState:SetFinalOffset(3)
    fx.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
    return fx
end

function M.attach(inst)
    if TheNet:IsDedicated() then return end
    local pieces,contact={},nil
    local last_target,last_anim
    local born=GetTime()
    local function refresh()
        local camera=TheCamera
        local heading=(camera and camera.heading or 0)*math.pi/180
        local pitch=(camera and camera.pitch or 35)*math.pi/180
        local dx,dy,dz=inst._dx:value(),inst._dy:value(),inst._dz:value()
        local count,scale,direction,raised=M.span(dx,dy,dz,inst._lift:value(),heading,pitch)
        local age=math.max(0,GetTime()-born)
        for i=#pieces,count+1,-1 do
            if pieces[i]:IsValid() then pieces[i]:Remove() end
            pieces[i]=nil
        end
        for i=1,count do
            local piece=pieces[i]
            if not piece then
                piece=local_fx(inst,"nw_electric_arc","shock_fx");pieces[i]=piece
            end
            local t=(i-.5)/count
            piece.Transform:SetPosition(dx*t,raised+(dy-raised)*t,dz*t)
            piece.AnimState:SetScale(scale,scale)
            if piece._nw_direction~=direction then
                piece._nw_direction=direction
                piece.AnimState:PlayAnimation("arc_"..direction,true)
                piece.AnimState:SetTime((age+(i%4)/30)%(4/30))
            end
            -- Preserve the native white electricity and fade only at the end.
            piece.AnimState:SetMultColour(1,1,1,math.min(1,math.max(0,(.23-age)/.07)))
        end
        local target,anim=inst._contact:value(),inst._shockanim:value()
        if target~=last_target or anim~=last_anim then
            if contact and contact:IsValid() then contact:Remove() end
            contact=nil;last_target,last_anim=target,anim
            if target and target:IsValid() and anim~="" then
                contact=local_fx(target,"shock_fx","shock_fx")
                -- Native shock sizes already account for creature size. Do not
                -- multiply them a second time by a scaled parent Transform.
                local sx,sy,sz=target.Transform:GetScale()
                contact.Transform:SetScale(1/sx,1/sy,1/sz)
                contact.AnimState:PlayAnimation(anim)
            end
        end
    end
    inst:ListenForEvent("nw_arcdirty",refresh)
    inst:DoTaskInTime(0,refresh)
    local task=inst:DoPeriodicTask(1/30,refresh)
    inst:ListenForEvent("onremove",function()
        task:Cancel()
        for _,piece in ipairs(pieces) do if piece:IsValid() then piece:Remove() end end
        if contact and contact:IsValid() then contact:Remove() end
    end)
    return refresh
end

return M
