-- Run only in the isolated fresh balanced-world server suite.
local M={}
function M.run()
    local Balance=require("nw/balance")
    local Generator=require("nw/generator")
    local Compiler=require("nw/compiler")
    local Damage=require("nw/balance_damage")
    assert(TheWorld.ismastersim and Balance.is_balanced(),"NW_BALANCE: balanced server required")
    TheWorld:PushEvent("ms_setclocksegs",{day=16,dusk=0,night=0})
    local x,z=0,0
    for _,e in pairs(Ents) do
        if e:HasTag("multiplayer_portal") then
            local px,_,pz=e.Transform:GetWorldPosition();x,z=px,pz;break
        end
    end
    local made={}
    local function spawn(name)
        local e=assert(SpawnPrefab(name));made[#made+1]=e
        e.Transform:SetPosition(x,0,z);e.entity:SetCanSleep(false)
        return e
    end
    local function near(a,b,label)
        assert(math.abs(a-b)<.001,"NW_BALANCE: "..label.." "..tostring(a).." ~= "..tostring(b))
    end
    local player=spawn("wilson")
    local sanity,hunger,health=player.components.sanity,player.components.hunger,player.components.health
    local wand=spawn("nw_wand")
    local cmp=wand.components.nw_wand
    cmp:InitializeNew(0,"balance-smoke")
    near(cmp.data.stats.recharge,2.1,"new starter recharge")
    near(cmp.data.stats.sanity_conversion,20,"saved base conversion")
    near(Generator.sanity_conversion_for(cmp.data.stats),10,"world conversion")
    player.components.inventory:GiveItem(wand)
    player.components.inventory:Equip(wand)
    local function prepare(san,food)
        sanity:SetPercent(san/sanity.max)
        hunger:SetPercent(food/hunger.max)
        cmp.data.cards={{card_uid="balance-smoke-heavy",spell_id="heavy"},false}
        cmp.data.runtime=Compiler.initial(cmp.data.cards,cmp.data.stats,123)
        cmp.data.config_revision=cmp.data.config_revision+1
        cmp.last_time=GetTime()
    end
    local function cast()
        local ok,why=cmp:Cast(player,Vector3(x+4,0,z));assert(ok,"NW_BALANCE: cast "..tostring(why))
        -- These checks concern launch fees; remove outgoing shots before they
        -- reach unrelated fresh-world entities or the later damage fixture.
        local shots={}
        for _,e in pairs(Ents) do
            if e.prefab=="nw_projectile" and e._shot and e._shot.owner==player then shots[#shots+1]=e end
        end
        for _,e in ipairs(shots) do e:Remove() end
    end
    local before_health=health.currenthealth
    prepare(1,10);cast()
    near(sanity.current,0,"SAN exhausted first");near(hunger.current,9.6,"hunger covers SAN deficit")
    prepare(10,10);cast()
    near(sanity.current,8.2,"sufficient SAN fee");near(hunger.current,10,"sufficient SAN preserves hunger")
    prepare(0,.1);cast();near(hunger.current,0,"hunger clamps to zero")
    prepare(0,0);cast()
    near(health.currenthealth,before_health,"no immediate health fee")
    -- A save from the old generation keeps its raw recharge and conversion.
    cmp.data.generator_version=2;cmp.data.stats.recharge=1.4
    local copy=SpawnSaveRecord(wand:GetSaveRecord());made[#made+1]=copy
    local restored=copy.components.nw_wand
    near(restored.data.stats.recharge,1.4,"old recharge preserved")
    near(restored.data.stats.sanity_conversion,20,"old base conversion preserved")
    near(Generator.sanity_conversion_for(restored.data.stats),10,"old wand current-world fee")
    local saved=restored:OnSave();restored:OnLoad(saved)
    near(restored.data.stats.sanity_conversion,20,"conversion does not compound on load")
    -- Cards may cancel even the new starter's full recharge; no cast multiplier
    -- or positive minimum may reintroduce a wait at compilation time.
    local data=Generator.starter()
    data.stats.capacity=8;data.stats.draw_count=1
    data.cards={}
    for i=1,7 do data.cards[i]={card_uid="balance-recharge-"..i,spell_id="recharge_down"} end
    data.cards[8]={card_uid="balance-recharge-8",spell_id="spark"}
    data.runtime=Compiler.initial(data.cards,data.stats,123)
    local plan=assert(Compiler.compile(data))
    near(plan.next_state.remaining_recharge,0,"cards reach zero recharge")
    for tier=1,4 do
        local generated=Generator.generate(1234,tier,"sprout")
        local lo,hi=require("nw/wand_generation").distribution(tier,"sprout","recharge")
        assert(generated.stats.recharge>=lo and generated.stats.recharge<=hi,"NW_BALANCE: generated recharge range")
    end
    -- Exercise real combat/health with the same cast identity and another root.
    local target=spawn("nw_target_dummy")
    target.Transform:SetPosition(x+8,0,z)
    target.components.health:SetMaxHealth(10000)
    local root=assert(Damage.root())
    local parameters={_nw_root=root}
    for n=1,10 do
        local before=target.components.health.currenthealth
        Damage.attack(parameters,player,target,100)
        near(before-target.components.health.currenthealth,20+80*.9^(n-1),"same-cast hit "..n)
    end
    local before=target.components.health.currenthealth
    Damage.attack({_nw_root=Damage.root()},player,target,100)
    near(before-target.components.health.currenthealth,100,"new cast resets damage")
    local other=spawn("nw_target_dummy")
    other.Transform:SetPosition(x+10,0,z)
    before=other.components.health.currenthealth
    Damage.attack(parameters,player,other,100)
    near(before-other.components.health.currenthealth,100,"other target has independent hit count")
    print("NW_BALANCE_DAMAGE: hits=100/92/84.8 floor=20 new_cast=100")
    sanity:SetPercent(1);hunger:SetPercent(1)
    TheWorld:DoTaskInTime(10.1,function()
        local before=target.components.health.currenthealth
        Damage.attack(parameters,player,target,100)
        near(before-target.components.health.currenthealth,100,"same root resets after ten seconds without a hit")
        for i=#made,1,-1 do if made[i]:IsValid() then made[i]:Remove() end end
        print("NW_BALANCE_PASS: native SAN/hunger fees, zero-resource casting, unchanged health, generated recharge, zero card recharge, legacy save/load, repeated-hit falloff, target independence, new-cast and ten-second resets")
    end)
end
return M
