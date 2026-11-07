-- DST keeps one collector per mod/action type/component: later writes replace it.
local collectors={}
local containers={params={},MAXITEMSLOTS=0}
package.loaded.containers=containers
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
Action=function(options) return options end
ActionHandler=function(action,state) return {action=action,state=state} end
ACTIONS={}
local env={
    AddAction=function(action) ACTIONS[action.id]=action end,
    AddStategraphActionHandler=function() end,
    AddComponentAction=function(kind,component,fn)
        collectors[kind]=collectors[kind] or {}
        collectors[kind][component]=fn
    end,
}
-- Match modmain order, including the repair action registered after the pile.
require("nw/cardpile").install(env)
require("nw/wand_damage").install(env)
local function entity(prefab,tags,surface)
    return {prefab=prefab,HasTag=function(_,tag) return tags[tag]==true end,
        _surface={value=function() return surface or 0 end}}
end
local function offered(item,target,right)
    local actions={}
    -- Both cards and dust have these native action components on clients.
    for _,component in ipairs({"stackable","inventoryitem"}) do
        local collect=collectors.USEITEM[component]
        if collect then collect(item,{},target,actions,right) end
    end
    return actions
end
local card=entity("nw_spellcard",{nw_spellcard=true})
local floor=entity("nw_spellcard",{nw_spellcard=true})
local pile=entity("nw_spellpile",{nw_spellpile=true},256*2+1)
local actions=offered(card,floor,true)
assert(#actions==1 and actions[1]==ACTIONS.NW_PILE,"repair registration hid the pile action")
assert(offered(card,pile,true)[1]==ACTIONS.NW_PILE)
assert(#offered(card,floor,false)==0)
assert(#offered(card,card,true)==0)
assert(#offered(card,entity("nw_spellcard",{nw_spellcard=true,INLIMBO=true}),true)==0)
assert(#offered(card,entity("nw_spellpile",{nw_spellpile=true},256*25+1),true)==0)
local dust=entity("nw_dust",{})
local broken=entity("nw_wand",{nw_broken=true})
actions=offered(dust,broken,true)
assert(#actions==1 and actions[1]==ACTIONS.NW_REPAIR,"pile registration hid repair")
assert(#offered(dust,floor,true)==0 and #offered(card,broken,true)==0)
assert(#offered(dust,broken,false)==0)
print("card pile actions: creation, adding, capacity, limbo, mouse button and wand repair coexist")
