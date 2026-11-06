local M={}
function M.run()
    local Cleanup=require("nw/permanent_motion_cleanup")
    local Limits=require("nw/spell_limits")
    assert(Limits.permanent_motion_cleanup and not Limits.boundary_cleanup,"NW_CLEANUP: settings")
    local owner=SpawnPrefab("wilson")
    owner.entity:SetCanSleep(false)
    owner.components.health:SetInvincible(true)
    owner.components.combat.CanTarget=function() return false end
    local w,h=TheWorld.Map:GetSize()
    local x=w*TILE_SCALE/2+200
    local launchx,launchz
    for tx=w-1,0,-1 do
        for tz=1,h-2 do
            local px,_,pz=TheWorld.Map:GetTileCenterPoint(tx,tz)
            if TheWorld.Map:IsPassableAtPoint(px,0,pz,true) then launchx,launchz=px,pz;break end
        end
        if launchx then break end
    end
    assert(launchx,"NW_CLEANUP: valid launch tile")
    local items,probes={},{}
    local function spawn()
        local p=require("nw/util").copy(require("nw/definitions").spells.payload_egg)
        p.flags={};p.speed=6;p.field_drive=true
        local e=SpawnPrefab("nw_payload_egg")
        e:Launch(owner,p,launchx,launchz,1,0,function() end,1.4)
        e.Physics:Teleport(x,0,#items*8)
        Cleanup.sync(e)
        items[#items+1]=e;probes[#probes+1]=e._nw_cleanup_state.probe
        return e
    end
    for i=1,20 do spawn() end
    TheWorld:DoTaskInTime(2,function()
        for _,e in ipairs(items) do
            local state=e._nw_cleanup_state
            print("NW_CLEANUP_NATIVE:",e:IsAsleep(),state.probe:IsAsleep(),state.probe.sleepstatepending,e.Transform:GetWorldPosition())
            assert(not e:IsAsleep() and state.probe:IsAsleep() and not state.probe.sleepstatepending,"NW_CLEANUP: native sleep classification")
            assert(e:GetPosition().x>x+5,"NW_CLEANUP: spell keeps moving")
            assert(Cleanup.elapsed(e)>1,"NW_CLEANUP: below-threshold timer")
            -- Accelerated fixture: equivalent to a saved 16-minute absence.
            state.absent=Cleanup.timeout;state.updated_at=GetTime()
        end
        TheWorld:DoTaskInTime(1.2,function()
            assert(TheWorld._nw_permanent_motion_cleanup.count==20,"NW_CLEANUP: threshold removed entities early")
            local fresh=spawn()
            TheWorld:DoTaskInTime(1.2,function()
                for i=1,20 do
                    assert(not items[i]:IsValid() and not probes[i]:IsValid(),"NW_CLEANUP: expired entity/probe survived")
                end
                assert(fresh:IsValid() and TheWorld._nw_permanent_motion_cleanup.count==1,"NW_CLEANUP: fresh entity removed")
                fresh:Remove();owner:Remove()
                assert(not probes[21]:IsValid() and not TheWorld._nw_permanent_motion_cleanup.task,"NW_CLEANUP: idle resources survived")
                require("nw/smoke_motion_rules").run(function()
                    print("NW_CLEANUP_PASS: native sleep, independent cleanup gates, motion rules and triggerer attribution")
                end,launchx,launchz,x)
            end)
        end)
    end)
end
return M
