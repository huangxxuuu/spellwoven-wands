$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$artRoot = $PSScriptRoot
$groups = @('A_once', 'B_round_1', 'B_round_2', 'B_round_3')
$assets = @('workbench', 'engraver', 'furnace')
$names = @('奥术台', '武器刻印台', '奥术分解炉')
$font = [System.Drawing.Font]::new('Microsoft YaHei', 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(40, 38, 36))
$format = [System.Drawing.StringFormat]::new()
$format.Alignment = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center
try {
    foreach ($group in $groups) {
        $canvas = [System.Drawing.Bitmap]::new(1800, 660)
        $graphics = [System.Drawing.Graphics]::FromImage($canvas)
        try {
            $graphics.Clear([System.Drawing.Color]::FromArgb(234, 232, 228))
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
            for ($i = 0; $i -lt 3; $i++) {
                $imagePath = Join-Path $artRoot ($group + '/' + $assets[$i] + '.png')
                $asset = [System.Drawing.Image]::FromFile($imagePath)
                try {
                    $scale = [Math]::Min(560.0 / $asset.Width, 580.0 / $asset.Height)
                    $width = [single]($asset.Width * $scale)
                    $height = [single]($asset.Height * $scale)
                    $x = [single]($i * 600 + (600 - $width) / 2)
                    $y = [single](24 + (580 - $height) / 2)
                    $rect = [System.Drawing.RectangleF]::new($x, $y, $width, $height)
                    $graphics.DrawImage($asset, $rect)
                } finally {
                    $asset.Dispose()
                }
                $label = [System.Drawing.RectangleF]::new([single]($i * 600), 612, 600, 36)
                $graphics.DrawString($names[$i], $font, $brush, $label, $format)
            }
            $canvas.Save((Join-Path $artRoot ('display/' + $group + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $graphics.Dispose()
            $canvas.Dispose()
        }
    }
} finally {
    $format.Dispose()
    $brush.Dispose()
    $font.Dispose()
}
Write-Output 'Saved four display sheets; originals preserved.'

