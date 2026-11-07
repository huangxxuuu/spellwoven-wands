-- Match the two real native routes: explicit UI paths and replicated net_hash values.
local oldhash,oldresolve=hash,resolvefilepath
local path="images/inventoryimages/nw_icons.xml"
resolvefilepath=function(p) return "../mods/nw_weave_dev/"..p end
hash=function(p) assert(p==resolvefilepath(path));return 3278123456 end
package.loaded["nw/card_icon"]=nil
local install=require("nw/card_icon").install
local function image(atlas)
    return {atlas=atlas,w=128,h=128,SetTexture=function(self,a,tex) self.atlas=a;self.texture=tex;self.w=128;self.h=128 end,
        SetSize=function(self,w,h) self.w=w;self.h=h end}
end
local native=image(nil);install(native)
-- ItemTile creates Image() first, then SetImageFromItem supplies both network hashes.
native:SetTexture(3278123456,123456789)
assert(native.w==64 and native.h==64)
native:SetTexture(3278123456,987654321)
assert(native.w==64 and native.h==64)
local restored=image(3278123456);install(restored);assert(restored.w==64)
local editor=image(resolvefilepath(path));install(editor);assert(editor.w==64)
editor:SetTexture(path,"nw_spell_fire.tex");editor:SetSize(49,49);assert(editor.w==49)
local other=image(9876);install(other);assert(other.w==128)
other:SetTexture("images/hud.xml","inv_slot.tex");assert(other.w==128)
hash,resolvefilepath=oldhash,oldresolve
package.loaded["nw/card_icon"]=nil
print("card icon: numeric atlas/image hashes, initial creation, image changes and explicit editor sizes passed")
