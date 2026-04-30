function ConvertFrom-WacTuiRenderCodePoint {
  param([Parameter(Mandatory = $true)][int[]]$CodePoint)

  return -join ($CodePoint | ForEach-Object { [char]$_ })
}

$script:WacTuiSelectedLinePrefix = "[[WAC_TUI_SELECTED]]"
$script:WacTuiNoWrapLinePrefix = "[[WAC_TUI_NOWRAP]]"
$script:WacTuiButtonRowPrefix = "[[WAC_TUI_BUTTON_ROW]]"

function New-WacTuiSelectedLine {
  param([AllowNull()][string]$Text = "")

  if ($null -eq $Text) { $Text = "" }
  return $script:WacTuiSelectedLinePrefix + $Text
}

function Test-WacTuiSelectedLine {
  param([AllowNull()][string]$Text = "")

  if ($null -eq $Text) { return $false }
  return $Text.StartsWith($script:WacTuiSelectedLinePrefix)
}

function Remove-WacTuiSelectedLinePrefix {
  param([AllowNull()][string]$Text = "")

  if ($null -eq $Text) { return "" }
  if (Test-WacTuiSelectedLine -Text $Text) {
    return $Text.Substring($script:WacTuiSelectedLinePrefix.Length)
  }
  return $Text
}

function New-WacTuiNoWrapLine {
  param([AllowNull()][string]$Text = "")

  if ($null -eq $Text) { $Text = "" }
  return $script:WacTuiNoWrapLinePrefix + $Text
}

function Test-WacTuiNoWrapLine {
  param([AllowNull()][string]$Text = "")

  if ($null -eq $Text) { return $false }
  return $Text.StartsWith($script:WacTuiNoWrapLinePrefix)
}

function Remove-WacTuiNoWrapLinePrefix {
  param([AllowNull()][string]$Text = "")

  if ($null -eq $Text) { return "" }
  if (Test-WacTuiNoWrapLine -Text $Text) {
    return $Text.Substring($script:WacTuiNoWrapLinePrefix.Length)
  }
  return $Text
}

function New-WacTuiButtonRowLine {
  param([AllowNull()][string]$Text = "")

  if ($null -eq $Text) { $Text = "" }
  return $script:WacTuiButtonRowPrefix + $Text
}

function Test-WacTuiButtonRowLine {
  param([AllowNull()][string]$Text = "")

  if ($null -eq $Text) { return $false }
  return $Text.StartsWith($script:WacTuiButtonRowPrefix)
}

function Remove-WacTuiButtonRowPrefix {
  param([AllowNull()][string]$Text = "")

  if ($null -eq $Text) { return "" }
  if (Test-WacTuiButtonRowLine -Text $Text) {
    return $Text.Substring($script:WacTuiButtonRowPrefix.Length)
  }
  return $Text
}

function Add-WacTuiInverseVideo {
  param([string]$Text = "")

  $escape = [char]27
  return "$escape[7m$Text$escape[0m"
}

function Add-WacTuiSelectedVideo {
  param([string]$Text = "")

  $escape = [char]27
  $plain = Remove-WacTuiAnsi -Text $Text
  if ($Text.Contains("$escape[31m")) {
    return "$escape[37;41m$plain$escape[0m"
  }
  return (Add-WacTuiInverseVideo -Text $plain)
}

function Add-WacTuiDim {
  param([string]$Text = "")

  $escape = [char]27
  return "$escape[2m$Text$escape[0m"
}

function Add-WacTuiAccent {
  param([string]$Text = "")

  $escape = [char]27
  return "$escape[36m$Text$escape[0m"
}

function Add-WacTuiWarning {
  param([string]$Text = "")

  $escape = [char]27
  return "$escape[33m$Text$escape[0m"
}

function Add-WacTuiDanger {
  param([string]$Text = "")

  $escape = [char]27
  return "$escape[31m$Text$escape[0m"
}

function Format-WacTuiButton {
  param(
    [string]$Text = "",
    [bool]$Selected = $false
  )

  $button = ("[ {0} ]" -f $Text)
  if ($Selected) { return (Add-WacTuiInverseVideo -Text $button) }
  return $button
}

function Remove-WacTuiAnsi {
  param([AllowNull()][string]$Text = "")

  if ($null -eq $Text) { return "" }
  return [regex]::Replace($Text, "$([char]27)\[[0-9;]*m", "")
}

function Get-WacTuiVisibleLength {
  param([AllowNull()][string]$Text = "")

  $plain = Remove-WacTuiAnsi -Text $Text
  $length = 0
  for ($index = 0; $index -lt $plain.Length; $index++) {
    $code = [int][char]$plain[$index]
    if ($code -eq 0xFE0F) { continue }
    if ($code -ge 0x2600 -and $code -le 0x27BF) {
      $length += 2
      continue
    }
    if ($code -ge 0xD800 -and $code -le 0xDBFF -and ($index + 1) -lt $plain.Length) {
      $next = [int][char]$plain[$index + 1]
      if ($next -ge 0xDC00 -and $next -le 0xDFFF) {
        $length += 2
        $index++
        continue
      }
    }
    $length++
  }
  return $length
}

