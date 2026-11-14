local C=require("nw/constants/training").trial
local M={}
local active=setmetatable({},{__mode="k"})
local L=require("nw/locale")
local strings={
    {"10秒测试","10s trial"},{"30秒测试","30s trial"},
    {"连击","Combo"},{"重置","Reset"},
    {"等待测试者首次命中","Waiting for tester's first hit"},
    {"测试完成","Trial complete"},{"测试中","Trial running"},
    {"伤害 %.1f","Damage %.1f"},
    {"窗口耗蓝 %.1f","Window mana %.1f"},
    {"施法次数 %d","Casts %d"},
    {"空手右键切换连击/10秒/30秒；测试中或结束后右键重置，再次右键切换。仅统计选定测试者。","Empty-hand right-click cycles combo/10s/30s; during or after a trial, right-click resets, then right-click again to switch. Only the selected tester counts."},
}
for _,pair in ipairs(strings) do L.register(pair[1],pair[2]) end
local function valid(player)
    return player and player:IsValid() and not player:HasTag("playerghost")
end
function M.new(duration,tester)
    return {duration=duration,tester=tester,damage=0,mana=0,casts=0,dps=0}
end
function M.damage(s,owner,amount,now)
    if owner~=s.tester or type(amount)~="number" or amount~=amount or amount<=0 or amount>=math.huge then return false end
    if s.finished or s.started and now>=s.started+s.duration then return false end
    if not s.started then s.started=now end
    s.damage=s.damage+amount
    M.advance(s,now)
    return true
end
function M.advance(s,now)
    if s.started and not s.finished and now>=s.started+s.duration then s.finished=true end
    local elapsed=s.started and math.min(s.duration,math.max(0,now-s.started)) or 0
    s.dps=s.damage/math.max(C.min_dps_seconds,elapsed)
end
function M.cast(owner,spent,now)
    local bag=active[owner]
    local s=bag and bag._nw_trial
    if s and not s.finished and (not s.started or now<s.started+s.duration)
        and type(spent)=="number" and spent>=0 and spent<math.huge then
        s.mana=s.mana+spent
        s.casts=s.casts+1
        M.advance(s,now)
        M.refresh(bag)
    end
end
local function text(s)
    local name=s.tester.GetDisplayName and s.tester:GetDisplayName() or "Tester"
    local elapsed=s.started and math.min(s.duration,math.max(0,GetTime()-s.started)) or 0
    return string.format("%d|%.2f|%.3f|%.3f|%d|%.3f|%d|%s",s.duration,elapsed,s.damage,s.mana,
        s.finished and 2 or s.started and 1 or 0,s.dps,s.casts,name)
end
function M.display(raw)
    if not raw or raw=="" then return "" end
    local duration,elapsed,damage,mana,status,dps,casts,name=raw:match("^(%d+)|([%d.]+)|([%d.]+)|([%d.]+)|(%d)|([%d.]+)|(%d+)|(.+)$")
    if not duration then return "" end
    duration,elapsed,damage,mana,status=tonumber(duration),tonumber(elapsed),tonumber(damage),tonumber(mana),tonumber(status)
    local heading=L.t(status==2 and "测试完成" or status==1 and "测试中" or "等待测试者首次命中")
    return string.format("%s [%s] %.1f/%ds\n%s\nDPS %.1f\n%s\n%s",heading,name,elapsed,duration,
        string.format(L.t("伤害 %.1f"),damage),tonumber(dps),
        string.format(L.t("窗口耗蓝 %.1f"),mana),
        string.format(L.t("施法次数 %d"),tonumber(casts)))
end
function M.refresh(bag)
    local s=bag._nw_trial
    local code=not s and 0 or (s.duration==C.short_duration and 1 or 2)+(s.finished and 4 or s.started and 2 or 0)
    bag._nw_trial_mode:set(code)
    bag._nw_trial_text:set(s and text(s) or "")
    if bag._nw_combo_refresh then bag._nw_combo_refresh() end
