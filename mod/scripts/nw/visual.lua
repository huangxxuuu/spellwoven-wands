local M = {}
M.lengths = {"short","medium","long"}
M.heads={"crystal_1","crystal_2","crystal_3","plain_1","plain_2","plain_3"}
M.tails={"drop","diamond","round"}
M.colors={"red","blue","green"}
M.fast_regen=25
M.scale={short=1.88,medium=1.72,long=1.60}
M.held_multiplier=1.2
local head_count=#M.heads*#M.colors
local tail_count=#M.tails*#M.colors
M.styles=9
M.per_style=head_count*#M.lengths*tail_count
M.count=M.styles*M.per_style
M.cosmetic_rolls=18*M.styles
function M.atlas(code)
    return "images/inventoryimages/nw_wand_parts.xml"
end
function M.parts(code)
    local style=math.floor(code/M.per_style)+1
    code=code%M.per_style
    local head=math.floor(code/(#M.lengths*tail_count))
    local length=math.floor(code/tail_count)%#M.lengths
    local tail=code%tail_count
    return "head_"..M.heads[math.floor(head/3)+1].."_"..M.colors[head%3+1],
        M.lengths[length+1],"tail_"..M.tails[math.floor(tail/3)+1].."_"..M.colors[tail%3+1],
        string.format("body_%02d_%s",style,M.lengths[length+1])
end
function M.icon(code,broken) return "nw_wand_"..code..(broken and "_broken" or "") end
function M.icon_parts(code,broken)
    local head,length,tail,body=M.parts(code)
    return {body..".tex",tail.."_"..length..".tex",head..(broken and "_broken" or "").."_"..length..".tex"}
end
function M.apply(inst, code, pose, broken)
    local head,length,tail,body=M.parts(code)
    inst.AnimState:SetBank("nw_parts")
    inst.AnimState:SetBuild("nw_parts")
    inst.AnimState:PlayAnimation(pose.."_"..length,true)
    inst.AnimState:OverrideSymbol("head","nw_parts",head..(broken and "_broken" or ""))
    inst.AnimState:OverrideSymbol("body","nw_parts",body)
    inst.AnimState:OverrideSymbol("tail","nw_parts",tail)
    if pose=="ground" then
        inst.AnimState:OverrideSymbol("contact_grass","swap_cane","grass")
    end
end
function M.apply_dropped(inst,look,floating)
    if floating==nil then
        floating=inst.components.floater and inst.components.floater:IsFloating()
    end
    M.apply(inst,look,floating and "floating" or "ground",inst._nw_broken and inst._nw_broken:value())
end
local function code_for(stats,roll,style)
    local length=stats.capacity<=4 and 0 or stats.capacity<=8 and 1 or 2
    local head_shape=(stats.shuffle and 3 or 0)+math.min(stats.draw_count or 1,3)-1
    local tail_shape=stats.mana_regen>=M.fast_regen and 2 or math.floor(roll/9)
    local head=head_shape*3+roll%3
    local tail=tail_shape*3+math.floor(roll/3)%3
    return (style-1)*M.per_style+(head*#M.lengths+length)*tail_count+tail
end

function M.recipe_code(tier)
    local grade=math.max(1,tier)
    return code_for({capacity=4*grade,draw_count=grade,mana_regen=18},
        (grade-1)*4,({1,2,9})[grade])
end

-- Roll encodes independent head colour (3), tail colour (3) and slow-tail shape (2).
function M.appearance(stats,cosmetic)
    local roll,style=cosmetic%18,math.floor(cosmetic/18)+1
    local head,length,tail,body=M.parts(code_for(stats,roll,style))
    return {appearance_schema=3,roll=roll,shaft_style=style,head_id=head,body_id=body,
        tail_id=tail,length_class=length}
end
function M.from_data(data)
    return code_for(data.stats,data.appearance.roll,data.appearance.shaft_style)
end
function M.upgrade(data)
    local roll=type(data.appearance)=="table" and data.appearance.roll
    local style=type(data.appearance)=="table" and data.appearance.shaft_style
    local valid_roll=type(roll)=="number" and roll==math.floor(roll) and roll>=0 and roll<18
    local valid_style=type(style)=="number" and style==math.floor(style) and style>=1 and style<=M.styles
    if not valid_roll or not valid_style then
        -- Stable even if an old wand is loaded twice before the next world save.
        local hash=1
        local uid=tostring(data.wand_uid or data.origin_seed or data.seed or 1)
        for i=1,#uid do hash=(hash*31+uid:byte(i))%2147483647 end
        if not valid_roll then roll=hash%18 end
        if not valid_style then style=math.floor(hash/18)%M.styles+1 end
    end
    data.appearance=M.appearance(data.stats,roll+18*(style-1))
end
return M
