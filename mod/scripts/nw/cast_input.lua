local Binding=require("nw/cast_binding")
local Key=require("nw/cast_key")
local Cast=require("nw/cast_action")
local M={}
local focused=true
local pressed,key,owned=false,nil,false

function M.poll(pc)
    if pc.inst==ThePlayer and pressed and key and not Key.down(key) then pressed,owned=false,false end
end

function M.world_input(pc)
    local p=pc.inst
    return focused and pc.handler and p==ThePlayer and p.HUD and TheFrontEnd:GetActiveScreen()==p.HUD
        and pc:UsingMouse() and pc:IsEnabled() and not IsPaused() and p:IsActionsVisible()
        and not p._nw_editing and not p._nw_hud_dragging and not p._nw_binding_capture and not p:HasTag("playerghost")
        and not pc.placer_recipe and not pc.deployplacer and not pc:IsAOETargeting()
        and not p.replica.inventory:GetActiveItem() and not TheInput:GetHUDEntityUnderMouse()
end
local function controller()
    return ThePlayer and ThePlayer.components and ThePlayer.components.playercontroller
end
local function intercept(pc)
    return pc and Binding.ready() and M.world_input(pc) and Cast.hand(pc.inst)~=nil
end
function M.install(env,G)
    if G.TheNet:IsDedicated() then return end
    local input=G.TheInput
    local swallowed={}
    local function reset()
        local pc=controller()
        if pc and pc._nw_cast_key_cancel then pc:_nw_cast_key_cancel() end
        key=Binding.get()
        pressed=key and Key.down(key) or false
        owned=false
    end
    Binding.subscribe(reset)
    local function event(value,down)
        if not value then return end
        if key~=Binding.get() then reset() end
        if value~=key then return end
        local pc=controller()
        if not down then
            pressed,owned=false,false
            if pc and pc._nw_cast_key_event then pc:_nw_cast_key_event(false) end
        elseif not pressed then
            -- Even presses in chat/menus disarm until release; a key repeat must
            -- never start casting after the UI is closed with that key held.
            pressed=true
            owned=intercept(pc) and pc._nw_cast_key_event~=nil or false
            if owned then pc:_nw_cast_key_event(true) end
        end
    end
    input:AddMouseButtonHandler(function(button,down) event(Key.mouse(button),down) end)
    input:AddKeyHandler(function(code,down) event(Key.keyboard(code),down) end)

    local control=input.OnControl
    input.OnControl=function(self,id,down,...)
        if not down and swallowed[id] then swallowed[id]=nil;return end
        -- Raw dispatch can start a jump or open a screen before its matching
        -- control arrives. Keep ownership of that press even if context changed.
        if down and ((pressed and owned) or intercept(controller())) and Key.matches_control(Binding.get(),id) then
            swallowed[id]=true
            return
        end
        if down then swallowed[id]=nil end
        return control(self,id,down,...)
    end
    -- Native cameras and held controls also poll digital state, independently
    -- of OnControl. Suppress only controls mapped to this player's cast key,
    -- while the wand owns world input. Never remap the user's game settings.
    local control_pressed=input.IsControlPressed
    input.IsControlPressed=function(self,id,...)
        if intercept(controller()) and Key.matches_control(Binding.get(),id) then return false end
        return control_pressed(self,id,...)
    end
    local lost,gained=G.OnFocusLost,G.OnFocusGained
    G.OnFocusLost=function(...)
        focused=false
        local p=G.ThePlayer
        if p and p._nw_binding_capture and p._nw_binding_capture.cancel then p._nw_binding_capture:cancel() end
        reset()
        if lost then return lost(...) end
    end
    G.OnFocusGained=function(...)
        focused=true
        reset()
        if gained then return gained(...) end
    end
    env.AddPlayerPostInit(function(player)
        player:ListenForEvent("playeractivated",function() if player==G.ThePlayer then reset() end end)
        player:ListenForEvent("playerdeactivated",function()
            if player==G.ThePlayer then
                local pc=controller()
                if pc and pc._nw_cast_key_cancel then pc:_nw_cast_key_cancel() end
                pressed,key,owned=false,nil,false
            end
        end)
    end)
end
return M
