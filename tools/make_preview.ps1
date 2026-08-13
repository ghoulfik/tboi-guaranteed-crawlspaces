# Regenerates workshop/preview.png - the Steam Workshop thumbnail.
#
# 640x640, well under Steam's 1 MB limit. This mod ships no art of its own, so
# the image is drawn from primitives in a flat, chunky style with hard outlines,
# which survives being shrunk to a Workshop tile far better than fine detail.
#
# The subject is the mod in one picture: a rock, and the crawlspace under it.
# The violet corner brackets are a deliberate nod to Secrets Reveal, which marks
# exactly this rock.
#
# Run:  powershell -ExecutionPolicy Bypass -File tools\make_preview.ps1

Add-Type -AssemblyName System.Drawing

$root   = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$outDir = Join-Path $root 'workshop'
$out    = Join-Path $outDir 'preview.png'

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$S = 640
$bmp = New-Object System.Drawing.Bitmap $S, $S, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

function RGB([int]$r, [int]$g_, [int]$b, [int]$a = 255) {
  [System.Drawing.Color]::FromArgb($a, $r, $g_, $b)
}
function Brush($c)          { New-Object System.Drawing.SolidBrush $c }
function Pen($c, [single]$w) { New-Object System.Drawing.Pen $c, $w }

# ---------------------------------------------------------------- background
$bgRect = New-Object System.Drawing.Rectangle 0, 0, $S, $S
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  $bgRect, (RGB 38 28 22), (RGB 12 9 8), 90.0)
$g.FillRectangle($bg, $bgRect)

# Isaac's floor is a 40-unit grid; hinting at it grounds the scene.
$gridPen = Pen (RGB 255 245 230 12) 1
for ($x = 40; $x -lt $S; $x += 40) { $g.DrawLine($gridPen, $x, 0, $x, $S) }
for ($y = 40; $y -lt $S; $y += 40) { $g.DrawLine($gridPen, 0, $y, $S, $y) }

# Vignette, so the eye lands on the middle.
$vig = New-Object System.Drawing.Drawing2D.GraphicsPath
$vig.AddEllipse(-120, -120, $S + 240, $S + 240)
$vigBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush $vig
$vigBrush.CenterColor    = RGB 0 0 0 0
$vigBrush.SurroundColors = @((RGB 0 0 0 190))
$g.FillRectangle($vigBrush, $bgRect)

# Vertical layout is fixed up front so nothing collides: the title plate ends at
# 178, the art lives between 186 and 538, and the strap starts at 546.
$cx = 320

# ---------------------------------------------------------------------- hole
$holeY = 462

# Rim: the lip of dug-out earth around the opening.
$g.FillEllipse((Brush (RGB 58 42 31)), ($cx - 168), ($holeY - 76), 336, 152)
$g.FillEllipse((Brush (RGB 44 31 23)), ($cx - 152), ($holeY - 67), 304, 134)
# The opening itself.
$g.FillEllipse((Brush (RGB 9 7 12)),  ($cx - 128), ($holeY - 56), 256, 112)

# Ladder going down into it.
$railPen = Pen (RGB 150 98 48) 12
$railPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$railPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($railPen, ($cx - 40), ($holeY - 34), ($cx - 54), ($holeY + 56))
$g.DrawLine($railPen, ($cx + 40), ($holeY - 34), ($cx + 54), ($holeY + 56))

$rungY = $holeY - 22
$step  = 26
for ($i = 0; $i -lt 4; $i++) {
  $t = $i * $step
  # Rungs fade as they descend, which reads as depth without any gradient work.
  $a = [int](235 - $i * 46)
  $rungPen = Pen (RGB 176 118 60 $a) 10
  $rungPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $rungPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
  $spread = 42 + $i * 4
  $g.DrawLine($rungPen, ($cx - $spread), ($rungY + $t), ($cx + $spread), ($rungY + $t))
}

# ---------------------------------------------------------------------- rock
# Directly above the hole: break this, get that.
$rx = 320
$ry = 286

# Contact shadow, so the rock sits in the scene instead of hovering over it.
$g.FillEllipse((Brush (RGB 0 0 0 120)), ($rx - 98), ($ry + 40), 196, 44)
$g.FillEllipse((Brush (RGB 0 0 0 90)),  ($rx - 78), ($ry + 48), 156, 34)

$rock = New-Object System.Drawing.Drawing2D.GraphicsPath
$pts = @(
  (New-Object System.Drawing.Point (($rx - 96), ($ry + 62))),
  (New-Object System.Drawing.Point (($rx - 104), ($ry + 8))),
  (New-Object System.Drawing.Point (($rx - 62), ($ry - 44))),
  (New-Object System.Drawing.Point (($rx + 4),  ($ry - 66))),
  (New-Object System.Drawing.Point (($rx + 68), ($ry - 40))),
  (New-Object System.Drawing.Point (($rx + 102), ($ry + 12))),
  (New-Object System.Drawing.Point (($rx + 92), ($ry + 62)))
)
$rock.AddPolygon($pts)
$rock.CloseFigure()

$g.FillPath((Brush (RGB 124 113 102)), $rock)

