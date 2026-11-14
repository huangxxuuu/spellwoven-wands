local Glow=require("nw/projectile_glow")
local function make(native)
    return Prefab("nw_native_"..native,function()
        local inst=Prefabs[native].fn()
        inst._nw_native_prefab=native
        Glow.prepare_native(inst,native)
        if not TheWorld.ismastersim then
            local replicated=inst.OnEntityReplicated
            inst.OnEntityReplicated=function(self,...)
                if replicated then replicated(self,...) end
                Glow.native(self)
            end
        end
        return inst
    end,nil,{native})
end
return make("fire_projectile"),make("ice_projectile"),
    make("voidcloth_boomerang_proj"),make("tornado")
