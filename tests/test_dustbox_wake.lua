-- The engine animation clock is controlled here to reproduce a missed
-- completion event. Exercise the real prefab's callbacks, not a copied rig.
local noop=function() end
package.loaded["nw/arcane_storage"]={
    atlas="images/inventoryimages/nw_arcane_storage.xml",
    DUSTBOX_SCALE=1,
    Count=function(container) return container.count or 0 end,
    StateForCount=function(count) return count==0 and "empty" or count<=80 and "half" or "full" end,
    Watch=function(inst,callback) inst.refresh=callback end,
}
TheWorld={ismastersim=true}
Asset=function(...) return {...} end
Prefab=function(name,fn) return {name=name,fn=fn} end
MakeInventoryPhysics=noop
MakeInventoryFloatable=noop
MakeHauntableLaunch=noop

function CreateEntity()
    local inst={components={},events={},tags={}}
    inst.entity={AddTransform=noop,AddAnimState=noop,AddSoundEmitter=noop,
        AddNetwork=noop,SetPristine=noop}
    inst.AnimState={plays=0,done=false,SetBank=noop,SetBuild=noop,SetRayTestOnBB=noop,SetScale=noop,
        PlayAnimation=function(self,name)
            self.current=name;self.plays=self.plays+1;self.done=false
        end,
        AnimDone=function(self) return self.done end}
    inst.SoundEmitter={PlaySound=noop}
    function inst:AddTag(tag) self.tags[tag]=true end
    function inst:ListenForEvent(event,callback) self.events[event]=callback end
    function inst:AddComponent(name)
        if name=="inventoryitem" then
            self.components[name]={ChangeImageName=function(c,image) c.image=image end,
                SetOnPutInInventoryFn=function(c,callback) c.onputininventoryfn=callback end}
        elseif name=="container" then
            local c={inst=self,count=0,opened=false,WidgetSetup=noop,EnableInfiniteStackSize=noop}
            function c:IsOpen() return self.opened end
            function c:Open() self.opened=true;self.onopenfn(self.inst) end
            function c:Close() self.opened=false;self.onclosefn(self.inst) end
            self.components[name]=c
        else
            self.components[name]={}
        end
    end
    return inst
end

local prefab=require("prefabs/nw_dustbox")
local box=prefab.fn()
local c=box.components.container
local function fill(count)
    c.count=count
    local state=require("nw/arcane_storage").StateForCount(count)
    box.refresh(box,state,count)
end

fill(81)
c:Open()
assert(box.AnimState.current=="open_full")
local plays=box.AnimState.plays
box:OnEntityWake()
assert(box.AnimState.plays==plays,"waking must not restart an unfinished opening")

fill(80)
box.AnimState.done=true -- no animover event was delivered
box:OnEntityWake()
assert(box.AnimState.current=="opened_half","finished opening uses latest contents")
assert(box.components.inventoryitem.image=="nw_dustbox_open_half")

c:Close()
fill(0)
plays=box.AnimState.plays
box:OnEntityWake()
assert(box.AnimState.plays==plays,"waking must not restart an unfinished closing")
box.AnimState.done=true
box:OnEntityWake()
assert(box.AnimState.current=="closed_empty","finished closing recovers without animover")
plays=box.AnimState.plays
box:OnEntityWake()
assert(box.AnimState.plays==plays,"stable closed pose must not replay on wake")

fill(1)
c:Open()
box.AnimState.done=true;box:OnEntityWake()
c:Close();c:Open()
plays=box.AnimState.plays
box:OnEntityWake()
assert(box.AnimState.plays==plays,"reopen request must preserve the active close motion")
box.AnimState.done=true;box:OnEntityWake()
assert(box.AnimState.current=="open_half","completed close must honor a pending reopen")
box.AnimState.done=true;box:OnEntityWake()
assert(box.AnimState.current=="opened_half")
print("dustbox wake: missed completion, unfinished motion, latest fill and pending reopen passed")
