-- World-saved spell placements. Runtime owner entities and callbacks never
-- enter save data; ownership follows the player's userid across reconnects.
local Copy=require("nw/util").copy
local M={}
function M.userid(e)
    return e and type(e.userid)=="string" and e.userid~="" and e.userid or nil
end
function M.caster(e)
    if not require("nw/spell_effects").live(e) or e:HasTag("playerghost")
        or e.IsInLimbo and e:IsInLimbo() then return end
    -- Valid Lua entities can linger briefly while changing shards/disconnecting.
    if M.userid(e) then
        for _,player in ipairs(AllPlayers) do if player==e then return e end end
        return
    end
    return e
end
function M.is(id)
    return id=="crystal_mine" or id=="sleep_crystal" or id=="payload_egg"
end
local function key(owner) return M.userid(owner) or tostring(owner.GUID) end
function M.crystals(owner)
    local all=TheWorld._nw_crystal_owners or {}
    TheWorld._nw_crystal_owners=all
    local id=key(owner)
    all[id]=all[id] or {}
    owner._nw_crystals=all[id]
    return all[id]
end
function M.owner(inst)
    local data=inst._nw_stored
    local owner=inst._nw_owner
    if not owner or not owner:IsValid() then
        owner=nil
        if data.userid and data.userid~="" then
            for _,player in ipairs(AllPlayers) do
                if player.userid==data.userid then owner=player;break end
            end
        end
        inst._nw_owner=owner
    end
    if owner then
        M.crystals(owner)
        return M.caster(owner)
    end
end
local function track(inst,loading)
    local data=inst._nw_stored
    local all=TheWorld._nw_crystal_owners or {}
    TheWorld._nw_crystal_owners=all
    local id=data.userid or data.owner_key
    local list=all[id] or {};all[id]=list
    list[#list+1]=inst
    table.sort(list,function(a,b) return a._nw_stored.order<b._nw_stored.order end)
    inst:ListenForEvent("onremove",function()
        for i,v in ipairs(list) do if v==inst then table.remove(list,i);break end end
    end)
end
function M.start(inst,data,owner,loading)
    inst._nw_stored=Copy(data)
    data=inst._nw_stored
    require("nw/entity_limits").restore_field(inst,data.userid or data.owner_key,"permanent_fields",data.order)
    data.order=inst._nw_permanent_order or data.order
    require("nw/projectile_size").field(inst,data.p)
    inst._nw_owner=owner
    if data.neutral and not owner then
        local x,_,z=inst.Transform:GetWorldPosition()
        owner=require("nw/payload_caster").neutral(x,z);inst._nw_owner=owner
    end
    require("nw/payload_caster").retain(owner,inst)
    TheWorld._nw_placement_order=math.max(TheWorld._nw_placement_order or 0,data.order or 0)
    if not data.order then
        TheWorld._nw_placement_order=TheWorld._nw_placement_order+1
        data.order=TheWorld._nw_placement_order
    end
    if data.p.id~="payload_egg" then track(inst,loading) end
    local function joined(_,player)
        if data.userid and player.userid==data.userid then inst._nw_owner=player;M.crystals(player) end
    end
    inst:ListenForEvent("ms_playerjoined",joined,TheWorld)
    owner=M.owner(inst)
    local function fire(x,z,dx,dz,triggerer)
        local caster
        if data.p.id=="payload_egg" then
            caster=require("nw/payload_caster").resolve(triggerer)
            if not caster then caster=require("nw/payload_caster").neutral(x,z) end
        else caster=M.owner(inst) end
        if not caster then return false end
        if not data.payload then return true end
        return require("nw/executor").execute(Copy(data.payload),caster,x,z,dx,dz,data.height)
    end
    local x,_,z=inst.Transform:GetWorldPosition()
    if require("nw/field_motion").start(inst,owner,data.p,data.dx,data.dz,data.age,data.motion)==false then return end
    require("nw/field_stages").start(inst,data.p.id,data.p,loading)
    require("nw/expanded_fields").actions[data.p.id](inst,owner,data.p,x,z,data.dx,data.dz,fire)
end
function M.install(inst)
    inst.OnSave=function(self,data)
        if not self._nw_stored or self._nw_spent then return end
        local saved=Copy(self._nw_stored)
        saved.cleanup_absent=require("nw/permanent_motion_cleanup").elapsed(self)
        local motion=self._nw_motion
        if motion then
            saved.dx,saved.dz,saved.age=motion.dx,motion.dz,motion.age
            saved.motion=require("nw/field_motion").save(self)
        end
        if self._nw_armed_at then saved.arm_left=math.max(0,self._nw_armed_at-GetTime()) end
        data.placement=saved
    end
    inst.OnLoad=function(self,data)
        if data and data.placement then M.start(self,data.placement,nil,true) end
    end
end
function M.launch(inst,owner,p,dx,dz,height,payload)
    M.start(inst,{userid=M.userid(owner),owner_key=key(owner),neutral=owner._nw_neutral,p=p,dx=dx,dz=dz,height=height,payload=payload},owner)
end
return M
