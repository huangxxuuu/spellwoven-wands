-- Each row is {minimum, maximum, centre, standard deviation}. No point budget.
local M={keys={"capacity","mana_max","mana_regen","cast_delay","recharge","spread"}}
M.bounds={capacity={2,12,1},mana_max={24,1200,5},mana_regen={2,320,1},
    cast_delay={.08,2.4,.01},recharge={.10,6,.01},spread={0,15,.5},draw_count={1,6,1}}
M.tiers={
    {capacity={3,7,5,1},mana_max={80,240,140,35},mana_regen={12,45,25,7},
        cast_delay={.5,1.4,.85,.18},recharge={.7,2.6,1.5,.35},spread={1,12,6,2.5},shuffle=.50,always=0},
    {capacity={4,9,6,1.15},mana_max={120,450,240,65},mana_regen={20,90,45,14},
        cast_delay={.32,1.05,.60,.14},recharge={.4,1.9,1.05,.28},spread={0,10,4,2},shuffle=.35,always=0},
    {capacity={6,11,8,1.15},mana_max={200,800,420,120},mana_regen={35,180,85,28},
        cast_delay={.20,.75,.40,.10},recharge={.22,1.3,.65,.20},spread={0,8,2.5,1.5},shuffle=.20,always=.10},
    {capacity={8,12,10,1},mana_max={320,1200,700,180},mana_regen={60,320,150,45},
        cast_delay={.20,.55,.28,.07},recharge={.10,.9,.40,.14},spread={0,6,1.5,1.2},shuffle=.10,always=.25},
}
-- Centre offsets are in units of the tier's standard deviation. Types stay
-- within the tier's range, including their intentional weaknesses.
M.types={
    sprout={width=.75,shuffle=false,offset={},draw={55,22,12,6,3,2}},
    rapid={offset={cast_delay=-1,recharge=-.6,mana_regen=.7,mana_max=-.6,capacity=-.6},draw={70,18,7,3,1.5,.5}},
    reservoir={offset={mana_max=1.25,mana_regen=-.6,recharge=.7},draw={40,25,16,10,6,3}},
    renewal={offset={mana_regen=1.3,mana_max=-.7,cast_delay=.35},draw={60,22,10,5,2,1}},
    weaver={shuffle=false,offset={capacity=1.3,cast_delay=.6,recharge=.35},draw={65,18,9,5,2,1}},
    chaos={shuffle=true,offset={mana_max=.6,cast_delay=-.5,spread=1},draw={10,20,25,22,15,8}},
}
function M.distribution(tier,kind,key)
    local row=assert(M.tiers[tier],"invalid tier")[key]
    local profile=assert(M.types[kind],"invalid archetype")
    return row[1],row[2],row[3]+(profile.offset[key] or 0)*row[4],row[4]*(profile.width or 1),M.bounds[key][3]
end
return M
