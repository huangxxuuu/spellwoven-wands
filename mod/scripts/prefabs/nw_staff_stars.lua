-- Reuse the native factory, including its animation, heater, cooker, sanity
-- aura, haunt response and saved extinguish timer. Only motion is added.
local Copy=require("nw/util").copy
local function owner(inst)
    if inst._killed then return end
    local e=inst._nw_owner
    if not e or not e:IsValid() then
        e=nil
        for _,v in ipairs(AllPlayers) do
            if inst._nw_star.userid and v.userid==inst._nw_star.userid then e=v;break end
        end
        inst._nw_owner=e
    end
    return require("nw/persistent_fields").caster(e)
end
local function start(inst,data,caster)
    if not caster and data.neutral then
        local x,_,z=inst.Transform:GetWorldPosition()
        caster=require("nw/payload_caster").neutral(x,z)
    end
    inst._nw_star=Copy(data);inst._nw_owner=caster;inst._nw_motion_owner=owner
    require("nw/payload_caster").retain(caster,inst)
    require("nw/giant_stars").apply(inst,data.p)
    require("nw/field_motion").start(inst,owner(inst),data.p,data.dx,data.dz,data.age,data.motion)
end
local function make(id,native)
    local function fn()
        local inst=Prefabs[native].fn()
        MakeProjectilePhysics(inst,1,.1);inst._nw_ground_mask=true
        inst._nw_star_size=net_float(inst.GUID,"nw_star.size")
        require("nw/giant_stars").pulse(inst)
        if not TheWorld.ismastersim then return inst end
        local save,load=inst.OnSave,inst.OnLoad
        inst.OnSave=function(self,data)
            local refs=save and save(self,data)
            data.nw_star=Copy(self._nw_star)
            if data.nw_star and self._nw_motion then
                local m=self._nw_motion
                data.nw_star.dx,data.nw_star.dz,data.nw_star.age=m.dx,m.dz,m.age
                data.nw_star.motion=require("nw/field_motion").save(self)
            end
            return refs
        end
        inst.OnLoad=function(self,data,...)
            if load then load(self,data,...) end
            if data and data.nw_star then start(self,data.nw_star) end
        end
        function inst:Launch(caster,p,x,z,dx,dz,cleanup)
            self.Transform:SetPosition(x,0,z)
            start(self,{p=p,dx=dx,dz=dz,userid=require("nw/persistent_fields").userid(caster),neutral=caster and caster._nw_neutral or nil},caster)
            -- A placed native star has its own lifetime; it is not a flying
            -- projectile reservation and must not block a wand for days.
            cleanup()
        end
        inst:ListenForEvent("onstarkilled",function() inst.Physics:Stop() end)
        return inst
    end
    return Prefab("nw_edge_"..id,fn,nil,{native})
end
return make("yellowstaff","stafflight"),make("opalstaff","staffcoldlight")
