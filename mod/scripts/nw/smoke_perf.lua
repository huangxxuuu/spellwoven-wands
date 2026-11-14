local M={}
function M.run(x,z,done)
    local Perf=require("nw/perf")
    local owner=SpawnPrefab("nw_target_dummy");owner.Transform:SetPosition(x,0,z)
    local wand=SpawnPrefab("nw_wand");owner:AddComponent("inventory")
    owner.components.inventory:GiveItem(wand);owner.components.inventory:Equip(wand)
    local cmp=wand.components.nw_wand;cmp:InitializePrototype()
    local Compiler=require("nw/compiler");local compile=Compiler.compile;local calls=0
    Compiler.compile=function(...) calls=calls+1;return compile(...) end
    for i=1,1000 do assert(cmp:CanCast(owner)) end
    Compiler.compile=compile
    assert(calls<=1,"NW_PERF: unchanged readiness repeatedly compiled")
    print("NW_PERF_READY: 1000 probes, compiler calls",calls)
    local clutter={}
    for i=1,160 do
        local e=CreateEntity();e.entity:AddTransform();e.persists=false
        e.Transform:SetPosition(x+(i%20)*.2,0,z+(math.floor(i/20)-4)*.2)
        clutter[#clutter+1]=e
    end
    local counts={1,4,9,24,9};local index=0
    local function run()
        index=index+1
        local n=counts[index]
        if not n then
            for _,e in ipairs(clutter) do e:Remove() end
            wand:Remove();owner:Remove();done();return
        end
        local shots={};Perf.begin()
        for i=1,n do
            local p=SpawnPrefab("nw_projectile");shots[#shots+1]=p
            local angle=index==5 and (-10+20*(i-1)/(n-1))*DEGREES or 0
            p:Launch(owner,{id="heavy",damage=1,speed=7,lifetime=.5},x,z,math.cos(angle),math.sin(angle),function() end,1.5)
        end
        TheWorld:DoTaskInTime(.7,function()
            for _,p in ipairs(shots) do assert(not p:IsValid(),"NW_PERF: projectile leaked") end
            local s=Perf.finish()
            assert(s.position_writes==0 and s.queries<=s.steps,"NW_PERF: repeated position writes/query regression")
            if n>1 then assert(s.queries<s.steps,"NW_PERF: grouped bullets did not share queries") end
            print("NW_PERF_SHOTS:",n,index==5 and "fan" or "parallel","steps",s.steps,"queries",s.queries,"candidates",s.candidates,"visits",s.visits,"position_writes",s.position_writes)
            run()
        end)
    end
    run()
end
return M
