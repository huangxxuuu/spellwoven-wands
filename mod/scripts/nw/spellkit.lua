local Factory=require("nw/wand_factory")
local Compiler=require("nw/compiler")
local Cards=require("nw/cards")
local D=require("nw/definitions")
local M={}
M.pages={
    {"基础弹与近战",{"spark","arrow","heavy","scatter","fire","frost","thrust","slash","whirl"}},
    {"弹道",{"sine","spiral","precision","homing","bounce","orbit","phase_wall","homing_rotate"}},
    {"弹体强化",{"speed_up","speed_down","damage_up","pierce","pierce_all","knockback","giant_shot","short_life"}},
    {"辅助、多重与触发",{"leech","light","heal_ally","double","triple","imprint_hit","imprint_timer"}},
    {"碰撞变体",{}},{"定时变体",{}},
    {"瞬发、法杖修正与倍施",{"explosion","chain","mana_reduce","recharge_down","repeat_2","repeat_3","gunpowder"}},
    {"首批扩充",{"spore_sentry","vital_ring","heavy_shot","trident_cast","chord_d","repeat_4"}},
}
for _,id in ipairs(D.bullets) do
    table.insert(M.pages[5][2],id.."_hit");table.insert(M.pages[6][2],id.."_timer")
end
for i,card in ipairs(require("nw/expansion")) do
    if (i-1)%8==0 then M.pages[#M.pages+1]={"百卡扩充 "..math.ceil(i/8),{}} end
    table.insert(M.pages[#M.pages][2],card.id)
end
local previous
for _,c in ipairs(require("nw/arsenal").cards) do
    if not require("nw/engraved_spells").retired[c.id] then
    local group=c.source_weapon and "武器刻印" or c.select_target and "目标选择" or "乐谱"
    if previous~=group or #M.pages[#M.pages][2]==9 then M.pages[#M.pages+1]={group,{}} end
    previous=group;table.insert(M.pages[#M.pages][2],c.id)
    end
end
M.presets={
    weather={"double","rain_cloud","wet_weak","arrow"},
    ambush={"arrow_hit","sleep_crystal","detonate"},
    bells={"note_a","note_c"},hex={"hex_cast","spark","fire","arrow","frost","flint_lance","slime"},
    garden={"arrow_hit","spore_sentry"},fan={"trident_cast","fire","arrow","frost"},
    wall={"phase_wall","arrow"},burst={"explosion","arrow"},
    echo={"repeat_2","double","spark","arrow"},
    economy={"mana_reduce","repeat_3","arrow"},
    quick={"mana_reduce","recharge_down","spark"},
    remote={"arrow_hit","slash"},timer={"arrow_timer","whirl"},scatter={"scatter_hit","thrust"},
    nested={"imprint_hit","arrow","spark_timer","whirl"},fire={"triple","fire","fire","fire"},
    frost={"triple","frost","frost","frost"},lightning={"arrow_hit","leech","chain"},
    orbit={"orbit","pierce_all","light","spark"},curve={"homing","sine","arrow"},
    ricochet={"bounce","knockback","heavy"},support={"heal_ally","spark"},
}
local function actor()
    local player=ConsoleCommandPlayer()
    return player and player.components.inventory and player
end
local function card(id)
    local e=SpawnPrefab("nw_spellcard")
    e:SetSpell(id);e.source="debug";return e
end
function M.give(id)
    local player=actor()
    if not player or not Cards.codes[id] then print("NW: unknown card",id);return end
    player.components.inventory:GiveItem(card(id),nil,player:GetPosition())
end
function M.buildwand(ids,spec,label)
    if #ids==1 and M.presets[ids[1]] then ids=M.presets[ids[1]] end
    if #ids>12 then print("NW: max 12 slots");return end
    for _,id in ipairs(ids) do if not Cards.codes[id] then print("NW: unknown card",id);return end end
    local w=SpawnPrefab("nw_wand");local cmp=w.components.nw_wand
    cmp:InitializePrototype()
    local d=cmp.data
    d.stats.capacity,d.stats.mana_max,d.stats.mana_regen=12,600,80
    d.stats.spread,d.stats.cast_delay,d.stats.recharge=6,.45,.6
    if spec then
        d.stats.capacity,d.stats.draw_count,d.stats.mana_regen,d.stats.shuffle,d.seed=unpack(spec)
        d.stats.mana_max=spec[7] or d.stats.mana_max
        d.appearance=require("nw/visual").appearance(d.stats,spec[6])
    end
    d.cards={}
    for i=1,d.stats.capacity do d.cards[i]=ids[i] and Factory.card(ids[i],"debug") or false end
    d.runtime=Compiler.initial(d.cards,d.stats,d.seed)
    d.config_revision=d.config_revision+1;cmp:Sync()
    w.components.named:SetName(label or (spec and ((d.stats.shuffle and "木尖" or "晶尖").."试杖 · 同发 "..d.stats.draw_count) or
        "试验法杖 · "..(#ids>0 and Cards.short[ids[1]] or "空杖")))
    return w
end
local function makewand(player,ids,spec)
    local w=M.buildwand(ids,spec)
    if not w then return end
    player.components.inventory:GiveItem(w,nil,player:GetPosition())
    return w
end
function M.wand(...)
    local player=actor()
    if player then return makewand(player,{...}) end
end
function M.rollwand(tier,seed,player)
    player=player or actor()
    if not player then return end
    if type(tier)~="number" or tier~=math.floor(tier) or tier<1 or tier>4 or
        (seed~=nil and (type(seed)~="number" or seed~=math.floor(seed) or seed<1 or seed>2147483646)) then
        print("nw_rollwand(tier 1-4, optional integer seed 1-2147483646)");return
    end
    local w=SpawnPrefab("nw_wand")
    local cmp=w.components.nw_wand
    cmp:InitializeNew(tier,"debug",nil,seed)
    local d=cmp.data
    for i=1,d.stats.capacity do d.cards[i]=Factory.card("spark","debug") end
    d.config_revision=d.config_revision+1
    d.runtime=Compiler.initial(d.cards,d.stats,d.seed)
    cmp:Sync()
    player.components.inventory:GiveItem(w,nil,player:GetPosition())
    return w
end
local function place(player,angle,dist)
    local pt=player:GetPosition()
    local offset=FindWalkableOffset(pt,angle,dist,16,true,false)
    return offset and pt+offset or pt
end
function M.hudkit()
    local player=actor()
    if not player then return end
    local result={}
    for _,spec in ipairs({{2,1,18,false,1,0,120},{7,1,25,false,2,0,260},{12,1,40,false,3,0,600}}) do
        result[#result+1]=makewand(player,{"spark","arrow"},spec)
    end
    local bench=SpawnPrefab("nw_workbench")
    bench.Transform:SetPosition(place(player,.4,2.5):Get())
    player.components.inventory:GiveItem(card("fire"))
    return result
end
function M.lookkit(color,style)
    local player=actor()
    if not player then return end
    local palette={red=0,blue=1,green=2}
    if color and palette[color]==nil then print('nw_lookkit: red / blue / green');return end
    if style~=nil and (type(style)~="number" or style~=math.floor(style) or style<1 or style>require("nw/visual").styles) then
        print("nw_lookkit: shaft number 1-9");return
    end
    for i,spec in ipairs({{4,1,12,false,1},{8,2,18,false,2},{12,3,38,false,3},
        {4,1,18,true,4},{8,2,38,true,5},{12,3,12,true,6}}) do
        local head=palette[color] or (i-1+(spec[4] and 1 or 0))%3
        local tail=palette[color] or i%3
        spec[6]=head+tail*3+((i-1)%2)*9+18*((style or i)-1)
        makewand(player,{"spark","arrow"},spec)
    end
    for _,id in ipairs({"fire","frost","chain"}) do player.components.inventory:GiveItem(card(id)) end
    local bench=SpawnPrefab("nw_workbench")
    bench.Transform:SetPosition(place(player,.4,2.5):Get())
end
function M.all(player)
    player=player or actor()
    if not player then return end
    local boxes={}
    for i,page in ipairs(M.pages) do
        local chest=SpawnPrefab("treasurechest")
        boxes[#boxes+1]=chest
        chest.Transform:SetPosition(place(player,2*math.pi*i/#M.pages,math.max(5,#M.pages*.33)):Get())
        if not chest.components.named then chest:AddComponent("named") end
        chest.components.named:SetName("试验卡箱 · "..page[1])
        for j,id in ipairs(page[2]) do
            local e=card(id)
            e.Transform:SetPosition(chest.Transform:GetWorldPosition())
            chest.components.container:GiveItem(e,j)
        end
    end
    local bench=SpawnPrefab("nw_workbench")
    bench.Transform:SetPosition(place(player,.4,1.8):Get())
    local wand=makewand(player,{})
    print("NW_SPELLKIT: all spells / grouped chests, bench and editable 12-slot wand")
    return boxes,bench,wand
end
function M.range()
    local player=actor()
    if not player then return end
    local x,_,z=player.Transform:GetWorldPosition()
    local a=-player.Transform:GetRotation()*DEGREES
    local dx,dz=math.cos(a),math.sin(a)
    for _,p in ipairs({{5,0},{6.6,0},{8.2,0},{9.8,0},{5.6,1},{3,-2}}) do
        local tx,tz=x+dx*p[1]-dz*p[2],z+dz*p[1]+dx*p[2]
        if TheWorld.Map:IsPassableAtPoint(tx,0,tz) then
            local t=SpawnPrefab("nw_target_dummy")
            t.Transform:SetPosition(tx,0,tz)
            if p[2]<0 then
                t:AddComponent("follower");t.components.follower:SetLeader(player)
                t.components.health:SetPercent(.50)
                t:AddComponent("named");t.components.named:SetName("友方治疗靶 · 初始 500 血")
            end
        end
    end
end
return M