# One darker facet and one lighter one: enough shape without shading gradients.
$facet = New-Object System.Drawing.Drawing2D.GraphicsPath
$facet.AddPolygon(@(
  (New-Object System.Drawing.Point (($rx + 4),  ($ry - 66))),
  (New-Object System.Drawing.Point (($rx + 68), ($ry - 40))),
  (New-Object System.Drawing.Point (($rx + 102), ($ry + 12))),
  (New-Object System.Drawing.Point (($rx + 92), ($ry + 62))),
  (New-Object System.Drawing.Point (($rx + 26), ($ry + 62)))
))
$g.FillPath((Brush (RGB 92 83 74)), $facet)

$hi = New-Object System.Drawing.Drawing2D.GraphicsPath
$hi.AddPolygon(@(
  (New-Object System.Drawing.Point (($rx - 62), ($ry - 44))),
  (New-Object System.Drawing.Point (($rx + 4),  ($ry - 66))),
  (New-Object System.Drawing.Point (($rx - 14), ($ry - 22))),
  (New-Object System.Drawing.Point (($rx - 74), ($ry - 6)))
))
$g.FillPath((Brush (RGB 156 145 133)), $hi)

# Crack, hinting that this is the one to break.
$crackPen = Pen (RGB 46 40 35) 7
$crackPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$crackPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLines($crackPen, @(
  (New-Object System.Drawing.Point (($rx + 2),  ($ry - 64))),
  (New-Object System.Drawing.Point (($rx - 12), ($ry - 18))),
  (New-Object System.Drawing.Point (($rx + 16), ($ry + 4))),
  (New-Object System.Drawing.Point (($rx - 4),  ($ry + 62)))
))

$g.DrawPath((Pen (RGB 34 30 26) 8), $rock)

# ------------------------------------------------------- violet marker bracket
# The shape Secrets Reveal draws over this exact rock.
$mv  = RGB 190 116 248
$mPen = Pen $mv 9
$mPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$mPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round

$bl = $rx - 132; $br = $rx + 132
$bt = $ry - 100; $bb = $ry + 92
$arm = 38
foreach ($c in @(@($bl, $bt, 1, 1), @($br, $bt, -1, 1), @($bl, $bb, 1, -1), @($br, $bb, -1, -1))) {
  $x = $c[0]; $y = $c[1]; $sx = $c[2]; $sy = $c[3]
  $g.DrawLine($mPen, $x, $y, ($x + $arm * $sx), $y)
  $g.DrawLine($mPen, $x, $y, $x, ($y + $arm * $sy))
}

# ---------------------------------------------------------------------- text
function FirstFont([string[]]$names, [single]$size, $style) {
  foreach ($n in $names) {
    $f = New-Object System.Drawing.Font $n, $size, $style, ([System.Drawing.GraphicsUnit]::Pixel)
    if ($f.Name -eq $n) { return $f }
    $f.Dispose()
  }
  return New-Object System.Drawing.Font 'Arial', $size, $style, ([System.Drawing.GraphicsUnit]::Pixel)
}

$bold = [System.Drawing.FontStyle]::Bold

# Shrink until the widest line actually fits. Centre-aligned DrawString clips
# rather than overflows, so an unchecked size silently eats a letter -- which is
# exactly what happened to the S in CRAWLSPACES the first time round.
function FitFont([string[]]$names, [single]$start, $style, [string]$widest, [single]$maxW) {
  for ($size = $start; $size -gt 12; $size -= 1) {
    $f = FirstFont $names $size $style
    if ($g.MeasureString($widest, $f).Width -le $maxW) { return $f }
    $f.Dispose()
  }
  return FirstFont $names 12 $style
}

$titleFont = FitFont @('Arial Black', 'Segoe UI Black', 'Impact', 'Arial') 74 $bold 'CRAWLSPACES' 588
$subFont   = FitFont @('Segoe UI Semibold', 'Segoe UI', 'Arial') 27 $bold 'ONE PER FLOOR  -  ALWAYS REACHABLE' 588

$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = [System.Drawing.StringAlignment]::Center
$fmt.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

function Shadowed([string]$text, $font, [single]$y, $color, [int]$blur = 5) {
  $h = $font.GetHeight($g) * 1.6
  $r  = New-Object System.Drawing.RectangleF 0, $y, $S, $h
  $sr = New-Object System.Drawing.RectangleF 0, ($y + $blur), $S, $h
  $g.DrawString($text, $font, (Brush (RGB 0 0 0 200)), $sr, $fmt)
  $g.DrawString($text, $font, (Brush $color), $r, $fmt)
}

$lineH = $titleFont.GetHeight($g) * 0.92

# Dark plate behind the title so it stays legible, sized to the text it holds.
$plateH = [int](22 + $lineH * 2 + 14)
$plate = New-Object System.Drawing.Rectangle 0, 0, $S, $plateH
$plateBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  $plate, (RGB 10 8 7 240), (RGB 10 8 7 110), 90.0)
$g.FillRectangle($plateBrush, $plate)

Shadowed 'GUARANTEED'  $titleFont 20            (RGB 245 240 232)
Shadowed 'CRAWLSPACES' $titleFont (20 + $lineH) $mv

# Bottom strap line.
$strap = New-Object System.Drawing.Rectangle 0, 546, $S, 94
$g.FillRectangle((Brush (RGB 8 6 6 225)), $strap)
$g.DrawLine((Pen $mv 4), 0, 546, $S, 546)
Shadowed 'ONE PER FLOOR  -  ALWAYS REACHABLE' $subFont 572 (RGB 214 204 192) 3

# ---------------------------------------------------------------------- save
$g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$kb = [math]::Round((Get-Item $out).Length / 1KB, 1)
Write-Host "wrote $out  (${kb} KB)"
