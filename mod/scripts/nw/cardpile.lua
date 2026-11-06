local T=require("nw/locale").t
local SIDE=5
local M={capacity=SIDE*SIDE,stride=256}

-- A pile contains the real card entities. Their UIDs, source and spell are
-- saved by the native container, including when two spells have the same name.
function M.perform(act)
    local player,card,target=act.doer,act.invobject,act.target
    if not player or not player:IsValid() or not card or not card:IsValid()
        or not target or not target:IsValid() or target==card or target:HasTag("INLIMBO")
        or not player:IsNear(target,3) or not card:HasTag("nw_spellcard") then return false end
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
            slots[#slots+1]=Vector3((col-2)*80,(2-row)*80,0)
        end
    end
    local widget={slotpos=slots,pos=Vector3(0,200,0),side_align_tip=240,
        bgatlas="images/nw_frame.xml",bgimage="frame_2_2.tex",
        bganim_visualfn=function(anim)
            local bg=anim.parent.bgimage
            if not bg.nw_frame then
                bg:SetSize(388,388)
                bg.nw_frame=bg:AddChild(require("widgets/nw_wandframe")())
                bg.nw_frame:SetSize(420,420)
            end
        end}
    containers.params.nw_spellpile={type="chest",widget=widget,acceptsstacks=false,
        itemtestfn=function(_,item) return item:HasTag("nw_spellcard") end}
    containers.MAXITEMSLOTS=math.max(containers.MAXITEMSLOTS,M.capacity)
    local action=Action({priority=6,rmb=true,distance=2,silent_fail=true})
    action.id,action.str,action.fn="NW_PILE",T("叠放法术卡"),M.perform
    env.AddAction(action)
    env.AddComponentAction("USEITEM","inventoryitem",M.collect)
    for _,sg in ipairs({"wilson","wilson_client"}) do
        env.AddStategraphActionHandler(sg,ActionHandler(action,"doshortaction"))
    end
end
return M
