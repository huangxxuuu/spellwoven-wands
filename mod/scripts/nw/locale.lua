-- Resolve once before loading data/UI modules. No gameplay or save keys are translated.
local M={language="zh"}
local english=require("nw/locales/en")
for zh,en in pairs(require("nw/locales/names")) do english[zh]=en end
local reverse={}
for zh,en in pairs(english) do reverse[en]=zh end
function M.resolve(setting,code)
    if setting=="zh" or setting=="en" then return setting end
    code=tostring(code or "en"):lower():gsub("_","-")
    return (code:match("^zh") or code=="chs" or code=="cht" or code=="chinese" or code=="schinese" or code=="tchinese") and "zh" or "en"
end
function M.configure(setting,code)
    M.language=M.resolve(setting,code)
    return M.language
end
function M.register(zh,en)
    english[zh]=en;reverse[en]=zh
end
function M.translate(text,language)
    if type(text)~="string" then return text end
    local zh=english[text] and text or reverse[text]
    if not zh then return text end
    return (language or M.language)=="en" and english[zh] or zh
end
function M.t(text) return M.translate(text) end
function M.for_player(player,text)
    return M.translate(text,player and player._nw_language or M.language)
end
function M.install(env,G)
    local code=G.require("languages/loc").GetLocaleCode()
    M.configure(env.GetModConfigData("language",true),code)
    -- Send only a validated display preference. It never changes server rules.
    env.AddModRPCHandler("nw_weave","language",function(player,language)
        if language=="zh" or language=="en" then player._nw_language=language end
    end)
    env.AddPlayerPostInit(function(player)
        local function announce()
            if player==G.ThePlayer then
                player._nw_language=M.language
                G.SendModRPCToServer(G.MOD_RPC.nw_weave.language,M.language)
            end
        end
        player:ListenForEvent("playeractivated",announce)
        player:DoTaskInTime(0,announce)
    end)
    env.AddComponentPostInit("inspectable",function(component)
        local original=component.GetDescription
        component.GetDescription=function(self,viewer,...)
            local text,context,author=original(self,viewer,...)
            if self.inst.prefab and self.inst.prefab:match("^nw_") and not author
                and not self.inst:HasTag("nw_customname") then
                text=M.for_player(viewer,text)
            end
            return text,context,author
        end
    end)
end
return M
