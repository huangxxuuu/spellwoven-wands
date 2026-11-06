local T=require("nw/locale").t
local Cards=require("nw/cards")
local stride=require("nw/cardpile").stride
local Ground=require("nw/ground_card")
local assets=Ground.assets()
local function show(inst)
    local surface=inst._surface:value()
    local code,count=surface%stride,math.floor(surface/stride)
    Ground.show(inst,code,count)
    if inst._nw_outline then Ground.show(inst._nw_outline,code,count) end
end

local function update(inst)
    inst._update=nil
    local box=inst.components.container
    local count=box:NumItems()
    if count<=1 then
        box:Close()
        box:DropEverything()
        inst:Remove()
        return
    end
    for i=1,box:GetNumSlots() do
        local top=box:GetItemInSlot(i)
        if top then
            inst._surface:set(count*stride+Cards.codes[top.spell_id])
            inst.components.named:SetName(string.format(T("法术牌堆（%d/%d）"),count,box:GetNumSlots()))
            show(inst)
            break
        end
    end
end
local function schedule(inst)
    -- Coalesce native remove/give events (including loading a save and swaps).
    if not inst._update then inst._update=inst:DoTaskInTime(0,update) end
end

local function fn()
    local inst=CreateEntity()
    inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddNetwork()
    inst:AddTag("nw_spellpile");inst:AddTag("chest");inst:AddTag("fireimmune")
    inst._surface=net_ushortint(inst.GUID,"nw_pile.surface","nw_piledirty")
    inst.displaynamefn=function(self)
        return string.format(T("法术牌堆（%d/%d）"),math.floor(self._surface:value()/stride),25)
    end
    show(inst)
    require("nw/recycle_mark").attach(inst,function(glow,item)
        local surface=item._surface:value()
        Ground.show(glow,surface%stride,math.floor(surface/stride))
    end)
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then
        inst:ListenForEvent("nw_piledirty",show);inst:DoTaskInTime(0,show)
        return inst
    end
    inst:AddComponent("inspectable")
    inst:AddComponent("named")
    inst:AddComponent("container")
    inst.components.container:WidgetSetup("nw_spellpile")
    inst:ListenForEvent("itemget",schedule)
    inst:ListenForEvent("itemlose",schedule)
    schedule(inst)
    return inst
end
return Prefab("nw_spellpile",fn,assets,{"nw_spellcard"})
