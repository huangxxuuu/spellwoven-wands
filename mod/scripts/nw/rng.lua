local M = {}
function M.new(seed)
    assert(type(seed) == "number" and seed >= 1 and seed <= 2147483646 and seed == math.floor(seed), "invalid seed")
    local rng = { state = seed }
    function rng:next()
        self.state = (self.state * 16807) % 2147483647
        return (self.state - 1) / 2147483646
    end
    function rng:int(n)
        assert(n >= 1 and n == math.floor(n), "invalid random range")
        return math.floor(self:next() * n) + 1
    end
    -- Reserve one seed, then advance an independent stream. Delayed payloads
    -- must not mutate the wand's next draw/shuffle state after cast commit.
    function rng:fork()
        self:next()
        return M.new(2147483647-self.state)
    end
    function rng:shuffle(list)
        for i = #list, 2, -1 do
            local j = self:int(i)
            list[i], list[j] = list[j], list[i]
        end
    end
    return rng
end
return M
