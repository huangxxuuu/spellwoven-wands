-- Persisted per shard. Items retain their origin ID when moved between shards.
local Identity = Class(function(self, inst)
    self.sequence = 0
end)
function Identity:Next()
    self.sequence = self.sequence + 1
    return table.concat({"nw", TheNet:GetSessionIdentifier(), TheShard:GetShardId(), self.sequence}, ":")
end
function Identity:Observe(id)
    if type(id)~="string" then return end
    local session,shard,sequence=id:match("^nw:([^:]+):([^:]+):(%d+)$")
    if session==TheNet:GetSessionIdentifier() and shard==tostring(TheShard:GetShardId()) then
        self.sequence=math.max(self.sequence,tonumber(sequence))
    end
end
function Identity:OnSave()
    return {sequence=self.sequence}
end
function Identity:OnLoad(data)
    self.sequence = math.max(self.sequence, data and data.sequence or 0)
end
return Identity
