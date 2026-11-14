local C=require("nw/constants/training").combo
local M={}
function M.accumulate(state,amount,now)
    if type(amount)~="number" or amount>=0 or amount~=amount or amount==-math.huge then return false end
    if not state.last_hit or now-state.last_hit>=C.reset_interval then state.total=0 end
    state.total=(state.total or 0)-amount
    state.last_hit=now
    return true
end
function M.digits(inst,total,quiet)
    local number=math.min(C.max_column_number,math.floor(total))
    for i=C.digit_columns,1,-1 do
        inst.AnimState:OverrideSymbol("column"..i,"punchingbag","number"..(number%10).."_black")
        number=math.floor(number/10)
    end
    inst._nw_combo_text:set(total>C.max_column_number and string.format("%.0f",math.floor(total)) or "")
    if inst._nw_combo_refresh then inst._nw_combo_refresh() end
    if not quiet and not (inst.components.burnable and inst.components.burnable:IsBurning()) then
        inst.SoundEmitter:PlaySound("farming/common/farm/veggie_scale/place")
    end
end
local function replace_listener(inst,event,fn)
    local callbacks=inst.event_listeners[event] and inst.event_listeners[event][inst]
    local old={};for _,callback in ipairs(callbacks or {}) do old[#old+1]=callback end
    for _,callback in ipairs(old) do inst:RemoveEventCallback(event,callback) end
    inst:ListenForEvent(event,fn)
end
function M.setup(inst)
    inst._nw_combo={total=0}
    require("nw/dummy_trials").setup(inst)
    local describe=inst.components.inspectable.descriptionfn
    inst.components.inspectable.descriptionfn=function(self,viewer,...)
        local original=describe and describe(self,viewer,...) or ""
        return (original or "").."\n"..require("nw/locale").for_player(viewer,
            "空手右键切换连击/10秒/30秒；测试中或结束后右键重置，再次右键切换。仅统计选定测试者。")
    end
    replace_listener(inst,"healthdelta",function(self,data)
        if data and M.accumulate(self._nw_combo,data.amount,GetTime()) then
            require("nw/dummy_trials").hit(self,self._nw_health_owner,-data.amount)
            M.digits(self,self._nw_combo.total)
        end
    end)
    replace_listener(inst,"blocked",function() end)
    local save,load=inst.OnSave,inst.OnLoad
    inst.OnSave=function(self,data)
        local refs=save and save(self,data)
        data.nw_combo_total=self._nw_combo.total
        return refs
    end
    inst.OnLoad=function(self,data,...)
        if load then load(self,data,...) end
        local total=data and data.nw_combo_total
        if type(total)=="number" and total>=0 and total<math.huge then self._nw_combo.total=total end
        self._nw_combo.last_hit=nil
        if not self:HasTag("burnt") then M.digits(self,self._nw_combo.total,true) end
    end
end
function M.visual(inst)
    local badge=CreateEntity()
    badge.entity:AddTransform();badge.entity:AddAnimState()
    badge:AddTag("FX");badge:AddTag("NOCLICK");badge.persists=false
    badge.entity:SetParent(inst.entity)
    badge.Transform:SetPosition(0,C.badge_height,0);badge.Transform:SetScale(C.badge_scale,C.badge_scale,C.badge_scale)
    badge.AnimState:SetBank("nw_objects");badge.AnimState:SetBuild("nw_objects")
    badge.AnimState:OverrideSymbol("sprite","nw_objects","nw_spell_spark")
    badge.AnimState:PlayAnimation("flight_spark",true)
    badge.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
    inst._nw_spark_badge=badge
    local label=CreateEntity()
    label.entity:AddTransform();label.entity:AddLabel()
    label:AddTag("FX");label:AddTag("NOCLICK");label.persists=false
    label.entity:SetParent(inst.entity)
    label.Label:SetFont(NUMBERFONT);label.Label:SetColour(unpack(C.label_colour))
    label.Label:SetWorldOffset(0,C.label_height,0)
    local function refresh()
        local trial=require("nw/dummy_trials").display(inst._nw_trial_text:value())
        local text=trial~="" and trial or inst._nw_combo_text:value()
        local overflow=text~=""
        for i=1,C.digit_columns do
            if overflow then inst.AnimState:HideSymbol("column"..i) else inst.AnimState:ShowSymbol("column"..i) end
        end
        label.Label:SetWorldOffset(0,trial~="" and C.trial_label_height or C.label_height,0)
        label.Label:SetFont(trial~="" and UIFONT or NUMBERFONT)
        if trial~="" then label.Label:SetColour(unpack(NORMAL_TEXT_COLOUR))
        else label.Label:SetColour(unpack(C.label_colour)) end
        label.Label:SetFontSize(trial~="" and C.trial_font_size or math.max(C.min_font_size,math.min(C.max_font_size,C.font_width/math.max(1,#text))))
        label.Label:SetText(text);label.Label:Enable(overflow and not inst:HasTag("burnt"))
    end
    inst._nw_combo_refresh=refresh
    inst:ListenForEvent("nw_combo_dirty",refresh);inst:ListenForEvent("nw_trial_dirty",refresh);refresh()
    inst:ListenForEvent("burnt",function() badge:Hide();label.Label:Enable(false) end)
    inst:ListenForEvent("onremove",function() badge:Remove();label:Remove() end)
end
return M
