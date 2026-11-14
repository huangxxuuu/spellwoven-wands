local C=require("nw/constants/ui").nw_wandframe
local Widget=require("widgets/widget")
local Image=require("widgets/image")

local Frame=Class(Widget,function(self)
    Widget._ctor(self,"nw_wandframe")
    self.pieces={}
    for row=1,3 do
        for col=1,3 do
            local center=row==2 and col==2
            local piece=self:AddChild(Image(center and "images/global.xml" or "images/nw_frame.xml",
                center and "square.tex" or string.format("frame_%d_%d.tex",row,col)))
            if center then piece:SetTint(unpack(C.fill_colour)) end
            piece:SetClickable(false)
            self.pieces[#self.pieces+1]=piece
        end
    end
end)
function Frame:SetSize(width,height)
    local edge=C.edge
    local widths={edge,width-edge*2,edge}
    local heights={edge,height-edge*2,edge}
    local xs={-width/2+edge/2,0,width/2-edge/2}
    local ys={height/2-edge/2,0,-height/2+edge/2}
    for row=1,3 do
        for col=1,3 do
            local piece=self.pieces[(row-1)*3+col]
            piece:SetSize(widths[col],heights[row])
            piece:SetPosition(xs[col],ys[row])
        end
    end
end
return Frame
