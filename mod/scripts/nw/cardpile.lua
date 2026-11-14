local C=require("nw/constants/ui").cardpile
local T=require("nw/locale").t
local SIDE=C.side
local M={capacity=SIDE*SIDE,stride=C.stride}

function M.perform(act)
    local player,card,target=act.doer,act.invobject,act.target
    if not player or not player:IsValid() or not card or not card:IsValid()
        or not target or not target:IsValid() or target==card or target:HasTag("INLIMBO")
        or not player:IsNear(target,C.interaction_range) or not card:HasTag("nw_spellcard") then return false end
    local inv=player.components.inventory
    if not inv or inv:GetActiveItem()~=card or card.components.inventoryitem.owner~=player
        or not player.components.health or player.components.health:IsDead() then return false end
    local pile=target
    if target.prefab=="nw_spellcard" then
        if target.components.inventoryitem.owner then return false end
        pile=SpawnPrefab("nw_spellpile")
        if not pile then return false end
        pile.Transform:SetPosition(target.Transform:GetWorldPosition())
        local bottom=target.components.stackable:Get()
        if not pile.components.container:GiveItem(bottom,nil,nil,false) then pile:Remove();return false end
    elseif target.prefab~="nw_spellpile" or target.components.container:IsFull() then return false end

    card=inv:RemoveItem(card,false)
    if not card then return false end
    if not pile.components.container:GiveItem(card,nil,nil,false) then
        inv:GiveActiveItem(card)
        return false
    end
    return true
end

function M.collect(item,doer,target,actions,right)
    if right and item:HasTag("nw_spellcard") and not target:HasTag("INLIMBO")
        and (target:HasTag("nw_spellcard") or target:HasTag("nw_spellpile") and target._surface:value()<M.stride*M.capacity)
        and item~=target then
        table.insert(actions,ACTIONS.NW_PILE)
    end
end

function M.install(env)
    local containers=require("containers")
    local slots={}
    for row=0,SIDE-1 do
        for col=0,SIDE-1 do
            slots[#slots+1]=Vector3((col-C.centre)*C.slot_step,(C.centre-row)*C.slot_step,0)
        end
    end
    local widget={slotpos=slots,pos=Vector3(0,C.y,0),side_align_tip=C.tip,
        bgatlas="images/nw_frame.xml",bgimage="frame_2_2.tex",
        bganim_visualfn=function(anim)
            local bg=anim.parent.bgimage
            if not bg.nw_frame then
                bg:SetSize(C.background_size,C.background_size)
                bg.nw_frame=bg:AddChild(require("widgets/nw_wandframe")())
                bg.nw_frame:SetSize(C.frame_size,C.frame_size)
            end
        end}
    containers.params.nw_spellpile={type="chest",widget=widget,acceptsstacks=false,
        itemtestfn=function(_,item) return item:HasTag("nw_spellcard") end}
    containers.MAXITEMSLOTS=math.max(containers.MAXITEMSLOTS,M.capacity)
    local action=Action({priority=C.action_priority,rmb=true,distance=C.action_distance,silent_fail=true})
    action.id,action.str,action.fn="NW_PILE",T("叠放法术卡"),M.perform
    env.AddAction(action)
    env.AddComponentAction("USEITEM","stackable",M.collect)
    for _,sg in ipairs({"wilson","wilson_client"}) do
        env.AddStategraphActionHandler(sg,ActionHandler(action,"doshortaction"))
    end
end
return M
