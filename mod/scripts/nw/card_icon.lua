-- Texture pixels and UI dimensions are separate: inventory/drag/recipe images stay 64 units.
local M={}
local ATLAS="images/inventoryimages/nw_icons.xml"
local atlas_hash
local function matches(atlas)
    if type(atlas)=="string" then
        return atlas:gsub("\\","/"):match("images/inventoryimages/nw_icons%.xml$")~=nil
    end
    -- inventoryitem_classified uses net_hash, so GetAtlas() normally returns a number.
    if type(atlas)=="number" then
        if atlas_hash==nil then atlas_hash=hash(resolvefilepath(ATLAS)) end
        return atlas==atlas_hash
    end
    return false
end
local function normalize(image)
    if matches(image.atlas) then
        image:SetSize(64,64)
    end
end
function M.install(image)
    local old=image.SetTexture
    image.SetTexture=function(self,...)
        old(self,...)
        normalize(self)
    end
    normalize(image)
end
return M
