local C=require("nw/constants/melee").work
local Credit=Class(function(self,inst)
    self.inst=inst;self.amounts={}
    if inst~=TheWorld then
        inst:ListenForEvent("picked",function() self.amounts.SCYTHE=nil end)
        inst:ListenForEvent("workfinished",function() self.amounts={} end)
    end
end)
function Credit:Take(key,n)
    local total=(self.amounts[key] or 0)+n
    local units=math.floor(total+C.credit_epsilon)
    self.amounts[key]=total-units>C.credit_epsilon and total-units or nil
    return units
end
function Credit:OnSave()
    if next(self.amounts) then return {add_component_if_missing=true,amounts=self.amounts} end
end
function Credit:OnLoad(data) self.amounts=data and data.amounts or {} end
return Credit
