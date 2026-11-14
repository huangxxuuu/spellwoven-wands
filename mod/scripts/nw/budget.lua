local M = {}
function M.new(per_player, per_shard)
    assert(per_player > 0 and per_shard >= per_player)
    local b = { used = 0, owners = {}, tokens = {}, next_id = 1, per_player = per_player, per_shard = per_shard }
    function b:reserve(owner, count)
        if type(owner) ~= "string" or type(count) ~= "number" or count < 0
            or count ~= math.floor(count) or count == math.huge then return nil, "INVALID_BUDGET" end
        local used = self.owners[owner] or 0
        if used + count > self.per_player or self.used + count > self.per_shard then return nil, "PROJECTILE_LIMIT" end
        local id = self.next_id
        self.next_id = id + 1
        self.tokens[id] = { owner = owner, pending = count, active = 0 }
        self.used, self.owners[owner] = self.used + count, used + count
        return id
    end
    function b:activate(id, count)
        local t = self.tokens[id]
        if not t or type(count) ~= "number" or count < 0 or count ~= math.floor(count)
            or count > t.pending then return false end
        t.pending, t.active = t.pending - count, t.active + count
        return true
    end
    function b:release(id, count, pending)
        local t = self.tokens[id]
        local key = pending and "pending" or "active"
        if not t or type(count) ~= "number" or count < 0 or count ~= math.floor(count)
            or count > t[key] then return false end
        t[key] = t[key] - count
        self.used = self.used - count
        self.owners[t.owner] = self.owners[t.owner] - count
        if self.owners[t.owner] == 0 then self.owners[t.owner] = nil end
        if t.pending + t.active == 0 then self.tokens[id] = nil end
        return true
    end
    function b:cancel(id)
        local t = self.tokens[id]
        if not t then return end
        local n = t.pending + t.active
        self.used = self.used - n
        self.owners[t.owner] = self.owners[t.owner] - n
        if self.owners[t.owner] == 0 then self.owners[t.owner] = nil end
        self.tokens[id] = nil
    end
    return b
end
return M
