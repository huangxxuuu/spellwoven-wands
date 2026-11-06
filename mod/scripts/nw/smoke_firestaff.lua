-- Reference measurement against the installed game's unmodified firestaff.
local M={}
function M.run(x,z,done)
    local player=SpawnPrefab("wilson")
    player.userid=""
    player:AddComponent("playeractionpicker");player:AddComponent("playercontroller")
    local pc=player.components.playercontroller;pc:Enable(true)
    player.Transform:SetPosition(x,0,z)
    local staff=SpawnPrefab("firestaff")
    local target=SpawnPrefab("nw_target_dummy");target.Transform:SetPosition(x+4,0,z)
    player.components.inventory:GiveItem(staff);player.components.inventory:Equip(staff)
    local shots,elapsed,projectile=0
    local start=GetTime()
    staff:ListenForEvent("weapononprojectilelaunched",function(_,data)
        shots=shots+1;elapsed=GetTime()-start;projectile=data.projectile
    end)
    player.sg:GoToState("idle")
    pc:DoAction(BufferedAction(player,target,ACTIONS.ATTACK,staff))
    assert(player.sg.currentstate.name=="attack","NW_FIRESTAFF: native attack not started")
    assert(math.abs(player.sg.statemem.projectiledelay-7*FRAMES)<.0001,"NW_FIRESTAFF: reference timing changed")
    TheWorld:DoTaskInTime(9*FRAMES,function()
        assert(shots==1 and elapsed>=6*FRAMES and elapsed<=8*FRAMES+.001,"NW_FIRESTAFF: reference launch mismatch")
        pc:OnRemoteDirectWalking(1,0);pc:DoDirectWalking(FRAMES)
        TheWorld:DoTaskInTime(2*FRAMES,function()
            assert(player.sg.currentstate.name~="attack" and shots==1,"NW_FIRESTAFF: recovery did not cancel")
            print("NW_FIRESTAFF_PASS: reference launch frames",elapsed/FRAMES,"recovery interrupted, one shot retained")
            if projectile and projectile:IsValid() then projectile:Remove() end
            staff:Remove();target:Remove();player:Remove()
            done()
        end)
    end)
end
return M
