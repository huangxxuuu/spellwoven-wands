local M={}
local active
local task
local world
local function update()
    if not TheCamera then return end
    local camera=TheCamera.heading*DEGREES
    local pitch=math.sin(TheCamera.pitch*DEGREES)
    for i=#active,1,-1 do
        local inst=active[i]
        if not inst:IsValid() then
            active[i]=active[#active];active[#active]=nil
        else
            local rel=-inst.Transform:GetRotation()*DEGREES-camera
            if rel~=inst._nw_view or pitch~=inst._nw_pitch then
                inst._nw_view,inst._nw_pitch=rel,pitch
                local heading=math.atan2(math.cos(rel)*pitch,math.sin(rel))
                local bin=(math.floor(heading/(2*math.pi)*32+.5)+(inst._nw_art_turn or 0))%32
                if bin~=inst._nw_dir then
                    inst._nw_dir=bin;inst._visual.AnimState:PlayAnimation((inst._nw_dir_prefix or "dir_")..bin,true)
                end
            end
        end
    end
    if #active==0 then task:Cancel();task=nil end
end
local drawn={gust=true,slime=true,heal_bolt=true,heavy=true,land_hook=true,
    arrow=true,fire=true,frost=true,scatter=true,spore_ball=true,flint_lance=true,grow_orb=true,star_vortex=true,glass_disc=true,tri_electric=true,end_beam=true,soundwave=true,bee_swarm=true,
    trident=true,fishingrod=true,farm_hoe=true,orange_bolt=true,yoth_lance=true}
-- A screen-facing painted body rotates within its own plane. Native physics
-- owns the world heading; a reversal never swaps entities or reflects the art.
function M.attach(inst,id,turn)
    inst._nw_art_turn=turn or 0
    inst._nw_dir_prefix=id=="farm_hoe" and "hoe_dir_" or nil
    local visual=inst._visual
    local anim=visual.AnimState
    anim:SetOrientation(ANIM_ORIENTATION.BillBoard)
    anim:SetBank("nw_spell_world");anim:SetBuild("nw_spell_world")
    if require("nw/arsenal").notes[id] then id="soundwave" elseif id=="fireflies" then id="bee_swarm" end
    if id=="oceanfishingrod" then
        inst._nw_dir_prefix="hook_dir_"
        anim:OverrideSymbol("body","oceanfishing_hook","hook")
        anim:OverrideSymbol("hook_line","oceanfishing_hook","line_01")
        visual.Transform:SetScale(2,2,2)
    elseif drawn[id] then anim:OverrideSymbol("body","nw_spell_world","body_"..id)
    else anim:OverrideSymbol("body","nw_objects",id=="spore_sentry" and "garden_thorn" or "nw_spell_"..id) end
    anim:PlayAnimation((inst._nw_dir_prefix or "dir_")..inst._nw_art_turn,true)
    if world~=TheWorld then active={};task=nil;world=TheWorld end
    active[#active+1]=inst
    if not task then task=TheWorld:DoPeriodicTask(FRAMES,update,0) end
end
return M
