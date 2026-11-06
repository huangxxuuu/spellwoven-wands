local Widget=require("widgets/widget")
local Image=require("widgets/image")

-- Each image owns its final rectangle. No inherited dialog tints, crowns or
-- scale overrides: all four wooden corners stay 16 HUD pixels at every capacity.
local Frame=Class(Widget,function(self)
    Widget._ctor(self,"nw_wandframe")
    self.pieces={}
    for row=1,3 do
        for col=1,3 do
            self.pieces[#self.pieces+1]=self:AddChild(Image("images/nw_frame.xml",
                string.format("frame_%d_%d.tex",row,col)))
        end
    end
end)
function Frame:SetSize(width,height)
    local edge=16
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
