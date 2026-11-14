local Scenarios=require("nw/test_scenarios")
local Kit=require("nw/spellkit")
local M={}
local byid={};for _,s in ipairs(Scenarios) do byid[s.id]=s end
local report=require("nw/dev_output").report
function M.help()
    local lines={"nw_testscene(\"all\")：全部场景；nw_testscene(\"duo\")：双人套装（A/B 分箱）；也可只生成一组："}
    for _,s in ipairs(Scenarios) do lines[#lines+1]='nw_testscene("'..s.id..'")  '..s.name end
    lines[#lines+1]='nw_testcleanup(20) / nw_testcleanup(1)：清理门槛测试用永久追踪卵。'
    local text=table.concat(lines,"\n");report(text);return text
end
local function point(x,z,used)
    for ring=0,5 do for i=1,(ring==0 and 1 or 16) do
        local angle=i*math.pi/8
        local px,pz=x+ring*2*math.cos(angle),z+ring*2*math.sin(angle)
        local clear=TheWorld.Map:IsPassableAtPoint(px,0,pz) and not TheWorld.Map:IsOceanTileAtPoint(px,0,pz)
        for _,p in ipairs(used) do if (px-p.x)^2+(pz-p.z)^2<6.25 then clear=false;break end end
        if clear and #TheSim:FindEntities(px,0,pz,1.5,nil,{"INLIMBO","FX"},{"structure","tree","boulder","wall","_combat"})==0 then
            local p={x=px,z=pz};used[#used+1]=p;return p
        end
    end end
end
local function named(e,name)
    if not e.components.named then e:AddComponent("named") end
    e.components.named:SetName(name)
end
local function supply(row)
    if row.wand then
        local w=assert(Kit.buildwand(row.wand,{row.capacity or 12,1,80,false,71,0,600},row.name))
        w.components.nw_wand.data.stats.spread=0
        w.components.nw_wand.data.config_revision=w.components.nw_wand.data.config_revision+1
        w.components.nw_wand:Sync();return w
    end
    local e=assert(SpawnPrefab(row.card and "nw_spellcard" or row.prefab))
    if row.card then e:SetSpell(row.card);e.source="debug" end
    if (row.count or 1)>1 then
        assert(e.components.stackable and row.count<=e.components.stackable.maxsize,"test supply exceeds one stack")
        e.components.stackable:SetStackSize(row.count)
    end
    return e
end
function M.spawn(id,player)
    if id==nil or id=="help" then return M.help() end
    if id~="all" and id~="duo" and not byid[id] then report("NW: unknown test scene "..tostring(id));return M.help() end
    player=player or ConsoleCommandPlayer()
    if not player then report("NW: 未找到玩家，请进入世界后使用远程控制台。");return end
    local selection=id=="all" and Scenarios or id=="duo" and {} or {byid[id]}
    if id=="duo" then for _,s in ipairs(Scenarios) do if s.duo then selection[#selection+1]=s end end end
    local x,_,z=player.Transform:GetWorldPosition()
    local plan,used={},{}
    local function reserve(prefab,name,px,pz,scene,index)
        local p=point(px,pz,used)
        if not p then return false end
        plan[#plan+1]={prefab=prefab,name=name,x=p.x,z=p.z,scene=scene,index=index};return true
    end
    for i,s in ipairs(selection) do
        local ax,az=x+(#selection==1 and 0 or ((i-1)%4-1.5)*8),z+6+math.floor((i-1)/4)*8
        local count=math.ceil(#s.items/9)
        for n=1,count do
            local label=s.boxlabels and s.boxlabels[n] or n.."/"..count
            if not reserve("treasurechest","测试箱 · "..s.name.." · "..label,ax+(n-1)*3,az,s,n) then
                report("NW: 空地不足，请换到更开阔处或分组生成。");return
            end
        end
        if not reserve("homesign","测试说明 · "..s.name,ax,az-3,s) then report("NW: 木牌位置不足，请换空地。");return end
    end
    if id=="all" or id=="duo" or id=="duo_ui" or id=="ui" or id=="casting" or id=="crafting" then
        for i,prefab in ipairs((id=="all" or id=="crafting") and {"nw_workbench","nw_engraver","nw_disassembler"} or {"nw_workbench"}) do
            if not reserve(prefab,nil,x+(i-2)*3,z-4) then report("NW: 工作站位置不足，请换空地。");return end
        end
    end
    local result={boxes={},signs={},stations={}}
    for _,p in ipairs(plan) do
        local e=assert(SpawnPrefab(p.prefab));e.Transform:SetPosition(p.x,0,p.z)
        if p.name then named(e,p.name) end
        if p.prefab=="treasurechest" then
            result.boxes[#result.boxes+1]=e
            for slot=1,9 do
                local row=p.scene.items[(p.index-1)*9+slot]
                if row then
                    local v=supply(row);v.Transform:SetPosition(p.x,0,p.z)
                    assert(e.components.container:GiveItem(v,slot),"test box refused item")
                end
            end
        elseif p.prefab=="homesign" then
            local lines={p.scene.name}
            for n,step in ipairs(p.scene.steps) do lines[#lines+1]=n..". "..step end
            e.components.writeable:SetText(table.concat(lines,"\n"))
            result.signs[#result.signs+1]=e
        else result.stations[#result.stations+1]=e end
    end
    report(string.format("NW_TESTSCENE: %s; %d boxes; %d signs; %d stations",id,#result.boxes,#result.signs,#result.stations))
    return result
end
function M.cleanup(count,player)
    count=count or 20
    if type(count)~="number" or count~=math.floor(count) or count<1 or count>21 then
        report("nw_testcleanup：每次生成 1～21 个测试卵，例如先 20，再 1。");return
    end
    player=player or ConsoleCommandPlayer()
    if not player then report("NW: 未找到玩家，请进入世界后使用远程控制台。");return end
    local x,_,z=player.Transform:GetWorldPosition()
    local points,used={},{}
    for i=1,count do
        local p=point(x+((i-1)%5-2)*5,z+6+math.floor((i-1)/5)*5,used)
        if not p then report("NW: 测试卵位置不足，请换空地。");return end
        points[#points+1]=p
    end
    local d=require("nw/util").copy(require("nw/definitions").spells.payload_egg)
    d.speed=0;d.flags={targets={hostile=true},homing=require("nw/util").copy(require("nw/definitions").spells.homing)}
    local result={}
    for _,p in ipairs(points) do
        local e=assert(SpawnPrefab("nw_payload_egg"))
        e:Launch(player,require("nw/util").copy(d),p.x,p.z,1,0,function() end,1.4)
        result[#result+1]=e
    end
    local pool=TheWorld._nw_permanent_motion_cleanup
    report(string.format("NW_TESTCLEANUP: %d created; setting %s; tracked total %d",#result,tostring(require("nw/spell_limits").permanent_motion_cleanup),pool and pool.count or 0))
    return result
end
M.scenarios=Scenarios
return M
