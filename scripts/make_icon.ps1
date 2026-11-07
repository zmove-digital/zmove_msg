# Gera os assets de marca do ZMove Msg a partir das artes originais:
#   - D:\dev\projects\WALDEZ\ZMOVE_MSG_FILES\zmove_z_aviao_512x512.png (icone)
#   - D:\dev\projects\WALDEZ\ZMOVE_MSG_FILES\ZMOVE.png              (logo de abertura)
#
# Saidas:
#   assets/icon.png             icone legado (fundo escuro + logo)
#   assets/icon_background.png  fundo do icone adaptativo
#   assets/icon_foreground.png  frente do icone adaptativo (transparente)
#   assets/splash_logo.png      logo usado na abertura em Flutter
#   android/app/src/main/res/drawable-nodpi/splash_logo.png
#
# Depois rode: dart run flutter_launcher_icons

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$sourceDir = "D:\dev\projects\WALDEZ\ZMOVE_MSG_FILES"
$iconSource = Join-Path $sourceDir "zmove_z_aviao_512x512.png"
$splashSource = Join-Path $sourceDir "ZMOVE.png"

$assets = Join-Path $root "assets"
$resNodpi = Join-Path $root "android\app\src\main\res\drawable-nodpi"
New-Item -ItemType Directory -Force -Path $assets | Out-Null
New-Item -ItemType Directory -Force -Path $resNodpi | Out-Null

