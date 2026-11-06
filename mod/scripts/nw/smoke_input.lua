-- Exercise the actual native controller, BufferedAction and SGwilson attack.
local M={}
function M.run(x,z,done)
    local player=SpawnPrefab("wilson")
    -- An unowned spawned character has no input components until OnSetOwner;
    -- install the real components explicitly for this isolated fixture.
    player.userid=player.userid or ""
    player:AddComponent("playeractionpicker")
    player:AddComponent("playercontroller")
    player.components.playercontroller:Enable(true)
    player.Transform:SetPosition(x,0,z)
    local wand=SpawnPrefab("nw_wand")
    local cmp=wand.components.nw_wand
    cmp:InitializePrototype();cmp.data.stats.mana_regen=8
    player.components.inventory:GiveItem(wand);player.components.inventory:Equip(wand)
    local pc=player.components.playercontroller
    local count,talks,windups=0,0,0
    local started,launched
    player:ListenForEvent("newstate",function()
        if player.sg.currentstate.name=="attack" then windups=windups+1 end
    end)
    local cast=cmp.Cast
    cmp.Cast=function(self,...)
        local before=player.components.sanity.current
        local ok,err=cast(self,...)
        if ok then
            assert(math.abs(player.components.sanity.current-math.max(0,before-.25))<.00001,"NW_NATIVE: SAN cost mismatch")
            count=count+1;launched=GetTime()-started
        end
        return ok,err
    end
    player.components.talker.Say=function() talks=talks+1 end
    local function press(cached)
        local px,_,pz=player.Transform:GetWorldPosition()
        local pos=Vector3(px+4,0,pz)
        local act
        for _,candidate in ipairs(player.components.playeractionpicker:GetPointActions(pos,wand,true)) do
            if candidate.action==ACTIONS.NW_CAST then act=candidate;break end
        end
        if cached then
            assert(act==nil,"NW_NATIVE: unavailable cast still offered by picker")
            act=BufferedAction(player,nil,ACTIONS.NW_CAST,wand,pos)
        else
            assert(act,"NW_NATIVE: component action missing from native picker")
        end
        started=GetTime()
        pc:DoAction(act)
        return act
    end
    assert(ACTIONS.NW_CAST.invalid_hold_action and ACTIONS.NW_CAST.silent_fail)
    player.sg:GoToState("idle")
    press()
    assert(player.sg.currentstate.name=="attack","NW_NATIVE: not using native attack")
    assert(math.abs(player.sg.statemem.projectiledelay-7*FRAMES)<.0001,"NW_NATIVE: not firestaff timing")
    assert(pc.lastheldaction==nil and pc.actionholdtime==nil,"NW_NATIVE: action allowed hold repeat")
    TheWorld:DoTaskInTime(FRAMES,function()
        pc:OnRemoteDirectWalking(1,0);pc:DoDirectWalking(FRAMES)
        -- Stategraph locomote events are processed on the next engine update.
        TheWorld:DoTaskInTime(2*FRAMES,function()
            assert(player.sg.currentstate.name~="attack","NW_NATIVE: movement did not cancel wind-up")
        end)
        TheWorld:DoTaskInTime(.5,function()
            assert(count==0 and cmp.data.runtime.mana==120,"NW_NATIVE: interrupted cast consumed mana or fired")
            pc:OnRemoteStopWalking();pc:DoDirectWalking(FRAMES)
            player.sg:GoToState("idle")
            press()
            assert(player.sg.currentstate.name=="attack","NW_NATIVE: stationary click rejected")
            TheWorld:DoTaskInTime(9*FRAMES,function()
                assert(count==1 and launched>=6*FRAMES and launched<=8*FRAMES+.001,"NW_NATIVE: launch timing mismatch")
                -- Cut off the recovery animation, not an uncommitted wind-up.
                pc:OnRemoteDirectWalking(1,0);pc:DoDirectWalking(FRAMES)
                TheWorld:DoTaskInTime(2*FRAMES,function()
                    assert(player.sg.currentstate.name~="attack" and count==1,"NW_NATIVE: recovery movement lost or repeated shot")
                end)
            end)
            TheWorld:DoTaskInTime(.5,function()
                assert(count==1,"NW_NATIVE: single click did not fire exactly once")
                print("NW_CAST_TIMING_PASS: launch frames",launched/FRAMES,"recovery interrupted, one shot retained")
                cmp.data.runtime.remaining_cast=0;cmp.data.runtime.remaining_recharge=0
                for i=1,20 do pc:RepeatHeldAction() end
                TheWorld:DoTaskInTime(.5,function()
                    assert(count==1,"NW_NATIVE: holding repeated after cooldown")
                    cmp.data.runtime.mana=0;cmp.last_time=GetTime();cmp:Sync()
                    local before=windups
                    press(true)
                    assert(windups==before,"NW_NATIVE: dry click started wind-up")
                    TheWorld:DoTaskInTime(.8,function()
                        for i=1,20 do pc:RepeatHeldAction() end
                        assert(count==1 and talks==0,"NW_NATIVE: rejected click queued or spoke")
                        wand:Remove();player:Remove()
                        TheWorld:DoTaskInTime(2*FRAMES,function()
                            assert(require("nw/executor").stats()==0,"NW_NATIVE: projectile leak")
                            print("NW_NATIVE_PASS: native attack + early cancel without spend + recovery cancel keeps shot; single click; no held repeat; dry click silent and not queued")
                            done()
                        end)
                    end)
                end)
            end)
        end)
    end)
end
return M
