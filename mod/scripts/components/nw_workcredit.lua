-- Store fractional tool strokes per object (or terrain location on the world).
-- Native Workable rounds a final sub-unit to a full stroke, so send whole
-- strokes only; four ordinary 0.75 strokes perform exactly three native hits.
local Credit=Class(function(self,inst)
    self.inst=inst;self.amounts={}
    if inst~=TheWorld then
        inst:ListenForEvent("picked",function() self.amounts.SCYTHE=nil end)
        inst:ListenForEvent("workfinished",function() self.amounts={} end)
    end
end)
function Credit:Take(key,n)
    local total=(self.amounts[key] or 0)+n
    local units=math.floor(total+.000001)
    self.amounts[key]=total-units>.000001 and total-units or nil
    return units
end
function Credit:OnSave()
    if next(self.amounts) then return {add_component_if_missing=true,amounts=self.amounts} end
end
function Credit:OnLoad(data) self.amounts=data and data.amounts or {} end
return Credit
