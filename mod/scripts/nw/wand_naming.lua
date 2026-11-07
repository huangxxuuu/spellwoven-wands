local T=require("nw/locale").t
local M={}
function M.describe(inst)
    local named=inst.components.named
    return named and named.name or inst:GetBasicDisplayName(),TEXT_FILTER_CTX_CHAT,named and named.name_author_netid
end
local function owns(doer,item)
    return doer and item and item:IsValid() and item.components.inventoryitem
        and item.components.inventoryitem:GetGrandOwner()==doer
end
function M.begin(act)
    local wand,pencil,doer=act.target,act.invobject,act.doer
    if not wand or not wand:IsValid() or not wand:HasTag("nw_wand")
        or not pencil or pencil.prefab~="featherpencil" or not owns(doer,pencil)
        or not doer.components.health or doer.components.health:IsDead() or doer:HasTag("playerghost") then return false end
    local w=wand.components.writeable
    if not w or w:IsBeingWritten() then return false,"INUSE" end
    if wand.components.inventoryitem:IsHeld() and not owns(doer,wand) then return false end
    if not owns(doer,wand) and not (doer:IsNear(wand,3) and CanEntitySeeTarget(doer,wand)) then return false end
    wand._nw_name_pencil=pencil
    local named=wand.components.named
    local name=named.name or wand:GetBasicDisplayName()
    if not named.name_author_netid and not wand:HasTag("nw_customname") then name=require("nw/locale").for_player(doer,name) end
    wand._nw_name_original=name
    w:SetText(name)
    w:BeginWriting(doer)
    return true
end
function M.setup(inst)
    inst:AddComponent("writeable")
    local w=inst.components.writeable
    w:SetDefaultWriteable(false)
    w:SetAutomaticDescriptionEnabled(false)
    local begin=w.BeginWriting
    w.BeginWriting=function(self,doer)
        if owns(doer,inst._nw_name_pencil) then return begin(self,doer) end
    end
    w:SetOnWrittenFn(function(self,text,doer)
        local pencil=self._nw_name_pencil
        local name=type(text)=="string" and text:gsub("[\r\n\t]"," "):match("^%s*(.-)%s*$") or nil
        if name and name~="" and name~=self.components.named.name and name~=self._nw_name_original and owns(doer,pencil)
            and doer.components.health and not doer.components.health:IsDead() and not doer:HasTag("playerghost")
            and (owns(doer,self) or not self.components.inventoryitem:IsHeld() and doer:IsNear(self,3) and CanEntitySeeTarget(doer,self)) then
            self.components.named:SetName(name,doer.userid)
            self:AddTag("nw_customname")
            require("nw/spelljournal").renamed(self,doer)
            local one=pencil.components.stackable and pencil.components.stackable:Get() or pencil
            one:Remove()
        end
        w:SetText(self.components.named.name or self:GetBasicDisplayName())
    end)
    w:SetOnWritingEndedFn(function(self) self._nw_name_pencil=nil;self._nw_name_original=nil end)
    local update=w.OnUpdate
    w.OnUpdate=function(self,dt)
        -- Inventory items can be INLIMBO; their holder is the writing location.
        if self.writer and owns(self.writer,inst)
            and not (self.writer.components.rider and self.writer.components.rider:IsRiding()) then return end
        return update(self,dt)
    end
    inst.components.inspectable.getspecialdescription=M.describe
end
function M.install(env)
    local layouts=require("writeables")
    layouts.AddLayout("nw_wand",{
        prompt=T("为法杖命名（最多 32 字）"),animbank="ui_board_5x3",animbuild="ui_board_5x3",
        menuoffset=Vector3(6,-70,0),maxcharacters=32,
        defaulttext=function(inst) return inst:GetBasicDisplayName() end,
        cancelbtn={text=T("取消"),control=CONTROL_CANCEL},acceptbtn={text=T("改名"),control=CONTROL_ACCEPT},
    })
    local action=Action({priority=10,rmb=true,distance=3})
    action.id="NW_RENAME";action.str=T("改名");action.fn=M.begin
    env.AddAction(action)
    env.AddComponentAction("USEITEM","drawingtool",function(inst,doer,target,actions,right)
        if right and inst.prefab=="featherpencil" and target:HasTag("nw_wand") then
            table.insert(actions,action)
        end
    end)
    env.AddStategraphActionHandler("wilson",ActionHandler(action,"doshortaction"))
    env.AddStategraphActionHandler("wilson_client",ActionHandler(action,"doshortaction"))
end
return M
