param(
  [string]$Source = 'assets/stickers/sticker_sheet_source.png',
  [switch]$ReportOnly,
  [int]$Gap = 28
)

Add-Type -AssemblyName System.Drawing

$sourceBitmap = [System.Drawing.Bitmap]::new((Resolve-Path $Source).Path)
$width = $sourceBitmap.Width
$height = $sourceBitmap.Height
$visited = New-Object 'bool[,]' $width, $height
$components = [System.Collections.Generic.List[object]]::new()
$directions = @(
  @(-1,-1), @(0,-1), @(1,-1), @(-1,0), @(1,0), @(-1,1), @(0,1), @(1,1)
)

for ($y = 0; $y -lt $height; $y++) {
  for ($x = 0; $x -lt $width; $x++) {
    if ($visited[$x,$y]) { continue }
    $pixel = $sourceBitmap.GetPixel($x, $y)
    if ($pixel.A -lt 24) { $visited[$x,$y] = $true; continue }

    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([System.Drawing.Point]::new($x, $y))
    $visited[$x,$y] = $true
    $left = $x; $top = $y; $right = $x; $bottom = $y; $area = 0
    $pixels = [System.Collections.Generic.List[int]]::new()
    while ($queue.Count -gt 0) {
      $point = $queue.Dequeue()
      $area++
      $pixels.Add($point.X + ($point.Y * $width))
      if ($point.X -lt $left) { $left = $point.X }
      if ($point.Y -lt $top) { $top = $point.Y }
      if ($point.X -gt $right) { $right = $point.X }
      if ($point.Y -gt $bottom) { $bottom = $point.Y }
      foreach ($direction in $directions) {
        $nx = $point.X + $direction[0]
        $ny = $point.Y + $direction[1]
        if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $width -or $ny -ge $height) { continue }
        if ($visited[$nx,$ny]) { continue }
        if ($sourceBitmap.GetPixel($nx, $ny).A -lt 24) { $visited[$nx,$ny] = $true; continue }
        $visited[$nx,$ny] = $true
        $queue.Enqueue([System.Drawing.Point]::new($nx, $ny))
      }
    }
    if ($area -ge 100) {
      $components.Add([pscustomobject]@{ Left=$left; Top=$top; Right=$right; Bottom=$bottom; Area=$area; Pixels=$pixels })
    }
  }
}

$groups = [System.Collections.Generic.List[object]]::new()
foreach ($component in $components) {
  $groups.Add([pscustomobject]@{
    Left=$component.Left; Top=$component.Top; Right=$component.Right; Bottom=$component.Bottom; Area=$component.Area; Pixels=$component.Pixels
  })
}

$changed = $true
while ($changed) {
  $changed = $false
  for ($i = 0; $i -lt $groups.Count; $i++) {
    for ($j = $i + 1; $j -lt $groups.Count; $j++) {
      $a = $groups[$i]; $b = $groups[$j]
      $horizontalGap = if ($b.Left -gt $a.Right) { $b.Left - $a.Right } elseif ($a.Left -gt $b.Right) { $a.Left - $b.Right } else { 0 }
      $verticalGap = if ($b.Top -gt $a.Bottom) { $b.Top - $a.Bottom } elseif ($a.Top -gt $b.Bottom) { $a.Top - $b.Bottom } else { 0 }
      if ($horizontalGap -le $Gap -and $verticalGap -le $Gap) {
        $a.Left = [Math]::Min($a.Left, $b.Left); $a.Top = [Math]::Min($a.Top, $b.Top)
        $a.Right = [Math]::Max($a.Right, $b.Right); $a.Bottom = [Math]::Max($a.Bottom, $b.Bottom)
        $a.Area += $b.Area
        $a.Pixels.AddRange($b.Pixels)
        $groups.RemoveAt($j)
        $changed = $true
        break
      }
    }
    if ($changed) { break }
  }
}

$ordered = $groups | Sort-Object Top, Left
Write-Output "source: ${width}x${height}"
Write-Output "components: $($components.Count), groups: $($ordered.Count)"
$index = 1
foreach ($group in $ordered) {
  Write-Output ("{0}: {1},{2} {3}x{4} area={5}" -f $index, $group.Left, $group.Top, ($group.Right-$group.Left+1), ($group.Bottom-$group.Top+1), $group.Area)
  $index++
}

if (-not $ReportOnly) {
  $output = Join-Path (Split-Path $Source) 'extracted'
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  $index = 1
  foreach ($group in $ordered) {
    $padding = 10
    $left = [Math]::Max(0, $group.Left - $padding)
    $top = [Math]::Max(0, $group.Top - $padding)
    $right = [Math]::Min($width - 1, $group.Right + $padding)
    $bottom = [Math]::Min($height - 1, $group.Bottom + $padding)
    $cropWidth = $right - $left + 1
    $cropHeight = $bottom - $top + 1
    $crop = [System.Drawing.Bitmap]::new(
      $cropWidth,
      $cropHeight,
      [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $core = [System.Collections.Generic.HashSet[int]]::new($group.Pixels)
    for ($cy = 0; $cy -lt $cropHeight; $cy++) {
      for ($cx = 0; $cx -lt $cropWidth; $cx++) {
        $sourceX = $left + $cx
        $sourceY = $top + $cy
        $sourceIndex = $sourceX + ($sourceY * $width)
        $keep = $core.Contains($sourceIndex)
        if (-not $keep) {
          for ($dy = -2; $dy -le 2 -and -not $keep; $dy++) {
            for ($dx = -2; $dx -le 2 -and -not $keep; $dx++) {
              if ($core.Contains(($sourceX + $dx) + (($sourceY + $dy) * $width))) {
                $keep = $true
              }
            }
          }
        }
        if ($keep) {
          $crop.SetPixel($cx, $cy, $sourceBitmap.GetPixel($sourceX, $sourceY))
        }
      }
    }
    $path = Join-Path $output ('sticker_{0:D2}.png' -f $index)
    $crop.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $crop.Dispose()
    $index++
  }
}
$sourceBitmap.Dispose()
