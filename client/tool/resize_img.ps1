param(
    [string]$Src,
    [string]$Dst,
    [int]$Width = 540
)
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile($Src)
$newW = $Width
$newH = [int]($img.Height * ($newW / $img.Width))
$bmp = New-Object System.Drawing.Bitmap $newW, $newH
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($img, 0, 0, $newW, $newH)
$bmp.Save($Dst, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose()
$bmp.Dispose()
$img.Dispose()