function Get-OpaqueBounds {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [int]$Threshold = 16
    )

    $width = $Bitmap.Width
    $height = $Bitmap.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $data = $Bitmap.LockBits(
        $rect,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $stride = $data.Stride
    $bytes = New-Object byte[] ($stride * $height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $Bitmap.UnlockBits($data)

    $minX = $width
    $minY = $height
    $maxX = -1
    $maxY = -1

    for ($y = 0; $y -lt $height; $y++) {
        $row = $y * $stride
        for ($x = 0; $x -lt $width; $x++) {
            if ($bytes[$row + $x * 4 + 3] -gt $Threshold) {
                if ($x -lt $minX) { $minX = $x }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }

    if ($maxX -lt 0) {
        return [System.Drawing.Rectangle]::FromLTRB(0, 0, $width, $height)
    }
    return [System.Drawing.Rectangle]::FromLTRB($minX, $minY, $maxX + 1, $maxY + 1)
}

function New-GradientBrush {
    param([System.Drawing.RectangleF]$Rect)

    $from = [System.Drawing.Color]::FromArgb(255, 18, 74, 62)
    $to = [System.Drawing.Color]::FromArgb(255, 4, 17, 13)
    return New-Object System.Drawing.Drawing2D.LinearGradientBrush($Rect, $from, $to, 45.0)
}

function New-RoundedPath {
    param([float]$X, [float]$Y, [float]$W, [float]$H, [float]$R)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function Set-HighQuality {
    param([System.Drawing.Graphics]$Graphics)

    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $Graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
}

function Draw-TrimmedLogo {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Bitmap]$Bitmap,
        [System.Drawing.Rectangle]$Bounds,
        [float]$TargetWidth,
        [float]$CenterX,
        [float]$CenterY
    )

    $scale = $TargetWidth / $Bounds.Width
    $width = $Bounds.Width * $scale
    $height = $Bounds.Height * $scale
    $dest = New-Object System.Drawing.RectangleF(
        ($CenterX - $width / 2),
        ($CenterY - $height / 2),
        $width,
        $height
    )
    $source = New-Object System.Drawing.RectangleF(
        $Bounds.X,
        $Bounds.Y,
        $Bounds.Width,
        $Bounds.Height
    )
    $Graphics.DrawImage(
        $Bitmap,
        $dest,
        $source,
        [System.Drawing.GraphicsUnit]::Pixel
    )
}

function Save-RoundedIcon {
    param(
        [System.Drawing.Bitmap]$Logo,
        [System.Drawing.Rectangle]$Bounds,
        [string]$OutFile,
        [int]$Size = 1024,
        [float]$LogoWidthRatio = 0.74
    )

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    Set-HighQuality $g
    $g.Clear([System.Drawing.Color]::Transparent)

    $radius = [float]($Size * 0.22)
    $path = New-RoundedPath 0 0 $Size $Size $radius
    $rect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
    $brush = New-GradientBrush $rect
    $g.FillPath($brush, $path)

    Draw-TrimmedLogo -Graphics $g -Bitmap $Logo -Bounds $Bounds `
        -TargetWidth ($Size * $LogoWidthRatio) `
        -CenterX ($Size / 2) -CenterY ($Size / 2)

    $brush.Dispose()
    $path.Dispose()
    $g.Dispose()
    $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

function Save-SplashLogo {
    param(
        [System.Drawing.Bitmap]$Logo,
        [System.Drawing.Rectangle]$Bounds,
        [string]$OutFile,
        [int]$CanvasSize,
        [float]$LogoWidthRatio
    )

    $bmp = New-Object System.Drawing.Bitmap($CanvasSize, $CanvasSize)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    Set-HighQuality $g
    $g.Clear([System.Drawing.Color]::Transparent)
    Draw-TrimmedLogo -Graphics $g -Bitmap $Logo -Bounds $Bounds `
        -TargetWidth ($CanvasSize * $LogoWidthRatio) `
        -CenterX ($CanvasSize / 2) -CenterY ($CanvasSize / 2)
    $g.Dispose()
    $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$iconImage = [System.Drawing.Image]::FromFile($iconSource)
$iconBitmap = New-Object System.Drawing.Bitmap($iconImage)
$iconBounds = Get-OpaqueBounds -Bitmap $iconBitmap -Threshold 12
Write-Output "Icone: $($iconImage.Width)x$($iconImage.Height), conteudo $($iconBounds.Width)x$($iconBounds.Height)"

# Icone legado: fundo escuro arredondado + logo neon.
Save-RoundedIcon -Logo $iconBitmap -Bounds $iconBounds `
    -OutFile (Join-Path $assets "icon.png") -Size 1024 -LogoWidthRatio 0.74

# Fundo adaptativo: gradiente cheio (o sistema aplica a mascara).
$background = New-Object System.Drawing.Bitmap(1024, 1024)
$bg = [System.Drawing.Graphics]::FromImage($background)
Set-HighQuality $bg
$bgRect = New-Object System.Drawing.RectangleF(0, 0, 1024, 1024)
$bgBrush = New-GradientBrush $bgRect
$bg.FillRectangle($bgBrush, $bgRect)
$bgBrush.Dispose()
$bg.Dispose()
$background.Save((Join-Path $assets "icon_background.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$background.Dispose()

# Frente adaptativa: logo dentro da area segura (66% do canvas).
$foreground = New-Object System.Drawing.Bitmap(1024, 1024)
$fg = [System.Drawing.Graphics]::FromImage($foreground)
Set-HighQuality $fg
$fg.Clear([System.Drawing.Color]::Transparent)
Draw-TrimmedLogo -Graphics $fg -Bitmap $iconBitmap -Bounds $iconBounds `
    -TargetWidth (1024 * 0.58) -CenterX 512 -CenterY 512
$fg.Dispose()
$foreground.Save((Join-Path $assets "icon_foreground.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$foreground.Dispose()

# Logo de abertura: asset do Flutter + bitmap nativo (Android).
$splashImage = [System.Drawing.Image]::FromFile($splashSource)
$splashBitmap = New-Object System.Drawing.Bitmap($splashImage)
$splashBounds = Get-OpaqueBounds -Bitmap $splashBitmap -Threshold 12
Write-Output "Abertura: $($splashImage.Width)x$($splashImage.Height), conteudo $($splashBounds.Width)x$($splashBounds.Height)"

Save-SplashLogo -Logo $splashBitmap -Bounds $splashBounds `
    -OutFile (Join-Path $assets "splash_logo.png") -CanvasSize 1024 -LogoWidthRatio 0.88
Save-SplashLogo -Logo $splashBitmap -Bounds $splashBounds `
    -OutFile (Join-Path $resNodpi "splash_logo.png") -CanvasSize 720 -LogoWidthRatio 0.92

$iconBitmap.Dispose()
$iconImage.Dispose()
$splashBitmap.Dispose()
$splashImage.Dispose()

Write-Output "Assets gerados em $assets"
