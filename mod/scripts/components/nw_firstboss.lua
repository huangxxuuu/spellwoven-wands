local FirstBoss=Class(function(self,inst)
    self.inst=inst
    self.claimed=false
end)
function FirstBoss:OnSave() return {claimed=self.claimed} end
function FirstBoss:OnLoad(data) self.claimed=data and data.claimed==true or false end
return FirstBoss
