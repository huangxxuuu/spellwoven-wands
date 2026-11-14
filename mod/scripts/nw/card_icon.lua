local C=require("nw/constants/ui").card_icon
local M={}
local ATLAS="images/inventoryimages/nw_icons.xml"
local atlas_hash
local function matches(atlas)
    if type(atlas)=="string" then
        return atlas:gsub("\\","/"):match("images/inventoryimages/nw_icons%.xml$")~=nil
    end
    if type(atlas)=="number" then
        if atlas_hash==nil then atlas_hash=hash(resolvefilepath(ATLAS)) end
        return atlas==atlas_hash
    end
    return false
end
local function normalize(image)
    if matches(image.atlas) then
        image:SetSize(C.size,C.size)
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
