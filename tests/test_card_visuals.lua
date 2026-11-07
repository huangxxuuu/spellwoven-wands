local G=require("nw/ground_card")
local Cards=require("nw/cards")
local V=require("nw/card_visuals")
ANIM_ORIENTATION={BillBoard=7}
LAYER_BACKGROUND=1
Asset=function(kind,path) return {kind=kind,path=path} end
local highest=0;for _,code in pairs(Cards.codes) do highest=math.max(highest,code) end
assert(#G.assets()==math.ceil(highest/V.page_size)+1)
local function surface(slots)
    return G.surface({GetNumSlots=function() return 25 end,
        GetItemInSlot=function(_,i) return slots[i] and {spell_id=slots[i]} end})
end
local top,layout=surface({[2]="repeat_2",[5]="speed_up",[9]="fire",[12]="speed_down"})
assert(top==Cards.codes.repeat_2 and G.sequence(4,layout)=="HR")
assert(math.floor(layout/9)==1)
top,layout=surface({[1]="fire",[3]="repeat_2",[8]="speed_up"})
assert(top==Cards.codes.fire and G.sequence(3,layout)=="NH")
assert(math.floor(layout/9)==0)
top,layout=surface({[4]="fire",[7]="speed_up"})
assert(G.sequence(2,layout)=="H")
local state={SetBuild=function(self,b) self.build=b end,SetOrientation=function(_,v) assert(v==7) end,
    SetLayer=function(_,v) assert(v==LAYER_BACKGROUND) end,SetSortOrder=function(_,v) assert(v==3) end,
    OverrideSymbol=function(self,s,b,source) assert(s=="face");self.facebank=b;self.face=source end,
    SetBankAndPlayAnimation=function(self,b,clip) assert(b==self.build);self.clip=clip end}
for _,id in ipairs(Cards.order) do
    assert(V.cards[id] and V.cards[id].shape)
    for _,n in ipairs({1,2,3,4,8,9,25}) do
        for bits=0,26 do
            G.show({AnimState=state},Cards.codes[id],n,bits)
            assert(state.clip==G.pose(Cards.codes[id],n,bits))
            assert(state.build=="nw_card_piles")
            assert(state.face=="face_"..id)
            assert(state.facebank=="nw_card_faces_"..math.floor((Cards.codes[id]-1)/V.page_size))
        end
    end
end
G.show({AnimState=state},193,1)
assert(state.face=="face_target_players_other")
local c=Cards.codes.fire
assert(G.pose(c,2,1)=="two_RH")
assert(G.pose(c,3,2+3)=="three_RNH")
assert(G.pose(c,8,0)=="medium_RRR_plain")
assert(G.pose(c,8,9)=="medium_RRR_hex")
assert(G.pose(c,9,0)=="large_RRR_plain")
assert(G.pose(c,9,9)=="large_RRR_one_hex")
assert(G.pose(c,9,18,false)=="large_RRR_hex_adjacent")
assert(G.pose(c,25,18,true)=="large_RRR_hex_separated")
local _,packed=surface({[2]="speed_up",[4]="speed_down",[5]="repeat_2",[6]="speed_up",[8]="speed_down",[25]="speed_up"})
assert(math.floor(packed/9)==2 and G.sequence(9,packed)=="HN")
assert(require("nw/arsenal").notes.ocarina_a2.label=="A")
assert(require("nw/arsenal").notes.kantele_dsharp.label=="C")
assert(require("nw/arsenal").notes.kantele_dsharp.pitch==12)
print("card visuals: slot order, hidden slots, two-card stacks, all selectors, retired IDs and labels passed")