function Format-WacTuiVisiblePadRight {
  param(
    [AllowNull()][string]$Text = "",
    [int]$Width = 0
  )

  if ($null -eq $Text) { $Text = "" }
  $visibleLength = Get-WacTuiVisibleLength -Text $Text
  if ($visibleLength -ge $Width) { return $Text }
  return $Text + (" " * ($Width - $visibleLength))
}

function Split-WacTuiText {
  param(
    [AllowNull()][string]$Text = "",
    [int]$Width = 80
  )

  if ($Width -lt 1) { return ,@("") }
  if ($null -eq $Text) { $Text = "" }
  if ($Text.Length -le $Width) { return ,([string[]]@($Text)) }

  $lines = New-Object System.Collections.ArrayList
  $current = ""
  $words = [regex]::Matches($Text, "\S+") | ForEach-Object { $_.Value }

  foreach ($wordValue in $words) {
    $word = [string]$wordValue

    while ($word.Length -gt $Width) {
      if ($current.Length -gt 0) {
        [void]$lines.Add($current)
        $current = ""
      }

      [void]$lines.Add($word.Substring(0, $Width))
      $word = $word.Substring($Width)
    }

    if ($word.Length -eq 0) { continue }

    if ($current.Length -eq 0) {
      $current = $word
    } elseif (($current.Length + 1 + $word.Length) -le $Width) {
      $current = "$current $word"
    } else {
      [void]$lines.Add($current)
      $current = $word
    }
  }

  if ($current.Length -gt 0) {
    [void]$lines.Add($current)
  }

  if ($lines.Count -eq 0) {
    [void]$lines.Add("")
  }

  return ,([string[]]$lines.ToArray())
}

function Split-WacTuiHangingText {
  param(
    [AllowNull()][string]$Text = "",
    [int]$Width = 80,
    [int]$ContinuationColumn = 0
  )

  if ($Width -lt 1) { return ,@("") }
  if ($null -eq $Text) { $Text = "" }
  if ($Text.Length -le $Width) { return ,([string[]]@($Text)) }
  if ($ContinuationColumn -lt 0) { $ContinuationColumn = 0 }
  if ($ContinuationColumn -ge ($Width - 4)) {
    return ,(Split-WacTuiText -Text $Text -Width $Width)
  }

  $prefix = ""
  $remaining = $Text
  if ($Text.Length -gt $ContinuationColumn) {
    $prefix = $Text.Substring(0, $ContinuationColumn)
    $remaining = $Text.Substring($ContinuationColumn)
  }

  $lines = New-Object System.Collections.ArrayList
  $firstWidth = $Width - $prefix.Length
  $continuationPrefix = " " * $prefix.Length
  foreach ($part in (Split-WacTuiText -Text $remaining -Width $firstWidth)) {
    if ($lines.Count -eq 0) {
      [void]$lines.Add($prefix + $part)
    } else {
      [void]$lines.Add($continuationPrefix + $part)
    }
  }

  return ,([string[]]$lines.ToArray())
}

function Split-WacTuiButtonRow {
  param(
    [AllowNull()][string]$Text = "",
    [int]$Width = 80
  )

  if ($Width -lt 1) { return ,@("") }
  if ($null -eq $Text) { $Text = "" }
  if ((Get-WacTuiVisibleLength -Text $Text) -le $Width) { return ,([string[]]@($Text)) }

  $indentMatch = [regex]::Match($Text, "^\s*")
  $indent = $indentMatch.Value
  $body = $Text.Substring($indent.Length)
  $buttons = $body -split "  " | Where-Object { -not [string]::IsNullOrWhiteSpace((Remove-WacTuiAnsi -Text $_)) }
  $lines = New-Object System.Collections.ArrayList
  $current = $indent

  foreach ($button in $buttons) {
    $candidate = if ($current -eq $indent) { $current + $button } else { $current + "  " + $button }
    if ((Get-WacTuiVisibleLength -Text $candidate) -le $Width) {
      $current = $candidate
      continue
    }

    if ($current -ne $indent) {
      [void]$lines.Add($current)
    }
    $current = $indent + $button
  }

  if ($current -ne $indent) {
    [void]$lines.Add($current)
  }

  if ($lines.Count -eq 0) {
    [void]$lines.Add($indent)
  }

  return ,([string[]]$lines.ToArray())
}

function Format-WacTuiEllipsis {
  param(
    [AllowNull()][string]$Text = "",
    [int]$Width = 80
  )

  if ($Width -lt 1) { return "" }
  if ($null -eq $Text) { $Text = "" }
  if ((Get-WacTuiVisibleLength -Text $Text) -le $Width) { return $Text }
  if ($Text.Length -le $Width) { return $Text }

  if ($Width -le 3) {
    return "...".Substring(0, $Width)
  }

  $available = $Width - 3
  $left = [int][Math]::Ceiling($available / 2)
  $right = $available - $left

  return $Text.Substring(0, $left) + "..." + $Text.Substring($Text.Length - $right)
}