end
local function release(bag)
    local s=bag._nw_trial
    if s and active[s.tester]==bag then active[s.tester]=nil end
end
function M.select(bag,player)
    if not valid(player) or bag:HasTag("burnt") or not player:IsNear(bag,C.select_distance) then return false end
    local inv=player.components.inventory
    if inv and inv:GetEquippedItem(EQUIPSLOTS.HANDS) then return false end
    local old=bag._nw_trial
    if old and old.tester~=player and valid(old.tester) and not old.finished then return false end
    local duration=old and old.duration
    if not old or old.tester~=player then duration=C.short_duration
    elseif not old.started then duration=old.duration==C.short_duration and C.long_duration or nil end
    if duration and active[player] and active[player]~=bag and not active[player]._nw_trial.finished then return false end
    release(bag)
    bag._nw_trial=duration and M.new(duration,player) or nil
    if duration then active[player]=bag end
    M.refresh(bag)
    return true
end
function M.hit(bag,owner,amount)
    local s=bag._nw_trial
    if s and M.damage(s,owner,amount,GetTime()) then M.refresh(bag) end
end
function M.setup(bag)
    local combat=bag.components.combat
    if combat then
        local key=combat.GetAttacked_Internal and "GetAttacked_Internal" or "GetAttacked"
        local original=combat[key]
        combat[key]=function(self,attacker,damage,weapon,...)
            local source=weapon and weapon._nw_journal_source or attacker and attacker._nw_journal_source
            local previous=bag._nw_damage_owner
            bag._nw_damage_owner=source and source.owner or attacker
            local result=original(self,attacker,damage,weapon,...)
            bag._nw_damage_owner=previous
            return result
        end
    end
    local health=bag.components.health
    local delta=health.DoDelta
    health.DoDelta=function(self,amount,overtime,cause,ignore_invincible,afflicter,...)
        local previous=bag._nw_health_owner
        bag._nw_health_owner=bag._nw_damage_owner or afflicter
        local result=delta(self,amount,overtime,cause,ignore_invincible,afflicter,...)
        bag._nw_health_owner=previous
        return result
    end
    bag:DoPeriodicTask(C.refresh_interval,function()
        local s=bag._nw_trial
        if not s then return end
        if not valid(s.tester) or bag:HasTag("burnt") or s.tester:GetDistanceSqToInst(bag)>C.max_distance*C.max_distance then
            release(bag);bag._nw_trial=nil;M.refresh(bag);return
        end
        if s.started and not s.finished then M.advance(s,GetTime());M.refresh(bag) end
    end)
    bag:ListenForEvent("onremove",function() release(bag) end)
end
function M.install(env)
    local a=Action({priority=C.action_priority,rmb=true,distance=C.action_distance})
    a.id="NW_DUMMY_TRIAL";a.str=L.t("10秒测试")
    a.strfn=function(act)
        local code=act.target and act.target._nw_trial_mode:value() or 0
        return code==0 and "TEN" or code==1 and "THIRTY" or code==2 and "COMBO" or "RESET"
    end
    env.AddAction(a)
    STRINGS.ACTIONS.NW_DUMMY_TRIAL={TEN=L.t("10秒测试"),THIRTY=L.t("30秒测试"),
        COMBO=L.t("连击"),RESET=L.t("重置")}
    a.fn=function(act) return act.target and act.target.prefab=="nw_spell_punchingbag" and M.select(act.target,act.doer) end
    env.AddComponentAction("SCENE","health",function(target,doer,actions,right)
        local inv=doer.replica and doer.replica.inventory or doer.components and doer.components.inventory
        local hand=inv and inv:GetEquippedItem(EQUIPSLOTS.HANDS)
        if right and not hand and target.prefab=="nw_spell_punchingbag" and not target:HasTag("burnt") then actions[#actions+1]=a end
    end)
    for _,sg in ipairs({"wilson","wilson_client"}) do env.AddStategraphActionHandler(sg,ActionHandler(a,"doshortaction")) end
end
return M
