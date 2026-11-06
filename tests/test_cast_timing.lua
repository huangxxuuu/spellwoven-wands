FRAMES=1/30;ACTIONS={NW_CAST={},ATTACK={}}
local T=require("nw/cast_timing")
for _,peer in ipairs({"server","client"}) do
    local calls=0
    local sg={states={attack={onenter=function(inst)
        calls=calls+1
        inst.sg.statemem={projectiledelay=inst.original_delay}
    end}}}
    T.install(sg)
    local p={sg={currentstate={name="attack"},HasStateTag=function(self) return self.about end,about=true}}
    function p:GetBufferedAction() return self.act end
    p.act={action=ACTIONS.NW_CAST};sg.states.attack.onenter(p)
    assert(math.abs(p.sg.statemem.projectiledelay-7*FRAMES)<1e-8)
    p.act={action=ACTIONS.ATTACK};p.original_delay=.4;sg.states.attack.onenter(p)
    assert(p.sg.statemem.projectiledelay==.4,"changed another weapon's timing")
    p.act={action=ACTIONS.NW_CAST};p.original_delay=nil;p.sg.about=false;sg.states.attack.onenter(p)
    assert(p.sg.statemem.projectiledelay==nil,"restarted a rejected attack")
    p.sg.about=true;p.sg.currentstate.name="idle";sg.states.attack.onenter(p)
    assert(p.sg.statemem.projectiledelay==nil)
    assert(calls==4,"native enter was skipped or duplicated")
end
print("cast timing: same native projectile timer on both peers; other actions and rejected states untouched")
