local M={}
function M.begin()
    M.sample={queries=0,effect_queries=0,melee=0,candidates=0,visits=0,steps=0,position_writes=0}
end
function M.finish() local s=M.sample;M.sample=nil;return s end
return M
