local L=require("nw/locale")
for _,code in ipairs({"zh","zht","zhr","zh-CN","zh_TW","chs","cht","schinese","tchinese"}) do
    assert(L.resolve("auto",code)=="zh",code)
end
for _,code in ipairs({"en","fr","de","ru","ja","ko","unknown"}) do assert(L.resolve("auto",code)=="en") end
assert(L.resolve("auto",nil)=="en")
assert(L.resolve("zh","en")=="zh" and L.resolve("en","zh")=="en")
L.configure("en","zh")
assert(L.t("火花弹")=="Spark Bolt")
assert(L.for_player({_nw_language="zh"},"Spark Bolt")=="火花弹")
assert(L.for_player({_nw_language="en"},"稀有 · 编织法杖")=="Rare · Weaver Wand")
assert(L.translate("My custom wand 甲")=="My custom wand 甲")
local info=require("nw/spell_info")
assert(info.names.spark=="Spark Bolt" and info.names.spark_hit=="Spark Bolt · Collision")
assert(info.effects.homing:find("50 units/s",1,true))
assert(info.tooltip("spark")=="Fires a light magical spark.")
local rules=require("nw/acquisition")
for _,row in ipairs(rules.menu_entries) do
    assert(not row.title:find("[\228-\233]"),"untranslated crafting title")
end
local env={}
local hook,rpc,post
env.GetModConfigData=function(key,local_only) assert(key=="language" and local_only);return "auto" end
env.AddModRPCHandler=function(_,_,fn) rpc=fn end
env.AddPlayerPostInit=function(fn) post=fn end
env.AddComponentPostInit=function(name,fn) assert(name=="inspectable");hook=fn end
L.install(env,{require=function() return {GetLocaleCode=function() return "en" end} end})
local player={}
rpc(player,"invalid");assert(player._nw_language==nil)
rpc(player,"zh");assert(player._nw_language=="zh")
local component={inst={prefab="nw_wand"},GetDescription=function() return "Starter Wand",1,nil end}
component.inst.HasTag=function() return false end
hook(component)
assert(component:GetDescription(player)=="入门法杖")
component.inst.prefab="axe";assert(component:GetDescription(player)=="Starter Wand","native descriptions untouched")
local custom={inst={prefab="nw_wand"},GetDescription=function() return "Starter Wand",1,"author" end}
hook(custom);assert(custom:GetDescription(player)=="Starter Wand","custom names untouched")
print("locale: auto/overrides, mixed-language inspection, custom-name preservation, English cards and crafting")
