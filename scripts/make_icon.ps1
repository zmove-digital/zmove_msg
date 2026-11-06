Add-Type -AssemblyName System.Drawing

function New-RoundedPath {
    param(
        [float]$X, [float]$Y, [float]$W, [float]$H, [float]$R
    )
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function Draw-Icon {
    param(
        [string]$OutFile,
        [int]$Size,
        [bool]$Transparent,
        [float]$Scale,
        [bool]$RoundedBackground
    )

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    if ($Transparent) {
        $g.Clear([System.Drawing.Color]::Transparent)
    } else {
        $rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
        $c1 = [System.Drawing.Color]::FromArgb(255, 22, 163, 143)
        $c2 = [System.Drawing.Color]::FromArgb(255, 10, 90, 80)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 45.0)
        if ($RoundedBackground) {
            $r = [float]($Size * 0.22)
            $path = New-RoundedPath 0 0 $Size $Size $r
            $g.FillPath($brush, $path)
            $path.Dispose()
        } else {
            $g.FillRectangle($brush, $rect)
        }
        $brush.Dispose()
    }

    # Area util do simbolo
    $span = [float]($Size * $Scale)
    $offset = [float](($Size - $span) / 2)

    $bubbleX = $offset + $span * 0.10
    $bubbleY = $offset + $span * 0.14
    $bubbleW = $span * 0.80
    $bubbleH = $span * 0.62
    $radius = $bubbleH * 0.32

    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $bubble = New-RoundedPath $bubbleX $bubbleY $bubbleW $bubbleH $radius
    $g.FillPath($white, $bubble)

    # Rabinho do balao
    $tail = New-Object System.Drawing.Drawing2D.GraphicsPath
    $tx = $bubbleX + $bubbleW * 0.22
    $ty = $bubbleY + $bubbleH - 4
    $tail.AddPolygon(@(
        (New-Object System.Drawing.PointF($tx, $ty)),
        (New-Object System.Drawing.PointF(($tx + $span * 0.16), $ty)),
        (New-Object System.Drawing.PointF(($tx + $span * 0.01), ($ty + $span * 0.16)))
    ))
    $g.FillPath($white, $tail)

    # Letra Z
    $brand = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 15, 123, 108))
    $fontSize = [float]($span * 0.40)
    $font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $textRect = New-Object System.Drawing.RectangleF($bubbleX, ($bubbleY - $span * 0.01), $bubbleW, $bubbleH)
    $g.DrawString("Z", $font, $brand, $textRect, $format)

    $font.Dispose()
    $brand.Dispose()
    $white.Dispose()
    $bubble.Dispose()
    $tail.Dispose()
    $g.Dispose()

    $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$root = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $root "assets"
if (-not (Test-Path $assets)) { New-Item -ItemType Directory -Path $assets | Out-Null }

Draw-Icon -OutFile (Join-Path $assets "icon.png") -Size 1024 -Transparent $false -Scale 0.62 -RoundedBackground $true
Draw-Icon -OutFile (Join-Path $assets "icon_foreground.png") -Size 1024 -Transparent $true -Scale 0.52 -RoundedBackground $false

Write-Output "Icones gerados em $assets"
