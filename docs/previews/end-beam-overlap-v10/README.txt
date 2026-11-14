Camera pitch: 35 degrees; heading: -90 degrees.
Projection matches nw/electric_visual.project; camera tracks captured head XYZ.
OnGround sprite axes use projected ground X/Z; BillBoard axes stay screen XY.
Draw order uses captured actual FinalOffset, then entity id.
Captured sortoffset is recorded, but GPU world/depth sorting is not simulated.
Animation time advances using captured playback rate; 16 micro clips/span retain native dimensions.
Captured quad transforms include overlap; terminal beam/connector outer endpoints are asserted.
Gentle-curve scenario changes heading smoothly, peaking at 9.9 degrees per logical span.
Compiled element matrices project atlas UV quads at exact floating-point BILD boundaries.
No intermediate integer raster: a 21px micro source stays 21px / 18.75 native units, not 22px.
Single mip0 texture archives (lower mip levels removed): True.
Compiled animation mip0 only, resampled by Pillow; mathematical preview, not game footage.
No actual GPU depth, mip/LOD selection, lighting, or multiplayer verification.
This preview cannot establish a fix for short-span mip sampling blur.
