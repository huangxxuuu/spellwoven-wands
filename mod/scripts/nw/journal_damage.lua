local M={}
function M.record(owner,p,loss)
    local journal=owner and owner.components and owner.components.nw_spelljournal
    if journal and p then journal:RecordDamage(p.journal_id or p.id,loss) end
end
function M.loss(owner,p,health,before)
    if health and before then M.record(owner,p,math.max(0,before-math.max(0,health.currenthealth))) end
end
function M.tag(inst,owner,p)
    inst._nw_journal_source={owner=owner,id=p.journal_id or p.id}
    require("nw/balance_damage").tag(inst,p)
    require("nw/base_damage_native").tag(inst,p)
    require("nw/native_targeting").tag(inst,owner,p)
end
function M.install(env)
    env.AddComponentPostInit("combat",function(combat)
        if not TheWorld.ismastersim then return end
        local key=combat.GetAttacked_Internal and "GetAttacked_Internal" or "GetAttacked"
        local attacked=combat[key]
        combat[key]=function(self,attacker,damage,weapon,...)
            local source=weapon and weapon._nw_journal_source or attacker and attacker._nw_journal_source
            if not source then return attacked(self,attacker,damage,weapon,...) end
            local health=self.inst.components.health
            local before=health and health.currenthealth
            local result=attacked(self,attacker,damage,weapon,...)
            M.loss(source.owner,source,health,before)
            return result
        end
        require("nw/base_damage_native").wrap_combat(combat)
        require("nw/native_targeting").wrap_combat(combat)
    end)
end
return M
