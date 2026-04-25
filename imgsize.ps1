param([string]$Path)
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile($Path)
Write-Host ($img.Width.ToString() + "x" + $img.Height.ToString())
$img.Dispose()
