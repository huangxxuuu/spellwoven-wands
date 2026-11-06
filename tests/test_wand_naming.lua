local M=require("nw/wand_naming")
TEXT_FILTER_CTX_CHAT=1;CanEntitySeeTarget=function() return true end
local player={userid="KU_name",components={health={IsDead=function() return false end}}}
function player:IsNear() return true end
function player:HasTag(t) return false end
local pencil={prefab="featherpencil",valid=true,components={}}
function pencil:IsValid() return self.valid end
local held=true;local used=0
pencil.components.inventoryitem={GetGrandOwner=function() return held and player or nil end}
pencil.components.stackable={Get=function() return {Remove=function() used=used+1 end} end}
local e={components={named={name="原名"},inspectable={},inventoryitem={}}}
function e:IsValid() return true end
function e:HasTag(t) return t=="nw_wand" or self.custom and t=="nw_customname" end
function e:AddTag(t) if t=="nw_customname" then self.custom=true end end
function e:GetBasicDisplayName() return "法杖" end
e.components.inventoryitem.GetGrandOwner=function() return player end
e.components.inventoryitem.IsHeld=function() return true end
e.components.named.SetName=function(self,name,author) self.name=name;self.author=author end
function e:AddComponent(id)
    assert(id=="writeable")
    local w={}
    function w:SetDefaultWriteable(v) self.default=v end
    function w:SetAutomaticDescriptionEnabled(v) self.auto=v end
    function w:SetOnWrittenFn(fn) self.written=fn end
    function w:SetOnWritingEndedFn(fn) self.ended=fn end
    function w:SetText(text) self.text=text end
    function w:BeginWriting(p) self.writer=p end
    function w:IsBeingWritten() return self.writer~=nil end
    function w:OnUpdate() self.checked=true end
    function w:EndWriting() self.writer=nil;self.ended(e) end
    self.components[id]=w
end
M.setup(e);local w=e.components.writeable
assert(not w.default and not w.auto and M.describe(e)=="原名")
w:BeginWriting(player);assert(not w.writer,"crafting must not open a free naming dialog")
local act={target=e,invobject=pencil,doer=player}
assert(M.begin(act) and w.text=="原名")
w:EndWriting();assert(used==0 and e.components.named.name=="原名")
assert(M.begin(act));w.written(e,"  星火\n法杖  ",player);w:EndWriting()
assert(M.describe(e)=="星火 法杖" and used==1 and e.components.named.author==player.userid)
for _,text in ipairs({"","   ","星火 法杖"}) do
    assert(M.begin(act));w.written(e,text,player);w:EndWriting()
    assert(used==1 and M.describe(e)=="星火 法杖")
end
assert(M.begin(act));held=false;w.written(e,"不能免费改名",player);w:EndWriting()
assert(used==1 and M.describe(e)=="星火 法杖" and not M.begin(act))
held=true;assert(M.begin(act));w:OnUpdate(1);assert(not w.checked)
e.components.inventoryitem.GetGrandOwner=function() return nil end
w:OnUpdate(1);assert(w.checked)
w:EndWriting()
e.components.inventoryitem.GetGrandOwner=function() return player end
e.components.named.name="入门法杖"
e.custom=false
player._nw_language="en"
assert(M.begin(act) and w.text=="Starter Wand")
w.written(e,"Starter Wand",player);w:EndWriting()
assert(used==1 and e.components.named.name=="入门法杖","translated default is not a paid rename")
e.components.named.name_author_netid="KU_author"
assert(M.begin(act) and w.text=="入门法杖","authored names must not be translated")
w:EndWriting()
print("wand naming: name-only inspection, native dialog guard, confirm/cancel, one pencil, no free rename after transfer")
