param([string]$ArtRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
public static class WaveAlphaAudit {
    public static object Scan(byte[] pixels, int width, int height, int stride) {
        long clear=0, partial=0, solid=0, border=0;
        int minX=width, minY=height, maxX=-1, maxY=-1;
        for (int y=0;y<height;y++) for (int x=0;x<width;x++) {
            byte a=pixels[y*stride+x*4+3];
            if(a==0)clear++; else if(a==255)solid++; else partial++;
            if(a>=16) {
                minX=Math.Min(minX,x); minY=Math.Min(minY,y);
                maxX=Math.Max(maxX,x); maxY=Math.Max(maxY,y);
                if(x==0||y==0||x==width-1||y==height-1)border++;
            }
        }
        return new {width=width,height=height,transparent_pixels=clear,partial_pixels=partial,opaque_pixels=solid,visible_border_pixels=border,bounds_alpha_16=new int[]{minX,minY,maxX+1,maxY+1}};
    }
}
'@
$previewDir = Join-Path $ArtRoot 'previews'
New-Item -ItemType Directory -Force -Path $previewDir | Out-Null
$images = @(Get-ChildItem -LiteralPath (Join-Path $ArtRoot 'originals') -Recurse -Filter '*.png' | Sort-Object FullName)
if ($images.Count -ne 6) { throw "Expected exactly 6 source images, got $($images.Count)." }
$font = [System.Drawing.Font]::new('Microsoft YaHei',18)
$smallFont = [System.Drawing.Font]::new('Microsoft YaHei',12)
$ink = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#22252a'))
function New-Canvas([int]$width,[int]$height,[string]$color) {
    $bmp = [System.Drawing.Bitmap]::new($width,$height)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.Clear([System.Drawing.ColorTranslator]::FromHtml($color))
    $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    return @{bitmap=$bmp; gfx=$gfx}
}
function Save-Canvas($canvas,[string]$path) {
    $canvas.bitmap.Save($path,[System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.gfx.Dispose()
    $canvas.bitmap.Dispose()
}
$board = New-Canvas 1568 1732 '#e3e2dd'
$board.gfx.DrawString('奥术分解炉 · 扩散特效 · 6 个纯 Prompt 候选',$font,$ink,24,16)
$board.gfx.DrawString('每张按左上 → 右上 → 左下 → 右下阅读：聚拢 / 展开 / 极限范围 / 碎散',$smallFont,$ink,24,50)
$audit = @()
for($i=0;$i -lt $images.Count;$i++) {
    $src = [System.Drawing.Bitmap]::new($images[$i].FullName)
    $number = '{0:D2}' -f ($i+1)
    $data = $src.LockBits([System.Drawing.Rectangle]::new(0,0,$src.Width,$src.Height),[System.Drawing.Imaging.ImageLockMode]::ReadOnly,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $pixels = [byte[]]::new($data.Stride*$src.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0,$pixels,0,$pixels.Length)
    $stats = [WaveAlphaAudit]::Scan($pixels,$src.Width,$src.Height,$data.Stride)
    $src.UnlockBits($data)
    $audit += @{candidate=$number; source=$images[$i].FullName; sha256=(Get-FileHash -LiteralPath $images[$i].FullName -Algorithm SHA256).Hash; alpha=$stats}
    $col = $i % 2
    $row = [Math]::Floor($i / 2)
    $x = [int](16+$col*776)
    $y = [int](88+$row*544)
    $board.gfx.DrawString(('方案 '+$number),$font,$ink,$x+12,$y)
    $board.gfx.DrawImage($src,[System.Drawing.Rectangle]::new($x,$y+32,768,512))
    $pair = New-Canvas 1536 1088 '#ffffff'
    $pair.gfx.FillRectangle([System.Drawing.Brushes]::DimGray,768,0,768,1088)
    $pair.gfx.DrawString(('方案 '+$number+' / 白底'),$font,$ink,24,16)
    $pair.gfx.DrawString(('方案 '+$number+' / 灰底'),$font,[System.Drawing.Brushes]::White,792,16)
    $pair.gfx.DrawImage($src,[System.Drawing.Rectangle]::new(0,64,768,512))
    $pair.gfx.DrawImage($src,[System.Drawing.Rectangle]::new(768,64,768,512))
    $pair.gfx.DrawString('缩略检查（原始构图，未重绘）',$smallFont,$ink,24,624)
    $pair.gfx.DrawImage($src,[System.Drawing.Rectangle]::new(144,688,480,320))
    $pair.gfx.DrawImage($src,[System.Drawing.Rectangle]::new(912,688,480,320))
    Save-Canvas $pair (Join-Path $previewDir ('candidate_'+$number+'_alpha.png'))
    $src.Dispose()
}
Save-Canvas $board (Join-Path $previewDir 'comparison_6.png')
$audit | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ArtRoot 'alpha_audit.json') -Encoding utf8
$font.Dispose()
$smallFont.Dispose()
$ink.Dispose()
Write-Output (Join-Path $previewDir 'comparison_6.png')
