-- Client-only preference, independent of a world, shard, wand or server save.
local M={key="nw_weave_hud_position_v1"}
local loaded,loading,saved,revision=false,false,nil,0
local waiters={}
local writing,queued=false,nil
local function finite(n)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end
function M.validate(value)
    if type(value)~="table" or value.version~=1 or not finite(value.x) or not finite(value.y)
        or value.x<0 or value.x>1 or value.y<0 or value.y>1 then return nil end
    return {version=1,x=value.x,y=value.y}
end
function M.clamp(x,y,width,bottom,top,sw,sh)
    local left,right=width/2+6,sw-width/2-6
    local low,high=-bottom+6,sh-top-6
    return left<=right and math.max(left,math.min(right,x)) or sw/2,
        low<=high and math.max(low,math.min(high,y)) or (sh-bottom-top)/2
end
function M.load(callback)
    if loaded then callback(M.validate(saved));return end
    waiters[#waiters+1]=callback
    if loading then return end
    loading=true
    local at=revision
    TheSim:GetPersistentString(M.key,function(ok,str)
        if at==revision and ok and str and #str>0 then
            local valid,value=pcall(require("json").decode,str)
            if valid then saved=M.validate(value) end
        end
        loaded,loading=true,false
        local callbacks=waiters;waiters={}
        for _,fn in ipairs(callbacks) do fn(M.validate(saved)) end
    end,false)
end
local function flush()
    if writing or not queued then return end
    writing=true
    local value=queued;queued=nil
    TheSim:SetPersistentString(M.key,require("json").encode(value),false,function()
        writing=false;flush()
    end)
end
function M.save(value)
    value=M.validate(value)
    if not value then return false end
    revision=revision+1;saved=value;loaded=true
    queued=value;flush()
    return true
end
return M
