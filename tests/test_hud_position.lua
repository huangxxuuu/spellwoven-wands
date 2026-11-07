local Layout=require("nw/hud_layout")
local Position=require("nw/hud_position")
local load_cb,writes,stored=nil,{},nil
package.loaded.json={encode=function(v) return string.format("%d,%g,%g",v.version,v.x,v.y) end,
    decode=function(s)
        local v,x,y=s:match("^(%d+),([%d%.]+),([%d%.]+)$")
        assert(v,"invalid JSON stand-in")
        return {version=tonumber(v),x=tonumber(x),y=tonumber(y)}
    end}
TheSim={GetPersistentString=function(_,key,cb) assert(key==Position.key);load_cb=cb end,
    SetPersistentString=function(_,key,value,encode,cb)
        assert(key==Position.key and not encode);writes[#writes+1]={value=value,cb=cb}
    end}
for _,v in ipairs({{}, {version=2,x=.5,y=.5},{version=1,x=0/0,y=.5},
    {version=1,x=math.huge,y=.5},{version=1,x=-1,y=.5}}) do assert(not Position.validate(v)) end
local restored
Position.load(function(p) restored=p end)
Position.save({version=1,x=.2,y=.4})
Position.save({version=1,x=.8,y=.7})
assert(#writes==1,"serialize asynchronous writes")
load_cb(true,"1,0.1,0.1")
assert(restored.x==.8,"late disk read must not overwrite a new drag")
writes[1].cb();assert(#writes==2 and writes[2].value=="1,0.8,0.7")
stored=writes[2].value;writes[2].cb()
package.loaded["nw/hud_position"]=nil
local Restarted=require("nw/hud_position")
Restarted.load(function(p) restored=p end);load_cb(true,stored)
assert(restored.x==.8 and restored.y==.7,"restart lost position")
package.loaded["nw/hud_position"]=nil
require("nw/hud_position").load(function(p) restored=p end);load_cb(true,"corrupt save")
assert(restored==nil,"corrupt preferences should fall back to default")
for count=2,12 do
    local width,bottom,top=Layout.bounds(count)
    for _,screen in ipairs({{1280,720},{1920,1080},{2560,1080}}) do
        for _,scale in ipairs({.7,1,1.5}) do
            local sw,sh=screen[1],screen[2]
            scale=scale*math.min(1,(sw-12)/(width*scale))
            for _,p in ipairs({{-100,-100},{sw+100,sh+100},{sw/2,sh/2}}) do
                local x,y=Position.clamp(p[1],p[2],width*scale,bottom*scale,top*scale,sw,sh)
                assert(x-width*scale/2>=5.99 and x+width*scale/2<=sw-5.99)
                assert(y+bottom*scale>=5.99 and y+top*scale<=sh-5.99)
            end
        end
    end
    for i=1,count do assert(Layout.slot_at((i-(count+1)/2)*Layout.slot_step,0,count)==i) end
    for i=1,count-1 do
        assert(not Layout.slot_at((i-count/2)*Layout.slot_step,0,count),"slot gaps must not select cards")
    end
    assert(not Layout.slot_at(0,56,count),"header should remain draggable")
end
local fill,progress,state=Layout.state(50,200,75,100,true)
assert(fill==.25 and progress==.25 and state=="cooling")
assert(select(3,Layout.state(0,200,0,100,false))=="blocked")
assert(select(3,Layout.state(10,200,0,100,true))=="ready")
print("HUD: every 2-12 capacity, scaled screen bounds, fixed gauge semantics, restart/corrupt/async save ordering")
