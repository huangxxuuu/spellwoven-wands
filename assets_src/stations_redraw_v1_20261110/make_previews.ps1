param([string]$ArtRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
public static class StationAlphaAudit {
    public static object Scan(byte[] pixels, int width, int height, int stride) {
        int minX=width, minY=height, maxX=-1, maxY=-1;
        long clear=0, partial=0, solid=0, border=0;
        for (int y=0;y<height;y++) for(int x=0;x<width;x++) {
            byte a=pixels[y*stride+x*4+3];
            if(a==0)clear++; else if(a==255)solid++; else partial++;
            if(a>=9) {
                minX=Math.Min(minX,x); minY=Math.Min(minY,y);
                maxX=Math.Max(maxX,x); maxY=Math.Max(maxY,y);
                if(x==0||y==0||x==width-1||y==height-1)border++;
            }
        }
        return new {width=width,height=height,alpha_bounds_threshold_9=new int[]{minX,minY,maxX+1,maxY+1},transparent_pixels=clear,partially_transparent_pixels=partial,opaque_pixels=solid,visible_border_pixels=border};
    }
}
'@

$previewDir = Join-Path $ArtRoot 'previews'
New-Item -ItemType Directory -Force -Path $previewDir | Out-Null
$items = @(
    @{ key='workbench'; name='奥术台'; width=256; height=256; scale=1.48 },
    @{ key='engraver'; name='武器刻印台'; width=301; height=320; scale=1.0 },
    @{ key='furnace'; name='奥术分解炉'; width=300; height=320; scale=1.0 }
)
$font = [System.Drawing.Font]::new('Microsoft YaHei',17)
$smallFont = [System.Drawing.Font]::new('Microsoft YaHei',12)
$white = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#eeeae2'))
$muted = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#b7bbc0'))
function New-Canvas([int]$width,[int]$height,[string]$color) {
    $bitmap = [System.Drawing.Bitmap]::new($width,$height)
    $gfx = [System.Drawing.Graphics]::FromImage($bitmap)
    $gfx.Clear([System.Drawing.ColorTranslator]::FromHtml($color))
    $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $gfx.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    return @{ bitmap=$bitmap; gfx=$gfx }
}
function Paint-Image($gfx,[string]$path,[int]$cx,[int]$bottom,[int]$width,[int]$height) {
    $src = [System.Drawing.Bitmap]::new($path)
    $factor = [Math]::Min($width / $src.Width,$height / $src.Height)
    $w = [int][Math]::Round($src.Width*$factor)
    $h = [int][Math]::Round($src.Height*$factor)
    $gfx.DrawImage($src,[System.Drawing.Rectangle]::new($cx-[int]($w/2),$bottom-$h,$w,$h))
    $src.Dispose()
}
function Save-Canvas($canvas,[string]$path) {
    $canvas.bitmap.Save($path,[System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.gfx.Dispose()
    $canvas.bitmap.Dispose()
}

$audit = @()
$compare = New-Canvas 1260 930 '#55595b'
$compare.gfx.DrawString('旧版 / 当前建筑源图',$font,$white,24,16)
$compare.gfx.DrawString('重绘 / 保留结构，调整线条与材质',$font,$white,24,474)
for($i=0;$i -lt $items.Count;$i++) {
    $entry=$items[$i]
    $path=Join-Path $ArtRoot ($entry.key+'/source.png')
    $bmp=[System.Drawing.Bitmap]::new($path)
    $data=$bmp.LockBits([System.Drawing.Rectangle]::new(0,0,$bmp.Width,$bmp.Height),[System.Drawing.Imaging.ImageLockMode]::ReadOnly,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $pixels=[byte[]]::new($data.Stride*$bmp.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0,$pixels,0,$pixels.Length)
    $stats=[StationAlphaAudit]::Scan($pixels,$bmp.Width,$bmp.Height,$data.Stride)
    $bmp.UnlockBits($data)
    $bmp.Dispose()
    $audit += @{ asset=$entry.key; source=$stats; target_body_pixels=@($entry.width,$entry.height); prefab_scale=$entry.scale }
    $cx=210+$i*420
    $w=[int][Math]::Round($entry.width*$entry.scale)
    $h=[int][Math]::Round($entry.height*$entry.scale)
    Paint-Image $compare.gfx (Join-Path $ArtRoot ('references/'+$entry.key+'_current.png')) $cx 431 $w $h
    Paint-Image $compare.gfx $path $cx 885 $w $h
    $compare.gfx.DrawString($entry.name,$smallFont,$white,$cx-65,438)
    $compare.gfx.DrawString($entry.name,$smallFont,$white,$cx-65,894)
    $thumb=New-Canvas $entry.width $entry.height '#000000'
    $thumb.gfx.Clear([System.Drawing.Color]::Transparent)
    Paint-Image $thumb.gfx $path ([int]($entry.width/2)) $entry.height $entry.width $entry.height
    Save-Canvas $thumb (Join-Path $previewDir ($entry.key+'_body_scale.png'))
}
Save-Canvas $compare (Join-Path $previewDir 'before_after.png')

$native=New-Canvas 1600 660 '#777777'
$native.gfx.DrawString('重绘建筑与原版炼金引擎 / 静态贴图尺度对照（无游戏光照）',$font,$white,24,16)
for($i=0;$i -lt $items.Count;$i++) {
    $entry=$items[$i]
    $w=[int][Math]::Round($entry.width*$entry.scale*.88)
    $h=[int][Math]::Round($entry.height*$entry.scale*.88)
    Paint-Image $native.gfx (Join-Path $ArtRoot ($entry.key+'/source.png')) (200+$i*400) 575 $w $h
    $native.gfx.DrawString($entry.name,$smallFont,$white,(140+$i*400),592)
}
$projectRoot=Split-Path (Split-Path $ArtRoot -Parent) -Parent
Paint-Image $native.gfx (Join-Path $projectRoot 'test_reports/native_style_reference/alchemy_engine.png') 1400 575 372 454
$native.gfx.DrawString('原版炼金引擎',$smallFont,$white,1330,592)
$native.gfx.DrawString('原版自带地影；新母图本体不烘焙地影。显示均按当前动画尺寸 × prefab 缩放 × 0.88。',$smallFont,$muted,24,627)
Save-Canvas $native (Join-Path $previewDir 'native_scale_comparison.png')

$edges=New-Canvas 1200 820 '#e5e3de'
$edges.gfx.FillRectangle([System.Drawing.Brushes]::DarkSlateGray,0,410,1200,410)
for($i=0;$i -lt $items.Count;$i++) {
    $entry=$items[$i]
    $path=Join-Path $ArtRoot ($entry.key+'/source.png')
    Paint-Image $edges.gfx $path (200+$i*400) 375 350 340
    Paint-Image $edges.gfx $path (200+$i*400) 785 350 340
}
Save-Canvas $edges (Join-Path $previewDir 'alpha_light_dark.png')
$audit | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $ArtRoot 'alpha_audit.json')
$font.Dispose(); $smallFont.Dispose(); $white.Dispose(); $muted.Dispose()
$audit | ConvertTo-Json -Depth 8
