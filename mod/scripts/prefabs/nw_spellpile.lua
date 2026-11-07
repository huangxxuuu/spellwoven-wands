local T=require("nw/locale").t
local Cards=require("nw/cards")
local stride=require("nw/cardpile").stride
local Ground=require("nw/ground_card")
local assets=Ground.assets()
local function show(inst)
    local surface=inst._surface:value()
    local code,count=surface%stride,math.floor(surface/stride)
    local layout=inst._layers:value()
    local separated=inst._separated:value()
    Ground.show(inst,code,count,layout,separated)
    if inst._nw_outline then Ground.show(inst._nw_outline,code,count,layout,separated) end
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
    local code,layout=Ground.surface(box)
    if code then
        inst._layers:set(layout)
        inst._surface:set(count*stride+code)
        inst.components.named:SetName(string.format(T("法术牌堆（%d/%d）"),count,box:GetNumSlots()))
        show(inst)
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
    inst._layers=net_byte(inst.GUID,"nw_pile.layers","nw_piledirty")
    inst._separated=net_bool(inst.GUID,"nw_pile.separated","nw_piledirty")
    inst.displaynamefn=function(self)
        return string.format(T("法术牌堆（%d/%d）"),math.floor(self._surface:value()/stride),25)
    end
    show(inst)
    require("nw/recycle_mark").attach(inst,function(glow,item)
        local surface=item._surface:value()
        Ground.show(glow,surface%stride,math.floor(surface/stride),item._layers:value(),item._separated:value())
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
    -- Choose once, on the server. Count changes, refreshes and reloads keep it.
    inst._separated:set(math.random()<.5)
    inst.OnSave=function(self,data) data.separated=self._separated:value() end
    inst.OnLoad=function(self,data)
        if data and data.separated~=nil then self._separated:set(data.separated==true) end
        schedule(self)
    end
    inst:ListenForEvent("itemget",schedule)
    inst:ListenForEvent("itemlose",schedule)
    schedule(inst)
    return inst
end
return Prefab("nw_spellpile",fn,assets,{"nw_spellcard"})
