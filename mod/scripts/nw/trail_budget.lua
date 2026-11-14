local C=require("nw/constants/performance").trail
local M={limit=0,options=require("nw/util").copy(C.options),key="nw_weave_trail_limit_v1"}
local allowed={};for _,limit in ipairs(M.options) do allowed[limit]=true end
local legacy=C.legacy
local function normalize(limit) return allowed[limit] and limit or legacy[limit] end
local loaded,loading,revision=false,false,0
local waiters={}
local writing,queued=false,nil

local function owner_userid(source)
    if not source then return "" end
    local id=source._nw_trail_userid and source._nw_trail_userid:value()
    if type(id)=="string" then return id end
    local owner=source._shot and source._shot.owner or source._nw_owner
    return owner and type(owner.userid)=="string" and owner.userid or ""
end

function M.can_emit(source)
    if M.limit==0 then return true end
    local userid=ThePlayer and ThePlayer.userid
    local mine=type(userid)=="string" and userid~="" and owner_userid(source)==userid
    local threshold=mine and M.limit or math.floor(M.limit*C.other_fraction)
    local pool=TheWorld and TheWorld._nw_trail_budget
    return (pool and pool.count or 0)<threshold
end

local function close(pool)
    if pool.world.RemoveEventCallback then pool.world:RemoveEventCallback("onremove",pool.onremove) end
    if pool.world._nw_trail_budget==pool then pool.world._nw_trail_budget=nil end
end

function M.remove(part)
    local record=part._trail_record
    if not record then return end
    local pool=record.pool
    pool.parts[part]=nil;part._trail_record=nil
    pool.count=pool.count-1
    record.dispose(part)
    if pool.count==0 then close(pool) end
end

function M.configure(limit)
    M.limit=normalize(limit) or 0
end
function M.install(env,G)
    if not G.TheNet:IsDedicated() then
        if not loaded then M.configure(env.GetModConfigData("client_trail_limit",true)) end
        M.load()
    end
end
function M.load(callback)
    if loaded then if callback then callback() end;return end
    if callback then waiters[#waiters+1]=callback end
    if loading then return end
    loading=true
    local at=revision
    TheSim:GetPersistentString(M.key,function(ok,value)
        local n=ok and normalize(tonumber(value)) or nil
        if at==revision and n~=nil then M.configure(n) end
        loaded,loading=true,false
        local callbacks=waiters;waiters={}
        for _,fn in ipairs(callbacks) do fn() end
    end,false)
end
local function flush()
    if writing or queued==nil then return end
    writing=true
    local value=queued;queued=nil
    TheSim:SetPersistentString(M.key,tostring(value),false,function()
        writing=false;flush()
    end)
end
function M.set(value)
    if not allowed[value] then return false end
    revision=revision+1;loaded=true;M.configure(value)
    queued=value;flush()
    return true
end
function M.clear()
    local pool=TheWorld and TheWorld._nw_trail_budget
    if pool then pool.onremove() end
end

function M.track(part,born,dispose)
    local record=part._trail_record
    if record then record.born=born;return end
    local pool=TheWorld._nw_trail_budget
    if not pool then
        pool={world=TheWorld,parts={},count=0}
        TheWorld._nw_trail_budget=pool
        pool.onremove=function()
            while next(pool.parts) do M.remove(next(pool.parts)) end
            close(pool)
        end
        if TheWorld.ListenForEvent then TheWorld:ListenForEvent("onremove",pool.onremove) end
    end
    part._trail_record={pool=pool,dispose=dispose,born=born}
    pool.parts[part]=true;pool.count=pool.count+1
end
return M
