Camera pitch: 35 degrees; heading: -90 degrees.
Projection matches nw/electric_visual.project; camera tracks captured head XYZ.
OnGround sprite axes use projected ground X/Z; BillBoard axes stay screen XY.
Draw order uses captured actual FinalOffset, then entity id.
Captured sortoffset is recorded, but GPU world/depth sorting is not simulated.
Animation time advances using captured playback rate; quarter clips retain native dimensions.
Compiled element matrices project decoded symbols directly; no intermediate native raster.
Single mip0 texture archives (lower mip levels removed): True.
Compiled animation mip0 only, resampled by Pillow; mathematical preview, not game footage.
No actual GPU depth, mip/LOD selection, lighting, or multiplayer verification.
This preview cannot establish a fix for short-span mip sampling blur.