function New-WacTuiFrame {
  param(
    [AllowNull()][string]$Title = "",
    [AllowNull()][string[]]$Lines = @(),
    [int]$Width = 80,
    [switch]$UseUnicode
  )

  if ($Width -lt 2) { $Width = 2 }

  if ($UseUnicode) {
    $topLeft = ConvertFrom-WacTuiRenderCodePoint @(0x250C)
    $topRight = ConvertFrom-WacTuiRenderCodePoint @(0x2510)
    $bottomLeft = ConvertFrom-WacTuiRenderCodePoint @(0x2514)
    $bottomRight = ConvertFrom-WacTuiRenderCodePoint @(0x2518)
    $horizontal = ConvertFrom-WacTuiRenderCodePoint @(0x2500)
    $vertical = ConvertFrom-WacTuiRenderCodePoint @(0x2502)
  } else {
    $topLeft = "+"
    $topRight = "+"
    $bottomLeft = "+"
    $bottomRight = "+"
    $horizontal = "-"
    $vertical = "|"
  }

  $innerWidth = $Width - 2
  $frame = New-Object System.Collections.ArrayList
  [void]$frame.Add($topLeft + ($horizontal * $innerWidth) + $topRight)

  $content = New-Object System.Collections.ArrayList
  if (-not [string]::IsNullOrWhiteSpace($Title)) {
    [void]$content.Add($Title)
  }

  if ($null -ne $Lines) {
    foreach ($line in $Lines) {
      $lineText = [string]$line
      $selected = Test-WacTuiSelectedLine -Text $lineText
      $lineText = Remove-WacTuiSelectedLinePrefix -Text $lineText
      $buttonRow = Test-WacTuiButtonRowLine -Text $lineText
      $lineText = Remove-WacTuiButtonRowPrefix -Text $lineText
      if ($buttonRow) {
        foreach ($wrapped in (Split-WacTuiButtonRow -Text $lineText -Width $innerWidth)) {
          [void]$content.Add([pscustomobject]@{
            Text = $wrapped
            Selected = $selected
          })
        }
        continue
      }
      $noWrap = Test-WacTuiNoWrapLine -Text $lineText
      $lineText = Remove-WacTuiNoWrapLinePrefix -Text $lineText
      if ($noWrap) {
        $continuationColumn = $lineText.IndexOf(" : ")
        if ($continuationColumn -ge 0) {
          $continuationColumn += 3
        } else {
          $continuationColumn = 0
        }
        foreach ($wrapped in (Split-WacTuiHangingText -Text $lineText -Width $innerWidth -ContinuationColumn $continuationColumn)) {
          [void]$content.Add([pscustomobject]@{
            Text = $wrapped
            Selected = $selected
          })
        }
        continue
      }
      foreach ($wrapped in (Split-WacTuiText -Text $lineText -Width $innerWidth)) {
        [void]$content.Add([pscustomobject]@{
          Text = $wrapped
          Selected = $selected
        })
      }
    }
  }

  foreach ($entry in $content) {
    if ($entry -is [string]) {
      $text = Format-WacTuiEllipsis -Text $entry -Width $innerWidth
      [void]$frame.Add($vertical + (Format-WacTuiVisiblePadRight -Text $text -Width $innerWidth) + $vertical)
      continue
    }

    $text = Format-WacTuiEllipsis -Text ([string]$entry.Text) -Width $innerWidth
    $padded = Format-WacTuiVisiblePadRight -Text $text -Width $innerWidth
    if ($entry.Selected) {
      $padded = Add-WacTuiSelectedVideo -Text $padded
    }
    [void]$frame.Add($vertical + $padded + $vertical)
  }

  [void]$frame.Add($bottomLeft + ($horizontal * $innerWidth) + $bottomRight)

  return ,([string[]]$frame.ToArray())
}

function New-WacTuiProgressBar {
  param(
    [int]$Percent = 0,
    [int]$Width = 20,
    [switch]$UseUnicode
  )

  if ($Width -lt 0) { $Width = 0 }
  if ($Percent -lt 0) { $Percent = 0 }
  if ($Percent -gt 100) { $Percent = 100 }

  if ($UseUnicode) {
    $fillChar = ConvertFrom-WacTuiRenderCodePoint @(0x2588)
    $emptyChar = ConvertFrom-WacTuiRenderCodePoint @(0x2591)
  } else {
    $fillChar = "#"
    $emptyChar = "-"
  }

  $filled = [int][Math]::Floor(($Percent * $Width) / 100)
  $empty = $Width - $filled

  return "[" + ($fillChar * $filled) + ($emptyChar * $empty) + "] $Percent%"
}
