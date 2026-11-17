local C=require("nw/constants/cast_binding")
local Key=require("nw/cast_key")
local Binding=Class(function(self,inst)
    self.inst=inst
    self.revision=0
end)
function Binding:Get()
    return self.override or self.default
end
function Binding:Initialize(value)
    if self.default or not Key.valid(value) then return false end
    self.default=value
    return true
end
function Binding:Set(value,revision)
    if not self.default or revision~=self.revision or (value~=nil and not Key.valid(value)) then return false end
    if value~=self.override then
        -- Never wrap a revision and accidentally accept an ancient request.
        if self.revision>=C.max_integer then return false end
        self.override=value
        self.revision=self.revision+1
        self.inst:PushEvent("nw_cast_binding_dirty")
    end
    return true
end
function Binding:OnSave()
    if not self.default then return end
    return {version=C.version,default=self.default,override=self.override,revision=self.revision}
end
function Binding:OnLoad(data)
    if type(data)~="table" or data.version~=C.version or not Key.valid(data.default) then return end
    self.default=data.default
    self.override=Key.valid(data.override) and data.override or nil
    local revision=data.revision
    self.revision=type(revision)=="number" and revision>=0 and revision<=C.max_integer
        and revision==math.floor(revision) and revision or 0
end
return Binding
