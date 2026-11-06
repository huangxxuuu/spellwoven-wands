local M={}
function M.run()
    TheWorld:PushEvent("ms_setclocksegs",{day=16,dusk=0,night=0})
    local player=SpawnPrefab("wilson");player.entity:SetCanSleep(false)
    player.components.health:SetInvincible(true)
    for _,e in pairs(Ents) do if e:HasTag("multiplayer_portal") then player.Physics:Teleport(e.Transform:GetWorldPosition());break end end
    local Kit=require("nw/test_scene_kit")
    local result=assert(Kit.spawn("all",player),"NW_SCENES: not enough clear ground")
    assert(#result.signs==17 and #result.boxes==23 and #result.stations==3,"NW_SCENES: incomplete camp")
    local roles={A=0,B=0}
    for _,box in ipairs(result.boxes) do
        for role in pairs(roles) do
            if box.components.named.name:find(role.." 玩家用品",1,true) then
                roles[role]=roles[role]+1
                assert(box.components.container:NumItems()==9,"NW_SCENES: incomplete role supplies")
            end
        end
    end
    assert(roles.A==5 and roles.B==5,"NW_SCENES: missing A/B boxes")
    local count=0
    for _,box in ipairs(result.boxes) do
        for _,v in pairs(box.components.container.slots) do
            count=count+1
            if v.prefab=="nw_spellcard" then
                assert(v.components.inspectable.description==require("nw/cards").names[v.spell_id],"NW_SCENES: long card inspection")
            elseif v.prefab=="nw_wand" then
                assert(v.components.inspectable.getspecialdescription(v)==v.components.named.name,"NW_SCENES: long wand inspection")
                assert(v.components.nw_wand:PreviewCast(),"NW_SCENES: invalid prepared loadout")
            end
        end
    end
    local first=result.boxes[1]
    local localized=SpawnPrefab("nw_wand")
    localized.components.nw_wand:InitializeNew(0,"debug")
    player._nw_language="en"
    assert(localized.components.inspectable:GetDescription(player)=="Starter Wand","NW_SCENES: English inspection")
    player._nw_language="zh"
    assert(localized.components.inspectable:GetDescription(player)=="入门法杖","NW_SCENES: Chinese inspection")
    localized.components.named:SetName("My Wand 星火", "KU_test")
    assert(localized:GetBasicDisplayName()=="My Wand 星火","NW_SCENES: custom name changed")
    localized:Remove()
    player._nw_language=nil
    local wand=first.components.container:RemoveItemBySlot(1)
    player.components.inventory:GiveItem(wand)
    local pencil=first.components.container:RemoveItemBySlot(4)
    player.components.inventory:GiveItem(pencil)
    assert(pencil.prefab=="featherpencil")
    local actions={};pencil:CollectActions("USEITEM",player,wand,actions,true)
    local found=false;for _,a in ipairs(actions) do if a==ACTIONS.NW_RENAME then found=true end end
    assert(found,"NW_SCENES: pencil action unavailable")
    local act={doer=player,target=wand,invobject=pencil}
    local w=wand.components.writeable
    local n=pencil.components.stackable:StackSize()
    assert(ACTIONS.NW_RENAME.fn(act));w:Write(player,nil)
    assert(pencil.components.stackable:StackSize()==n,"NW_SCENES: cancel consumed pencil")
    assert(ACTIONS.NW_RENAME.fn(act));w:Write(player,"星火测试杖")
    assert(wand.components.named.name=="星火测试杖" and pencil.components.stackable:StackSize()==n-1,"NW_SCENES: native rename")
    assert(wand.components.inspectable:GetDescription(player)=="星火测试杖","NW_SCENES: inspection did not follow rename")
    assert(ACTIONS.NW_RENAME.fn(act));w:Write(player,string.rep("字",33))
    assert(wand.components.named.name=="星火测试杖" and pencil.components.stackable:StackSize()==n-1,"NW_SCENES: name length guard")
    w:EndWriting()
    local px,_,pz=player.Transform:GetWorldPosition()
    player.components.inventory:DropItem(wand,true,true)
    wand.Physics:Teleport(px+1,0,pz)
    assert(ACTIONS.NW_RENAME.fn(act));w:Write(player,"落地命名杖")
    assert(wand.components.named.name=="落地命名杖" and pencil.components.stackable:StackSize()==n-2,"NW_SCENES: ground rename")
    wand.components.nw_wand:UpdateTime()
    local saved=wand:GetSaveRecord();wand:Remove()
    local restored=assert(SpawnSaveRecord(saved))
    assert(restored.components.named.name=="落地命名杖" and restored.components.nw_wand.data,"NW_SCENES: renamed save")
    assert(restored:HasTag("nw_customname"),"NW_SCENES: custom-name localization flag lost on save")
    restored:Remove()
    local sign=result.signs[1];local text=sign.components.writeable:GetText()
    local record=sign:GetSaveRecord();sign:Remove()
    sign=assert(SpawnSaveRecord(record));assert(sign.components.writeable:GetText()==text,"NW_SCENES: sign save")
    sign:Remove()
    local eggs=assert(Kit.cleanup(1,player));assert(#eggs==1 and eggs[1]._nw_motion,"NW_SCENES: cleanup fixture")
    eggs[1]:Remove()
    for _,group in pairs(result) do for _,e in ipairs(group) do if e:IsValid() then e:Remove() end end end
    local duo=assert(Kit.spawn("duo",player),"NW_SCENES: duo selector failed")
    assert(#duo.boxes==10 and #duo.signs==5 and #duo.stations==1,"NW_SCENES: duo pack counts")
    for _,group in pairs(duo) do for _,e in ipairs(group) do if e:IsValid() then e:Remove() end end end
    player:Remove()
    print("NW_SCENES_PASS: 17 scenarios, 23 filled boxes including five A/B pairs, saved signs, native pencil action, cancel/commit/length, name-only inspection and rename save; supplies",count)
end
return M
