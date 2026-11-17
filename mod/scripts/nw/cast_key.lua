local M={default="mouse:1001"}
local function integer(value) return type(value)=="number" and value==math.floor(value) end
function M.mouse(button)
    -- DST's keyboard/mouse input table includes buttons 4/5 (1005/1006).
    -- Wheel events have no useful held state; the primary button stays movement.
    if integer(button) and (button==1001 or button==1002 or (button>=1005 and button<=1031)) then
        return "mouse:"..button
    end
end
function M.keyboard(key)
    if not integer(key) then return end
    -- Escape cancels capture. Exclude system/modifier keys and console input.
    if (key>=32 and key<=126 and key~=96) or (key>=256 and key<=293) or key==8 or key==9 or key==127 then
        return "key:"..key
    end
end
function M.decode(value)
    if type(value)~="string" then return end
    local kind,number=value:match("^(%a+):(%d+)$")
    local code=tonumber(number)
    local canonical=kind=="mouse" and M.mouse(code) or (kind=="key" and M.keyboard(code))
    if canonical==value then return kind,code end
end
function M.valid(value) return M.decode(value)~=nil end
function M.down(value)
    local kind,code=M.decode(value)
    if kind=="mouse" then return TheInput:IsMouseDown(code) end
    return kind=="key" and TheInput:IsKeyDown(code) or false
end
function M.matches_control(value,control)
    local _,code=M.decode(value)
    if not code or not TheInputProxy or not integer(control) or control<0 or control>=math.huge then return false end
    -- HUD polling includes virtual inventory/camera controls. Resolve them just
    -- like Input:IsControlPressed before calling the native mapping API: that
    -- API asserts (rather than raising a Lua error) on out-of-range controls.
    control=TheInput:ResolveVirtualControls(control)
    if not integer(control) or control<0 or control>=CONTROL_CUSTOM_START then return false end
    local device,count,a,b,c,d=TheInputProxy:GetLocalizedControl(0,control,false,true)
    if device~=1 or not count or count<1 then return false end
    return a==code or (count>=2 and b==code) or (count>=3 and c==code) or (count>=4 and d==code)
end
function M.label(value)
    local en=require("nw/locale").language=="en"
    local kind,code=M.decode(value)
    if not kind then return en and "Follow host" or "跟随房主" end
    if kind=="mouse" then
        if code==1001 then return en and "Right mouse button" or "鼠标右键" end
        if code==1002 then return en and "Middle mouse button" or "鼠标中键" end
        return (en and "Mouse button " or "鼠标键 ")..(code-1001)
    end
    if code>=97 and code<=122 then return string.char(code):upper() end
    local readable={
        [8]={"退格","Backspace"},[9]={"Tab","Tab"},[32]={"空格","Space"},
        [127]={"删除","Delete"},
    }
    if readable[code] then return readable[code][en and 2 or 1] end
    if code>=282 and code<=293 then return "F"..(code-281) end
    local names=STRINGS and STRINGS.UI and STRINGS.UI.CONTROLSSCREEN and STRINGS.UI.CONTROLSSCREEN.INPUTS
    local native=names and names[1] and names[1][code]
    return (type(native)=="string" and native~="" and native)
        or (code>=32 and code<=126 and string.char(code):upper())
        or ((en and "Key " or "键 ")..code)
end
function M.hint(value)
    local _,code=M.decode(value)
    if not code then return end
    -- Use the same keyboard/mouse glyph strings as native action prompts.
    -- UIFONT already falls back to DST's controller-symbol font.
    local names=STRINGS and STRINGS.UI and STRINGS.UI.CONTROLSSCREEN and STRINGS.UI.CONTROLSSCREEN.INPUTS
    local native=names and names[1] and names[1][code]
    return type(native)=="string" and native~="" and native or M.label(value)
end
return M
