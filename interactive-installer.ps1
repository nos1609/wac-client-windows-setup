<#
.SYNOPSIS
  Interactive TUI wrapper for the WAC setup engine.
#>

[CmdletBinding()]
param(
  [ValidateSet("Auto", "Ru", "En")]
  [string]$Language = "Auto",
  [switch]$NoEmoji,
  [switch]$Ascii,
  [switch]$PlanOnly
)

$ErrorActionPreference = "Stop"

$script:ScriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $script:ScriptRoot "tui\WacTui.Locale.ps1")
. (Join-Path $script:ScriptRoot "tui\WacTui.Model.ps1")
. (Join-Path $script:ScriptRoot "tui\WacTui.Validation.ps1")
. (Join-Path $script:ScriptRoot "tui\WacTui.Render.ps1")
. (Join-Path $script:ScriptRoot "tui\WacTui.Progress.ps1")
$script:WacTuiUseVisuals = (-not $Ascii)
$script:WacTuiUseEmoji = (-not $Ascii -and -not $NoEmoji)
$script:ResolvedLanguage = Get-WacTuiLanguage -Language $Language

function Get-WacTuiConsoleSnapshot {
  $consoleWidth = 0
  $consoleHeight = 0
  $rawWidth = 0
  $rawHeight = 0

  try {
    $consoleWidth = [Console]::WindowWidth
    $consoleHeight = [Console]::WindowHeight
  } catch {
  }

  try {
    $rawWidth = $Host.UI.RawUI.WindowSize.Width
    $rawHeight = $Host.UI.RawUI.WindowSize.Height
  } catch {
  }

  $widthCandidates = @($consoleWidth, $rawWidth) | Where-Object { $_ -ge 1 }
  $heightCandidates = @($consoleHeight, $rawHeight) | Where-Object { $_ -ge 1 }
  $width = 78
  $height = 24
  if ($widthCandidates.Count -gt 0) {
    $width = ($widthCandidates | Measure-Object -Maximum).Maximum
  }
  if ($heightCandidates.Count -gt 0) {
    $height = ($heightCandidates | Measure-Object -Minimum).Minimum
  }

  if ($width -lt 40) { $width = 40 }

  return [pscustomobject]@{
    Width = [int]$width
    Height = [int]$height
    Key = ("c{0}x{1}|r{2}x{3}|w{4}" -f $consoleWidth, $consoleHeight, $rawWidth, $rawHeight, $width)
  }
}

function Get-WacTuiConsoleWidth {
  return (Get-WacTuiConsoleSnapshot).Width
}

function Get-WacTuiConsoleSizeKey {
  return (Get-WacTuiConsoleSnapshot).Key
}

function Get-WacTuiPreferredLayout {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En",
    [switch]$UseUnicode
  )

  $width = 100
  $frames = @(
    (New-WacTuiFrame -Title (Get-WacTuiUiText -Key "Title" -Language $Language) -Lines (New-WacTuiWelcomeLines -Language $Language -SelectedIndex 0) -Width $width -UseUnicode:$UseUnicode),
    (New-WacTuiFrame -Title (Get-WacTuiUiText -Key "LicenseTitle" -Language $Language) -Lines (New-WacTuiLicenseLines -Language $Language -Accepted $true -SelectedIndex 1) -Width $width -UseUnicode:$UseUnicode),
    (New-WacTuiFrame -Title (Get-WacTuiUiText -Key "ModeTitle" -Language $Language) -Lines (New-WacTuiModeLines -Language $Language -SelectedIndex 3) -Width $width -UseUnicode:$UseUnicode),
    (New-WacTuiFrame -Title (Get-WacTuiUiText -Key "CustomTitle" -Language $Language) -Lines (New-WacTuiCustomLines -Config $Config -Language $Language -SelectedIndex 20) -Width $width -UseUnicode:$UseUnicode),
    (New-WacTuiFrame -Title (Get-WacTuiReadyTitle -Config $Config -Language $Language) -Lines (New-WacTuiReadyLines -Config $Config -Language $Language -SelectedIndex 2) -Width $width -UseUnicode:$UseUnicode),
    (New-WacTuiFrame -Title (Get-WacTuiDetailsTitle -Config $Config -Language $Language) -Lines (New-WacTuiDetailsLines -Config $Config -Language $Language -SelectedIndex 0) -Width $width -UseUnicode:$UseUnicode)
  )

  $height = 24
  foreach ($frame in $frames) {
    if ($frame.Count -gt $height) { $height = $frame.Count }
  }

  return [pscustomobject]@{
    Width = $width
    Height = ($height + 1)
  }
}

function ConvertTo-WacTuiHostSize {
  param(
    [int]$Width,
    [int]$Height
  )

  return (New-Object System.Management.Automation.Host.Size -ArgumentList @($Width, $Height))
}

function Set-WacTuiPreferredWindowSize {
  param(
    [int]$Width,
    [int]$Height
  )

  if ($Width -lt 40) { $Width = 40 }
  if ($Height -lt 20) { $Height = 20 }

  try {
    $current = Get-WacTuiConsoleSnapshot
    if ($current.Width -gt $Width) { $Width = $current.Width }
    if ($current.Height -gt $Height) { $Height = $current.Height }

    $raw = $Host.UI.RawUI
    $max = $raw.MaxPhysicalWindowSize
    if ($max.Width -ge 40 -and $Width -gt $max.Width) { $Width = $max.Width }
    if ($max.Height -ge 20 -and $Height -gt $max.Height) { $Height = $max.Height }

    $buffer = $raw.BufferSize
    $bufferWidth = [Math]::Max($buffer.Width, $Width)
    $bufferHeight = [Math]::Max($buffer.Height, $Height)
    if ($bufferWidth -ne $buffer.Width -or $bufferHeight -ne $buffer.Height) {
      $raw.BufferSize = ConvertTo-WacTuiHostSize -Width $bufferWidth -Height $bufferHeight
    }

    $raw.WindowSize = ConvertTo-WacTuiHostSize -Width $Width -Height $Height

    return $true
  } catch {
    return $false
  }
}

function Set-WacTuiWizardWindowSize {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  $layout = Get-WacTuiPreferredLayout -Config $Config -Language $Language -UseUnicode:(!$Ascii)
  [void](Set-WacTuiPreferredWindowSize -Width $layout.Width -Height $layout.Height)
}

function Clear-WacTuiScreen {
  try {
    Clear-Host
    return
  } catch {
  }

  try {
    [Console]::Clear()
    return
  } catch {
  }

  Write-Host ""
}

function Show-WacTuiFrame {
  param(
    [string]$Title,
    [string[]]$Lines
  )

  Set-WacTuiTerminalTitle -Title $Title
  $useUnicode = -not $Ascii
  $snapshot = Get-WacTuiConsoleSnapshot
  $frame = New-WacTuiFrame -Title $Title -Lines $Lines -Width $snapshot.Width -UseUnicode:$useUnicode
  if ($snapshot.Height -ge 10 -and $frame.Count -gt $snapshot.Height) {
    $frame = Select-WacTuiFrameViewport -Frame $frame -Height $snapshot.Height
  }
  Clear-WacTuiScreen
  foreach ($line in $frame) {
    Write-Host $line
  }
}

function Set-WacTuiCursorVisible {
  param([bool]$Visible)

  try {
    $previous = [Console]::CursorVisible
    [Console]::CursorVisible = $Visible
    return $previous
  } catch {
    return $null
  }
}

function Wait-WacTuiOnExit {
  param(
    [ValidateSet("Ru", "En")]
    [string]$Language = (Get-WacTuiLanguage -Language $script:ResolvedLanguage)
  )

  if ($env:WAC_WAIT_ON_EXIT -ne "1") { return }
  try {
    [void](Read-Host (Get-WacTuiUiText -Key "PressEnterToClose" -Language $Language))
  } catch {
  }
}

function Add-WacTuiUiDim {
  param([string]$Text = "")

  if (-not $script:WacTuiUseVisuals) { return $Text }
  return Add-WacTuiDim -Text $Text
}

function Add-WacTuiUiAccent {
  param([string]$Text = "")

  if (-not $script:WacTuiUseVisuals) { return $Text }
  return Add-WacTuiAccent -Text $Text
}

function Add-WacTuiUiWarning {
  param([string]$Text = "")

  if (-not $script:WacTuiUseVisuals) { return $Text }
  return Add-WacTuiWarning -Text $Text
}

function Add-WacTuiUiDanger {
  param([string]$Text = "")

  if (-not $script:WacTuiUseVisuals) { return $Text }
  return Add-WacTuiDanger -Text $Text
}

function Get-WacTuiIcon {
  param([string]$Name = "")

  if (-not $script:WacTuiUseEmoji) { return "" }
  switch ($Name) {
    "Source" { return "📦 " }
    "Mode" { return "🧭 " }
    "Invoke" { return "▶️ " }
    "License" { return "📜 " }
    "Privacy" { return "🔒 " }
    "Custom" { return "⚙️ " }
    "Ready" { return "✅ " }
    "Details" { return "📋 " }
    "Install" { return "🚀 " }
    "Uninstall" { return "🗑️ " }
    "Log" { return "🧾 " }
    default { return "" }
  }
}

function Select-WacTuiFrameViewport {
  param(
    [Parameter(Mandatory = $true)][string[]]$Frame,
    [int]$Height = 24
  )

  if ($Height -lt 10 -or $Frame.Count -le $Height) { return ,$Frame }

  $topCount = 2
  $bottomCount = 4
  if (($topCount + $bottomCount) -ge $Height) { return ,($Frame | Select-Object -First $Height) }

  $middleHeight = $Height - $topCount - $bottomCount
  $selectedIndex = -1
  for ($index = 0; $index -lt $Frame.Count; $index++) {
    if ($Frame[$index].Contains("$([char]27)[7m")) {
      $selectedIndex = $index
      break
    }
  }

  $middleStart = $topCount
  if ($selectedIndex -ge $topCount -and $selectedIndex -lt ($Frame.Count - $bottomCount)) {
    $middleStart = $selectedIndex - [int][Math]::Floor($middleHeight / 2)
  }
  if ($middleStart -lt $topCount) { $middleStart = $topCount }

  $lastMiddleStart = $Frame.Count - $bottomCount - $middleHeight
  if ($lastMiddleStart -lt $topCount) { $lastMiddleStart = $topCount }
  if ($middleStart -gt $lastMiddleStart) { $middleStart = $lastMiddleStart }

  $result = New-Object System.Collections.ArrayList
  for ($index = 0; $index -lt $topCount; $index++) {
    [void]$result.Add($Frame[$index])
  }
  for ($index = $middleStart; $index -lt ($middleStart + $middleHeight); $index++) {
    [void]$result.Add($Frame[$index])
  }
  for ($index = ($Frame.Count - $bottomCount); $index -lt $Frame.Count; $index++) {
    [void]$result.Add($Frame[$index])
  }

  return ,([string[]]$result.ToArray())
}

function Set-WacTuiTerminalTitle {
  param([string]$Title = "")

  if ([string]::IsNullOrWhiteSpace($Title)) { return }
  try {
    $Host.UI.RawUI.WindowTitle = "WAC - $Title"
  } catch {
  }
}

function Get-WacTuiSpinnerFrame {
  param([int]$Index = 0)

  $frames = @("|", "/", "-", "\")
  if ($script:WacTuiUseEmoji) {
    $frames = @("◐", "◓", "◑", "◒")
  }
  return $frames[[Math]::Abs($Index % $frames.Count)]
}

function Set-WacTuiAnimatedTerminalTitle {
  param(
    [string]$Title = "",
    [int]$FrameIndex = 0
  )

  if ([string]::IsNullOrWhiteSpace($Title)) { return }
  try {
    $Host.UI.RawUI.WindowTitle = "{0} WAC - {1}" -f (Get-WacTuiSpinnerFrame -Index $FrameIndex), $Title
  } catch {
  }
}

function ConvertFrom-WacConsoleKeyInfo {
  param([Parameter(Mandatory = $true)]$KeyInfo)

  return [pscustomobject]@{
    Character = $KeyInfo.KeyChar
    VirtualKeyCode = [int]$KeyInfo.Key
  }
}

function Read-WacTuiInput {
  $initialSizeKey = Get-WacTuiConsoleSizeKey

  while ($true) {
    $currentSizeKey = Get-WacTuiConsoleSizeKey
    if (-not [string]::IsNullOrWhiteSpace($initialSizeKey) -and $currentSizeKey -ne $initialSizeKey) {
      return [pscustomobject]@{
        Kind = "Resize"
        Key = $null
      }
    }

    try {
      if ([Console]::KeyAvailable) {
        return [pscustomobject]@{
          Kind = "Key"
          Key = ConvertFrom-WacConsoleKeyInfo -KeyInfo ([Console]::ReadKey($true))
        }
      }
    } catch {
    }

    Start-Sleep -Milliseconds 80
  }
}

function Format-WacTuiButtonRow {
  param(
    [Parameter(Mandatory = $true)][object[]]$Buttons
  )

  $parts = New-Object System.Collections.ArrayList
  foreach ($button in $Buttons) {
    [void]$parts.Add((Format-WacTuiButton -Text $button.Text -Selected:$button.Selected))
  }

  $rowText = "    {0}" -f ([string]::Join("  ", [string[]]$parts.ToArray()))
  return (New-WacTuiButtonRowLine -Text $rowText)
}

function Read-WacTuiBlockingInput {
  try {
    return [pscustomobject]@{
      Kind = "Key"
      Key = ConvertFrom-WacConsoleKeyInfo -KeyInfo ([Console]::ReadKey($true))
    }
  } catch {
    return [pscustomobject]@{
      Kind = "Key"
      Key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
  }
}

function Get-WacTuiUiText {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [string]$Language = "En"
  )

  Get-WacTuiText -Key $Key -Language $Language
}

function Format-WacTuiUiText {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [string]$Language = "En",
    [object[]]$ArgumentList = @()
  )

  return [string]::Format((Get-WacTuiUiText -Key $Key -Language $Language), $ArgumentList)
}

function Get-WacTuiThirdPartyNoticePath {
  $candidates = New-Object System.Collections.ArrayList
  [void]$candidates.AddRange(@(
    (Join-Path $env:ProgramData "WindowsAdminCenter\UX\legal\3rdPartyDisclosure.html"),
    (Join-Path $env:ProgramData "WACSetup\payload\commonappdata\WindowsAdminCenter\UX\legal\3rdPartyDisclosure.html")
  ))

  $setupRoot = Join-Path $env:ProgramData "WACSetup"
  if (Test-Path -LiteralPath $setupRoot) {
    Get-ChildItem -LiteralPath $setupRoot -Directory -Filter "payload*" -ErrorAction SilentlyContinue |
      ForEach-Object {
        [void]$candidates.Add((Join-Path $_.FullName "commonappdata\WindowsAdminCenter\UX\legal\3rdPartyDisclosure.html"))
      }
  }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }

  return ""
}

function New-WacTuiLicenseLines {
  param(
    [string]$Language = "En",
    [bool]$Accepted = $false,
    [int]$SelectedIndex = 1
  )

  $checkboxKey = if ($Accepted) { "LicenseCheckboxOn" } else { "LicenseCheckbox" }
  $lines = New-Object System.Collections.ArrayList
  $thirdParty = Get-WacTuiThirdPartyNoticePath
  [void]$lines.Add((Add-WacTuiUiAccent -Text ("{0}{1}" -f (Get-WacTuiIcon -Name "License"), (Get-WacTuiUiText -Key "LicenseIntro" -Language $Language))))
  [void]$lines.Add((Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "LicenseProjectNotice" -Language $Language)))
  if (-not $thirdParty) {
    [void]$lines.Add((Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "LicenseNoLocal" -Language $Language)))
  }
  [void]$lines.Add(("{0}{1}" -f (Get-WacTuiIcon -Name "License"), (Get-WacTuiUiText -Key "LicenseTermsUrl" -Language $Language)))
  [void]$lines.Add(("{0}{1}" -f (Get-WacTuiIcon -Name "License"), (Get-WacTuiUiText -Key "LicenseEulaUrl" -Language $Language)))
  [void]$lines.Add(("{0}{1}" -f (Get-WacTuiIcon -Name "Privacy"), (Get-WacTuiUiText -Key "PrivacyUrl" -Language $Language)))

  if ($thirdParty) {
    [void]$lines.Add((Format-WacTuiUiText -Key "ThirdParty" -Language $Language -ArgumentList @($thirdParty)))
  }

  [void]$lines.Add("")
  [void]$lines.Add((Get-WacTuiUiText -Key $checkboxKey -Language $Language))
  [void]$lines.Add((Format-WacTuiButtonRow -Buttons @(
    [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Back" -Language $Language); Selected = ($SelectedIndex -eq 0) },
    [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Next" -Language $Language); Selected = ($SelectedIndex -eq 1) },
    [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Cancel" -Language $Language); Selected = ($SelectedIndex -eq 2) }
  )))
  [void]$lines.Add((Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "LicensePrompt" -Language $Language)))
  return [string[]]$lines.ToArray()
}

function Show-WacTuiLicenseScreen {
  param([string]$Language = "En")

  $accepted = $false
  $selectedIndex = 1
  while ($true) {
    Show-WacTuiFrame -Title (Get-WacTuiUiText -Key "LicenseTitle" -Language $Language) -Lines (New-WacTuiLicenseLines -Language $Language -Accepted $accepted -SelectedIndex $selectedIndex)
    $inputEvent = Read-WacTuiInput
    if ($inputEvent.Kind -eq "Resize") { continue }
    $key = $inputEvent.Key
    if ($key.VirtualKeyCode -eq 37 -or $key.VirtualKeyCode -eq 38) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta -1 -ItemCount 3
      continue
    }
    if ($key.VirtualKeyCode -eq 39 -or $key.VirtualKeyCode -eq 40) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta 1 -ItemCount 3
      continue
    }
    if ($key.Character -eq " ") {
      $accepted = -not $accepted
      continue
    }
    $char = [char]::ToUpperInvariant($key.Character)
    if ($char -eq "B") { return "Back" }
    if ($char -eq "C") { return "Cancel" }
    if ($char -eq "N") {
      if ($accepted) { return "Next" }
      Show-WacTuiFrame -Title (Get-WacTuiUiText -Key "LicenseTitle" -Language $Language) -Lines @(
        (Add-WacTuiUiWarning -Text (Get-WacTuiUiText -Key "LicenseRequired" -Language $Language)),
        "",
        (Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "LicensePrompt" -Language $Language))
      )
      Start-Sleep -Milliseconds 900
      continue
    }
    if ($key.VirtualKeyCode -eq 13) {
      if ($selectedIndex -eq 0) { return "Back" }
      if ($selectedIndex -eq 2) { return "Cancel" }
      if ($accepted) { return "Next" }
      Show-WacTuiFrame -Title (Get-WacTuiUiText -Key "LicenseTitle" -Language $Language) -Lines @(
        (Add-WacTuiUiWarning -Text (Get-WacTuiUiText -Key "LicenseRequired" -Language $Language)),
        "",
        (Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "LicensePrompt" -Language $Language))
      )
      Start-Sleep -Milliseconds 900
      continue
    }
  }
}

function Test-WacTuiUninstallAction {
  param([Parameter(Mandatory = $true)]$Config)

  return ($Config.Action -eq "Uninstall" -or $Config.Action -eq "UninstallFull")
}

function Get-WacTuiActionLabel {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  if ($Language -eq "Ru") {
    switch ($Config.Action) {
      "Uninstall" { return "удаление" }
      "UninstallFull" { return "полное удаление" }
    }
    switch ($Config.InstallMode) {
      "Express" { return "быстрая установка" }
      "Custom" { return "выборочная установка" }
      default { return [string]$Config.InstallMode }
    }
  }

  switch ($Config.Action) {
    "Uninstall" { return "uninstall" }
    "UninstallFull" { return "full uninstall" }
    default { return [string]$Config.InstallMode }
  }
}

function Get-WacTuiReadyTitle {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  if (Test-WacTuiUninstallAction -Config $Config) {
    return Get-WacTuiUiText -Key "ReadyUninstallTitle" -Language $Language
  }
  return Get-WacTuiUiText -Key "ReadyTitle" -Language $Language
}

function Get-WacTuiPrimaryActionText {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  switch ($Config.Action) {
    "Uninstall" { return Get-WacTuiUiText -Key "Uninstall" -Language $Language }
    "UninstallFull" { return Get-WacTuiUiText -Key "UninstallFull" -Language $Language }
    default { return Get-WacTuiUiText -Key "Install" -Language $Language }
  }
}

function Get-WacTuiOperationTitle {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  if (Test-WacTuiUninstallAction -Config $Config) {
    return Get-WacTuiUiText -Key "UninstallingTitle" -Language $Language
  }
  return Get-WacTuiUiText -Key "InstallingTitle" -Language $Language
}

function Get-WacTuiCompleteTitle {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  if (Test-WacTuiUninstallAction -Config $Config) {
    return Get-WacTuiUiText -Key "UninstallCompleteTitle" -Language $Language
  }
  return Get-WacTuiUiText -Key "CompleteTitle" -Language $Language
}

function Get-WacTuiDetailsTitle {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  if (Test-WacTuiUninstallAction -Config $Config) {
    return Get-WacTuiUiText -Key "DetailsUninstallTitle" -Language $Language
  }
  return Get-WacTuiUiText -Key "DetailsTitle" -Language $Language
}

function New-WacTuiReadySummary {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  $actionLabel = Get-WacTuiActionLabel -Config $Config -Language $Language
  if (Test-WacTuiUninstallAction -Config $Config) {
    $dataLine = if ($Config.Action -eq "UninstallFull") {
      Add-WacTuiUiDanger -Text (Get-WacTuiUiText -Key "SummaryUninstallPurgeData" -Language $Language)
    } else {
      Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "SummaryUninstallKeepData" -Language $Language)
    }
    return ,([string[]]@(
      ("{0}{1}" -f (Get-WacTuiIcon -Name "Mode"), (Format-WacTuiUiText -Key "SummaryMode" -Language $Language -ArgumentList @($actionLabel))),
      (Get-WacTuiUiText -Key "SummaryUninstallTarget" -Language $Language),
      $dataLine,
      (Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "SummaryUninstallServices" -Language $Language)),
      (Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "SummaryUninstallNetwork" -Language $Language))
    ))
  }

  $certificateMode = if ($Config.CertificateThumbprint) {
    Get-WacTuiUiText -Key "CertExisting" -Language $Language
  } else {
    Get-WacTuiUiText -Key "CertGenerated" -Language $Language
  }

  return ,([string[]]@(
    ("{0}{1}" -f (Get-WacTuiIcon -Name "Mode"), (Format-WacTuiUiText -Key "SummaryMode" -Language $Language -ArgumentList @($actionLabel))),
    ("{0}{1}" -f (Get-WacTuiIcon -Name "Ready"), (Format-WacTuiUiText -Key "SummaryOpen" -Language $Language -ArgumentList @($Config.Port))),
    (Format-WacTuiUiText -Key "SummaryCertificate" -Language $Language -ArgumentList @($certificateMode)),
    (Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "SummaryServices" -Language $Language)),
    (Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "SummaryNetwork" -Language $Language))
  ))
}

function New-WacTuiDetailedPlan {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  if (Test-WacTuiUninstallAction -Config $Config) {
    if ($Language -eq "Ru") {
      $plan = @(
        "Службы: остановить и удалить WindowsAdminCenter и службу управления учетными записями",
        "HTTP.sys: удалить привязку TLS-сертификата и резервирование URL для выбранного порта",
        "Брандмауэр: удалить правила Windows Admin Center",
        "Файлы: удалить каталог установки $($Config.InstallDir)",
        "Маркер: удалить файл параметров этого установщика"
      )
      if ($Config.Action -eq "UninstallFull") {
        $plan += "Данные: удалить каталог данных $($Config.DataDir)"
      } else {
        $plan += "Данные: оставить каталог данных $($Config.DataDir)"
      }
      return ,([string[]]$plan)
    }

    $plan = @(
      "Services: stop and remove WindowsAdminCenter and account management services",
      "HTTP.SYS: remove SSL certificate binding and URL reservation for the selected port",
      "Firewall: remove Windows Admin Center rules",
      "Files: remove install directory $($Config.InstallDir)",
      "Marker: remove this setup marker file"
    )
    if ($Config.Action -eq "UninstallFull") {
      $plan += "Data: remove data directory $($Config.DataDir)"
    } else {
      $plan += "Data: keep data directory $($Config.DataDir)"
    }
    return ,([string[]]$plan)
  }

  if ($Language -eq "Ru") {
    return ,([string[]]@(
      "Каталог установки: $($Config.InstallDir)",
      "Каталог данных: $($Config.DataDir)",
      "HTTPS-порт: $($Config.Port)",
      "Диапазон служебных портов: $($Config.ServicePortStart)-$($Config.ServicePortEnd)",
      "Права доступа: выдать службам и администраторам доступ к каталогам установки и данных",
      "HTTP.sys: зарегистрировать TLS-сертификат и резервирование URL",
      "Брандмауэр: применить выбранный сетевой доступ для Windows Admin Center",
      "WinRM: включить PowerShell Remoting, TrustedHosts и HTTPS согласно выбранным параметрам",
      "Диагностика: записать выбранный режим диагностических данных WAC",
      "База данных: выполнить efbundle.exe",
      "Службы: зарегистрировать и запустить службы WindowsAdminCenter"
    ))
  }

  return ,([string[]]@(
    "InstallDir: $($Config.InstallDir)",
    "DataDir: $($Config.DataDir)",
    "Port: $($Config.Port)",
    "ServicePortRange: $($Config.ServicePortStart)-$($Config.ServicePortEnd)",
    "ACL: grant service and administrators access to install/data directories",
    "HTTP.SYS: register SSL certificate and URL ACL",
    "Firewall: apply the selected Windows Admin Center network access",
    "WinRM: apply PowerShell Remoting, TrustedHosts, and HTTPS according to selected options",
    "Diagnostics: write the selected WAC diagnostic data mode",
    "Database: run efbundle.exe",
    "Services: register and start WindowsAdminCenter services"
  ))
}

function New-WacTuiDetailsLines {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En",
    [int]$SelectedIndex = 0
  )

  $lines = New-Object System.Collections.ArrayList
  $detailsLead = if ($Language -eq "Ru") { "План действий" } else { "Action plan" }
  [void]$lines.Add((Add-WacTuiUiAccent -Text ("{0}{1}" -f (Get-WacTuiIcon -Name "Details"), $detailsLead)))
  foreach ($line in (New-WacTuiDetailedPlan -Config $Config -Language $Language)) {
    [void]$lines.Add($line)
  }
  [void]$lines.Add("")
  [void]$lines.Add((Format-WacTuiButtonRow -Buttons @(
    [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Back" -Language $Language); Selected = ($SelectedIndex -eq 0) }
  )))
  [void]$lines.Add((Get-WacTuiUiText -Key "NavigationPrompt" -Language $Language))
  return [string[]]$lines.ToArray()
}

function Read-WacTuiDetailsAction {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  while ($true) {
    Show-WacTuiFrame -Title (Get-WacTuiDetailsTitle -Config $Config -Language $Language) -Lines (New-WacTuiDetailsLines -Config $Config -Language $Language -SelectedIndex 0)
    $inputEvent = Read-WacTuiInput
    if ($inputEvent.Kind -eq "Resize") { continue }
    $key = $inputEvent.Key
    $char = [char]::ToUpperInvariant($key.Character)
    if ($char -eq "B" -or $key.VirtualKeyCode -eq 13) { return "Back" }
  }
}

function Format-WacTuiConfigValue {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [Parameter(Mandatory = $true)][string]$Key,
    [string]$Language = "En"
  )

  switch ($Key) {
    "TlsMode" {
      if ($Config.CertificateThumbprint) {
        return Get-WacTuiUiText -Key "ValueInstalledCert" -Language $Language
      }
      return Get-WacTuiUiText -Key "ValueSelfSigned" -Language $Language
    }
    "PsRemoting" {
      if ($Config.SkipPsRemoting) { return Get-WacTuiUiText -Key "Disabled" -Language $Language }
      return Get-WacTuiUiText -Key "Enabled" -Language $Language
    }
    "TrustSelfSignedCertificate" {
      if ($Config.TrustSelfSignedCertificate) { return "[x]" }
      return "[ ]"
    }
    "KeepExistingData" {
      if ($Config.KeepExistingData) { return "[x]" }
      return "[ ]"
    }
    "ExperimentalArm64" {
      if ($Config.SkipArchitectureCheck) { return "[x]" }
      return "[ ]"
    }
    "DiagnosticDataMode" {
      if ($Language -ne "Ru") { return [string]$Config.DiagnosticDataMode }
      switch ($Config.DiagnosticDataMode) {
        "Required" { return "обязательные" }
        "Optional" { return "необязательные" }
        default { return [string]$Config.DiagnosticDataMode }
      }
    }
    "NetworkAccess" {
      if ($Language -ne "Ru") {
        switch ($Config.NetworkAccess) {
          "LocalOnly" { return "local only" }
          "LocalSubnet" { return "local subnet" }
          "Any" { return "any address" }
          default { return [string]$Config.NetworkAccess }
        }
      }
      switch ($Config.NetworkAccess) {
        "LocalOnly" { return "только локально" }
        "LocalSubnet" { return "локальная подсеть" }
        "Any" { return "любой адрес" }
        default { return [string]$Config.NetworkAccess }
      }
    }
    "TrustedHosts" {
      if ($Language -ne "Ru") {
        switch ($Config.TrustedHostsMode) {
          "ConfigureTrustedHosts" { return "manage automatically (*)" }
          "NotConfigureTrustedHosts" { return "do not change" }
          default { return [string]$Config.TrustedHostsMode }
        }
      }
      switch ($Config.TrustedHostsMode) {
        "ConfigureTrustedHosts" { return "управлять автоматически (*)" }
        "NotConfigureTrustedHosts" { return "не изменять" }
        default { return [string]$Config.TrustedHostsMode }
      }
    }
    "WinRmHttps" {
      if ($Config.WinRmHttpsMode -eq "Enable") { return Get-WacTuiUiText -Key "Enabled" -Language $Language }
      return Get-WacTuiUiText -Key "Disabled" -Language $Language
    }
    "SoftwareUpdateMode" {
      if ($Language -ne "Ru") { return [string]$Config.SoftwareUpdateMode }
      switch ($Config.SoftwareUpdateMode) {
        "Automatic" { return "автоматически" }
        "Manual" { return "вручную" }
        "Notification" { return "только уведомлять" }
        default { return [string]$Config.SoftwareUpdateMode }
      }
    }
    default {
      return [string]$Config.$Key
    }
  }
}

function Move-WacTuiSelection {
  param(
    [int]$SelectedIndex = 0,
    [int]$Delta = 0,
    [int]$ItemCount = 1
  )

  if ($ItemCount -lt 1) { return 0 }
  $next = ($SelectedIndex + $Delta) % $ItemCount
  if ($next -lt 0) { $next += $ItemCount }
  return $next
}

function Format-WacTuiSelectableLine {
  param(
    [string]$Text = "",
    [bool]$Selected = $false
  )

  $noWrap = Test-WacTuiNoWrapLine -Text $Text
  $lineText = $Text
  if ($noWrap) {
    $lineText = Remove-WacTuiNoWrapLinePrefix -Text $lineText
  }

  $line = "  $lineText"
  if ($noWrap) {
    $line = New-WacTuiNoWrapLine -Text $line
  }

  if ($Selected) { return New-WacTuiSelectedLine -Text $line }
  return $line
}

function Format-WacTuiOptionLine {
  param(
    [string]$Number = "",
    [string]$Label = "",
    [string]$Value = "",
    [int]$LabelWidth = 1
  )

  $labelText = $Label
  if ($null -eq $labelText) { $labelText = "" }
  $labelText = $labelText.PadRight($LabelWidth)
  return (New-WacTuiNoWrapLine -Text ("{0,2}. {1} : {2}" -f $Number, $labelText, $Value))
}

function Get-WacTuiCurrentPlatformRisk {
  try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    return Get-WacTuiPlatformRisk -OSArchitecture $os.OSArchitecture -ProcessorArchitecture $env:PROCESSOR_ARCHITECTURE -ProductType ([int]$os.ProductType)
  } catch {
    return Get-WacTuiPlatformRisk -OSArchitecture "" -ProcessorArchitecture $env:PROCESSOR_ARCHITECTURE -ProductType 1
  }
}

function Get-WacTuiOptionRiskLevel {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [Parameter(Mandatory = $true)][string]$Key
  )

  switch ($Key) {
    "TrustSelfSignedCertificate" {
      if ($Config.TrustSelfSignedCertificate) { return "WARN" }
      return "OK"
    }
    "PsRemoting" {
      if (-not $Config.SkipPsRemoting) { return "WARN" }
      return "OK"
    }
    "ExperimentalArm64" {
      if ($Config.SkipArchitectureCheck -or $Config.ExperimentalArm64) { return "DANGER" }
      return "OK"
    }
    "NetworkAccess" {
      if ($Config.NetworkAccess -eq "Any") { return "WARN" }
      if ($Config.NetworkAccess -eq "LocalSubnet") { return "WARN" }
      return "OK"
    }
    "TrustedHosts" {
      if ($Config.TrustedHostsMode -eq "ConfigureTrustedHosts") { return "WARN" }
      return "OK"
    }
    "WinRmHttps" {
      if ($Config.WinRmHttpsMode -eq "Enable") { return "WARN" }
      return "OK"
    }
    default {
      return "OK"
    }
  }
}

function Add-WacTuiOptionRiskStyle {
  param(
    [string]$Line = "",
    [ValidateSet("OK", "WARN", "DANGER")]
    [string]$Level = "OK"
  )

  $noWrap = Test-WacTuiNoWrapLine -Text $Line
  if ($noWrap) {
    $Line = Remove-WacTuiNoWrapLinePrefix -Text $Line
  }

  $styled = $Line
  switch ($Level) {
    "WARN" { $styled = Add-WacTuiUiWarning -Text $Line }
    "DANGER" { $styled = Add-WacTuiUiDanger -Text $Line }
    default { $styled = $Line }
  }

  if ($noWrap) {
    return New-WacTuiNoWrapLine -Text $styled
  }
  return $styled
}

function New-WacTuiCustomLines {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En",
    [int]$SelectedIndex = 0
  )

  $items = @(
    @("1", "OptInstallDir", "InstallDir"),
    @("2", "OptDataDir", "DataDir"),
    @("3", "OptPort", "Port"),
    @("4", "OptServicePortStart", "ServicePortStart"),
    @("5", "OptServicePortEnd", "ServicePortEnd"),
    @("6", "OptEndpointFqdn", "EndpointFqdn"),
    @("7", "OptServiceFqdn", "ServiceFqdn"),
    @("8", "OptTlsMode", "TlsMode"),
    @("9", "OptCertThumbprint", "CertificateThumbprint"),
    @("10", "OptCertSubject", "CertificateSubject"),
    @("11", "OptUpdateMode", "SoftwareUpdateMode"),
    @("12", "OptTrustSelfSigned", "TrustSelfSignedCertificate"),
    @("13", "OptPsRemoting", "PsRemoting"),
    @("14", "OptKeepData", "KeepExistingData"),
    @("15", "OptDiagnostic", "DiagnosticDataMode"),
    @("16", "OptNetworkAccess", "NetworkAccess"),
    @("17", "OptTrustedHosts", "TrustedHosts"),
    @("18", "OptWinRmHttps", "WinRmHttps")
  )

  $lines = New-Object System.Collections.ArrayList
  $customLead = if ($Language -eq "Ru") { "Параметры установки" } else { "Setup options" }
  [void]$lines.Add((Add-WacTuiUiAccent -Text ("{0}{1}" -f (Get-WacTuiIcon -Name "Custom"), $customLead)))
  $labelWidth = 1
  foreach ($item in $items) {
    $labelCandidate = Get-WacTuiUiText -Key $item[1] -Language $Language
    if ($labelCandidate.Length -gt $labelWidth) { $labelWidth = $labelCandidate.Length }
  }

  $index = 0
  foreach ($item in $items) {
    $label = Get-WacTuiUiText -Key $item[1] -Language $Language
    $value = Format-WacTuiConfigValue -Config $Config -Key $item[2] -Language $Language
    $line = Format-WacTuiOptionLine -Number $item[0] -Label $label -Value $value -LabelWidth $labelWidth
    $riskLevel = Get-WacTuiOptionRiskLevel -Config $Config -Key $item[2]
    $line = Add-WacTuiOptionRiskStyle -Line $line -Level $riskLevel
    [void]$lines.Add((Format-WacTuiSelectableLine -Text $line -Selected:($SelectedIndex -eq $index)))
    $index++
  }
  [void]$lines.Add((Format-WacTuiButtonRow -Buttons @(
    [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Back" -Language $Language); Selected = ($SelectedIndex -eq 18) },
    [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Next" -Language $Language); Selected = ($SelectedIndex -eq 19) },
    [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Cancel" -Language $Language); Selected = ($SelectedIndex -eq 20) }
  )))
  [void]$lines.Add((Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "CustomPrompt" -Language $Language)))
  return [string[]]$lines.ToArray()
}

function Read-WacTuiOptionalValue {
  param(
    [Parameter(Mandatory = $true)][string]$CurrentValue,
    [string]$Language = "En"
  )

  $prompt = "{0} [{1}]" -f (Get-WacTuiUiText -Key "KeepCurrentPrompt" -Language $Language), $CurrentValue
  $value = Read-Host $prompt
  if ([string]::IsNullOrWhiteSpace($value)) { return $CurrentValue }
  return $value
}

function Read-WacTuiOptionalInt {
  param(
    [int]$CurrentValue,
    [string]$Language = "En"
  )

  $raw = Read-WacTuiOptionalValue -CurrentValue ([string]$CurrentValue) -Language $Language
  $parsed = 0
  if (-not [int]::TryParse($raw, [ref]$parsed)) {
    throw (Get-WacTuiUiText -Key "InvalidValue" -Language $Language)
  }
  return $parsed
}

function Edit-WacTuiCustomConfig {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  $selectedIndex = 0
  $itemCount = 21
  while ($true) {
    Show-WacTuiFrame -Title (Get-WacTuiUiText -Key "CustomTitle" -Language $Language) -Lines (New-WacTuiCustomLines -Config $Config -Language $Language -SelectedIndex $selectedIndex)
    $inputEvent = Read-WacTuiInput
    if ($inputEvent.Kind -eq "Resize") { continue }
    $key = $inputEvent.Key
    if ($key.VirtualKeyCode -eq 38) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta -1 -ItemCount $itemCount
      continue
    }
    if ($key.VirtualKeyCode -eq 40) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta 1 -ItemCount $itemCount
      continue
    }
    if ($key.VirtualKeyCode -eq 37) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta -1 -ItemCount $itemCount
      continue
    }
    if ($key.VirtualKeyCode -eq 39) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta 1 -ItemCount $itemCount
      continue
    }
    $choice = ""
    if ($key.Character -eq " ") {
      if ($selectedIndex -in @(7, 10, 11, 12, 13, 14, 15, 16, 17)) {
        $choice = [string]($selectedIndex + 1)
      } else {
        continue
      }
    } elseif ($key.VirtualKeyCode -eq 13) {
      if ($selectedIndex -eq 18) { return "Back" }
      if ($selectedIndex -eq 19) { return "Next" }
      if ($selectedIndex -eq 20) { return "Cancel" }
      $choice = [string]($selectedIndex + 1)
    } else {
      $choice = ([string]$key.Character).ToUpperInvariant()
    }

    try {
      switch ($choice) {
        "1" { $Config.InstallDir = Read-WacTuiOptionalValue -CurrentValue $Config.InstallDir -Language $Language }
        "2" { $Config.DataDir = Read-WacTuiOptionalValue -CurrentValue $Config.DataDir -Language $Language }
        "3" { $Config.Port = Read-WacTuiOptionalInt -CurrentValue $Config.Port -Language $Language }
        "4" { $Config.ServicePortStart = Read-WacTuiOptionalInt -CurrentValue $Config.ServicePortStart -Language $Language }
        "5" { $Config.ServicePortEnd = Read-WacTuiOptionalInt -CurrentValue $Config.ServicePortEnd -Language $Language }
        "6" { $Config.EndpointFqdn = Read-WacTuiOptionalValue -CurrentValue $Config.EndpointFqdn -Language $Language }
        "7" { $Config.ServiceFqdn = Read-WacTuiOptionalValue -CurrentValue $Config.ServiceFqdn -Language $Language }
        "8" {
          if ($Config.CertificateThumbprint) {
            $Config.CertificateThumbprint = ""
          } else {
            $Config.CertificateThumbprint = Read-WacTuiOptionalValue -CurrentValue $Config.CertificateThumbprint -Language $Language
          }
        }
        "9" { $Config.CertificateThumbprint = Read-WacTuiOptionalValue -CurrentValue $Config.CertificateThumbprint -Language $Language }
        "10" { $Config.CertificateSubject = Read-WacTuiOptionalValue -CurrentValue $Config.CertificateSubject -Language $Language }
        "11" {
          if ($Config.SoftwareUpdateMode -eq "Automatic") { $Config.SoftwareUpdateMode = "Manual" }
          elseif ($Config.SoftwareUpdateMode -eq "Manual") { $Config.SoftwareUpdateMode = "Notification" }
          else { $Config.SoftwareUpdateMode = "Automatic" }
        }
        "12" { $Config.TrustSelfSignedCertificate = -not $Config.TrustSelfSignedCertificate }
        "13" { $Config.SkipPsRemoting = -not $Config.SkipPsRemoting }
        "14" { $Config.KeepExistingData = -not $Config.KeepExistingData }
        "15" {
          if ($Config.DiagnosticDataMode -eq "Required") { $Config.DiagnosticDataMode = "Optional" }
          else { $Config.DiagnosticDataMode = "Required" }
        }
        "16" {
          if ($Config.NetworkAccess -eq "LocalOnly") { $Config.NetworkAccess = "LocalSubnet" }
          elseif ($Config.NetworkAccess -eq "LocalSubnet") { $Config.NetworkAccess = "Any" }
          else { $Config.NetworkAccess = "LocalOnly" }
        }
        "17" {
          if ($Config.TrustedHostsMode -eq "ConfigureTrustedHosts") { $Config.TrustedHostsMode = "NotConfigureTrustedHosts" }
          else { $Config.TrustedHostsMode = "ConfigureTrustedHosts" }
        }
        "18" {
          if ($Config.WinRmHttpsMode -eq "Enable") { $Config.WinRmHttpsMode = "Disable" }
          else { $Config.WinRmHttpsMode = "Enable" }
        }
        "B" { return "Back" }
        "R" { return "Next" }
        "N" { return "Next" }
        "C" { return "Cancel" }
      }
    } catch {
      Show-WacTuiFrame -Title (Get-WacTuiUiText -Key "CustomTitle" -Language $Language) -Lines @($_.Exception.Message)
      Start-Sleep -Milliseconds 1100
    }
  }
}

function Assert-WacTuiCanApply {
  param([Parameter(Mandatory = $true)]$Config)

  $messageLanguage = Get-WacTuiLanguage -Language $Config.Language
  if (-not $Config.AcceptedTerms) {
    throw (Get-WacTuiUiText -Key "AssertLicense" -Language $messageLanguage)
  }

  $portPlan = Test-WacPortPlan -Port $Config.Port -ServicePortStart $Config.ServicePortStart -ServicePortEnd $Config.ServicePortEnd
  if ($portPlan.Level -eq "BLOCKED") {
    throw $portPlan.Message
  }
}

function New-WacTuiWelcomeLines {
  param(
    [string]$Language = "En",
    [int]$SelectedIndex = 0
  )

  return ,([string[]]@(
    (Add-WacTuiUiAccent -Text ("{0}{1}" -f (Get-WacTuiIcon -Name "Source"), (Get-WacTuiUiText -Key "WelcomeSource" -Language $Language))),
    ("{0}{1}" -f (Get-WacTuiIcon -Name "Mode"), (Get-WacTuiUiText -Key "WelcomeMode" -Language $Language)),
    (Add-WacTuiUiDim -Text ("{0}{1}" -f (Get-WacTuiIcon -Name "Invoke"), (Get-WacTuiUiText -Key "WelcomeInvoke" -Language $Language))),
    "",
    (Format-WacTuiButtonRow -Buttons @(
      [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Next" -Language $Language); Selected = ($SelectedIndex -eq 0) },
      [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Cancel" -Language $Language); Selected = ($SelectedIndex -eq 1) }
    )),
    (Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "NavigationPrompt" -Language $Language))
  ))
}

function Read-WacTuiWelcomeAction {
  param(
    [string]$Title,
    [string]$Language = "En"
  )

  $selectedIndex = 0
  while ($true) {
    Show-WacTuiFrame -Title $Title -Lines (New-WacTuiWelcomeLines -Language $Language -SelectedIndex $selectedIndex)
    $inputEvent = Read-WacTuiInput
    if ($inputEvent.Kind -eq "Resize") { continue }
    $key = $inputEvent.Key
    if ($key.VirtualKeyCode -eq 37 -or $key.VirtualKeyCode -eq 38) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta -1 -ItemCount 2
      continue
    }
    if ($key.VirtualKeyCode -eq 39 -or $key.VirtualKeyCode -eq 40) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta 1 -ItemCount 2
      continue
    }
    $char = [char]::ToUpperInvariant($key.Character)
    if ($char -eq "N") { return "Next" }
    if ($char -eq "C") { return "Cancel" }
    if ($key.VirtualKeyCode -eq 13) {
      if ($selectedIndex -eq 0) { return "Next" }
      return "Cancel"
    }
  }
}

function New-WacTuiActionLines {
  param(
    [string]$Language = "En",
    [int]$SelectedIndex = 0,
    $PlatformRisk = $null,
    $InstallState = $null
  )

  $modeLead = if ($Language -eq "Ru") { "Выберите действие" } else { "Choose action" }
  if ($null -eq $PlatformRisk) {
    $PlatformRisk = Get-WacTuiCurrentPlatformRisk
  }
  if ($null -eq $InstallState) {
    $InstallState = [pscustomobject]@{ IsInstalledByThisSetup = $false; Config = (New-WacTuiConfig) }
  }

  $lines = New-Object System.Collections.ArrayList
  [void]$lines.Add((Add-WacTuiUiAccent -Text ("{0}{1}" -f (Get-WacTuiIcon -Name "Mode"), $modeLead)))
  $actionItems = New-Object System.Collections.ArrayList
  if ($InstallState.IsInstalledByThisSetup) {
    [void]$actionItems.Add([pscustomobject]@{ Action = "Uninstall"; Key = "ActionUninstall"; Risk = "WARN" })
    [void]$actionItems.Add([pscustomobject]@{ Action = "UninstallFull"; Key = "ActionUninstallFull"; Risk = "DANGER" })
    [void]$actionItems.Add([pscustomobject]@{ Action = "Express"; Key = "ActionRepair"; Risk = "OK" })
    [void]$actionItems.Add([pscustomobject]@{ Action = "Custom"; Key = "ActionChange"; Risk = "OK" })
  } else {
    [void]$actionItems.Add([pscustomobject]@{ Action = "Express"; Key = "ModeExpress"; Risk = "OK" })
    [void]$actionItems.Add([pscustomobject]@{ Action = "Custom"; Key = "ModeCustom"; Risk = "OK" })
  }
  $index = 0
  foreach ($item in $actionItems) {
    $selected = ($SelectedIndex -eq $index)
    $line = Format-WacTuiSelectableLine -Text ("{0}. {1}" -f ($index + 1), (Get-WacTuiUiText -Key $item.Key -Language $Language))
    if ($item.Risk -eq "WARN") { $line = Add-WacTuiUiWarning -Text $line }
    if ($item.Risk -eq "DANGER") { $line = Add-WacTuiUiDanger -Text $line }
    if ($selected) { $line = New-WacTuiSelectedLine -Text $line }
    [void]$lines.Add($line)
    $index++
  }
  [void]$lines.Add((Add-WacTuiUiWarning -Text (Get-WacTuiUiText -Key "ModeRisk" -Language $Language)))
  if ($PlatformRisk.Code -eq "Arm64Experimental") {
    [void]$lines.Add((Add-WacTuiUiDanger -Text (Get-WacTuiUiText -Key "ModeArm64Warning" -Language $Language)))
  }
  [void]$lines.Add("")
  [void]$lines.Add((Format-WacTuiButtonRow -Buttons @(
      [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Back" -Language $Language); Selected = ($SelectedIndex -eq $actionItems.Count) },
      [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Cancel" -Language $Language); Selected = ($SelectedIndex -eq ($actionItems.Count + 1)) }
  )))
  [void]$lines.Add((Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "NavigationPrompt" -Language $Language)))
  return [string[]]$lines.ToArray()
}

function New-WacTuiModeLines {
  param(
    [string]$Language = "En",
    [int]$SelectedIndex = 0,
    $PlatformRisk = $null,
    $InstallState = $null
  )
  return New-WacTuiActionLines -Language $Language -SelectedIndex $SelectedIndex -PlatformRisk $PlatformRisk -InstallState $InstallState
}

function Read-WacTuiModeChoice {
  param(
    [string]$Language = "En",
    $InstallState = $null
  )

  $selectedIndex = 0
  $modeIndex = 0
  while ($true) {
    if ($null -eq $InstallState) {
      $InstallState = [pscustomobject]@{ IsInstalledByThisSetup = $false; Config = (New-WacTuiConfig) }
    }
    $actionCount = if ($InstallState.IsInstalledByThisSetup) { 4 } else { 2 }
    Show-WacTuiFrame -Title (Get-WacTuiUiText -Key "ModeTitle" -Language $Language) -Lines (New-WacTuiModeLines -Language $Language -SelectedIndex $selectedIndex -InstallState $InstallState)
    $inputEvent = Read-WacTuiInput
    if ($inputEvent.Kind -eq "Resize") { continue }
    $key = $inputEvent.Key
    if ($key.VirtualKeyCode -eq 38 -or $key.VirtualKeyCode -eq 37) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta -1 -ItemCount ($actionCount + 2)
      if ($selectedIndex -lt $actionCount) { $modeIndex = $selectedIndex }
      continue
    }
    if ($key.VirtualKeyCode -eq 40 -or $key.VirtualKeyCode -eq 39) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta 1 -ItemCount ($actionCount + 2)
      if ($selectedIndex -lt $actionCount) { $modeIndex = $selectedIndex }
      continue
    }
    if ($key.Character -match '^[1-4]$') {
      $requested = ([int]::Parse([string]$key.Character) - 1)
      if ($requested -lt $actionCount) { $modeIndex = $requested; $selectedIndex = $requested }
      continue
    }
    if ([char]::ToUpperInvariant($key.Character) -eq "B") { return "Back" }
    if ([char]::ToUpperInvariant($key.Character) -eq "C") { return "Cancel" }
    if ($key.VirtualKeyCode -eq 13) {
      if ($selectedIndex -lt $actionCount) { return (Resolve-WacTuiActionChoice -InstallState $InstallState -Index $selectedIndex) }
      if ($selectedIndex -eq $actionCount) { return "Back" }
      return "Cancel"
    }
  }
}

function Resolve-WacTuiActionChoice {
  param(
    $InstallState,
    [int]$Index = 0
  )
  if ($InstallState.IsInstalledByThisSetup) {
    switch ($Index) {
      0 { return "Uninstall" }
      1 { return "UninstallFull" }
      2 { return "Express" }
      default { return "Custom" }
    }
  }
  if ($Index -eq 1) { return "Custom" }
  return "Express"
}

function New-WacTuiReadyLines {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En",
    [int]$SelectedIndex = 1
  )

  $lines = New-Object System.Collections.ArrayList
  foreach ($line in (New-WacTuiReadySummary -Config $Config -Language $Language)) {
    [void]$lines.Add($line)
  }
  [void]$lines.Add("")
  [void]$lines.Add((Format-WacTuiButtonRow -Buttons @(
    [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Back" -Language $Language); Selected = ($SelectedIndex -eq 0) },
    [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Details" -Language $Language); Selected = ($SelectedIndex -eq 1) },
    [pscustomobject]@{ Text = (Get-WacTuiPrimaryActionText -Config $Config -Language $Language); Selected = ($SelectedIndex -eq 2) },
    [pscustomobject]@{ Text = (Get-WacTuiUiText -Key "Cancel" -Language $Language); Selected = ($SelectedIndex -eq 3) }
  )))
  [void]$lines.Add((Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "NavigationPrompt" -Language $Language)))
  return ,([string[]]$lines.ToArray())
}

function Read-WacTuiReadyAction {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [string]$Language = "En"
  )

  $selectedIndex = 2
  while ($true) {
    Show-WacTuiFrame -Title (Get-WacTuiReadyTitle -Config $Config -Language $Language) -Lines (New-WacTuiReadyLines -Config $Config -Language $Language -SelectedIndex $selectedIndex)
    $inputEvent = Read-WacTuiInput
    if ($inputEvent.Kind -eq "Resize") { continue }
    $key = $inputEvent.Key
    if ($key.VirtualKeyCode -eq 37 -or $key.VirtualKeyCode -eq 38) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta -1 -ItemCount 4
      continue
    }
    if ($key.VirtualKeyCode -eq 39 -or $key.VirtualKeyCode -eq 40) {
      $selectedIndex = Move-WacTuiSelection -SelectedIndex $selectedIndex -Delta 1 -ItemCount 4
      continue
    }
    $char = [char]::ToUpperInvariant($key.Character)
    if ($char -eq "B") { return "Back" }
    if ($char -eq "D") { return "Details" }
    if ($char -eq "I") { return "Install" }
    if ($char -eq "C") { return "Cancel" }
    if ($key.VirtualKeyCode -eq 13) {
      if ($selectedIndex -eq 0) { return "Back" }
      if ($selectedIndex -eq 1) { return "Details" }
      if ($selectedIndex -eq 2) { return "Install" }
      return "Cancel"
    }
  }
}

function Test-WacTuiAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($id)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WacTuiWindowsPowerShellPath {
  $candidate = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
  if (Test-Path -LiteralPath $candidate) { return $candidate }

  $command = Get-Command "powershell.exe" -ErrorAction SilentlyContinue
  if ($command -and $command.Source) { return $command.Source }

  return "powershell.exe"
}

function Get-WacTuiSudoPath {
  $command = Get-Command "sudo.exe" -ErrorAction SilentlyContinue
  if ($command -and $command.Source) { return $command.Source }
  return ""
}

function Join-WacTuiCommandArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + ($Value -replace '\\(?=")', '$0' -replace '"', '\"') + '"'
}

function Join-WacTuiCommandArguments {
  param([string[]]$ArgumentList = @())
  return (($ArgumentList | ForEach-Object { Join-WacTuiCommandArgument -Value $_ }) -join " ")
}

function New-WacTuiInstallLogPath {
  $diagDir = "C:\WAC-Diag"
  New-Item -ItemType Directory -Path $diagDir -Force | Out-Null
  return (Join-Path $diagDir ("wac-setup-install-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
}

function New-WacTuiApplyProcessPlan {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [string]$SetupEnginePath = "",
    [Parameter(Mandatory = $true)][string]$LogPath,
    [string]$SudoPath = "",
    [bool]$IsAdmin = $false
  )

  Assert-WacTuiCanApply -Config $Config

  $engineArguments = New-Object System.Collections.ArrayList
  [void]$engineArguments.Add("-NoLogo")
  [void]$engineArguments.Add("-NoProfile")
  [void]$engineArguments.Add("-ExecutionPolicy")
  [void]$engineArguments.Add("Bypass")
  [void]$engineArguments.Add("-File")
  [void]$engineArguments.Add($SetupEnginePath)

  foreach ($arg in (ConvertTo-WacSetupEngineArguments -Config $Config)) {
    [void]$engineArguments.Add($arg)
  }
  [void]$engineArguments.Add("-LogPath")
  [void]$engineArguments.Add($LogPath)

  $needsElevation = (-not $IsAdmin)
  $usesSudo = ($needsElevation -and -not [string]::IsNullOrWhiteSpace($SudoPath))
  $usesRunAs = ($needsElevation -and [string]::IsNullOrWhiteSpace($SudoPath))

  $argumentList = New-Object System.Collections.ArrayList
  if ($usesSudo) {
    [void]$argumentList.Add($PowerShellPath)
    foreach ($arg in ([string[]]$engineArguments.ToArray())) {
      [void]$argumentList.Add($arg)
    }
  } else {
    foreach ($arg in ([string[]]$engineArguments.ToArray())) {
      [void]$argumentList.Add($arg)
    }
  }

  return [pscustomobject]@{
    FilePath = if ($usesSudo) { $SudoPath } else { $PowerShellPath }
    ArgumentList = [string[]]$argumentList.ToArray()
    EngineFilePath = $PowerShellPath
    EngineArgumentList = [string[]]$engineArguments.ToArray()
    LogPath = $LogPath
    UsesSudo = $usesSudo
    UsesRunAs = $usesRunAs
  }
}

function Convert-WacTuiInstallLogLine {
  param(
    [string]$Line = "",
    [string]$Language = "En"
  )

  if ([string]::IsNullOrWhiteSpace($Line)) { return "" }
  if ($Line -match "\]\s+\[(?:INFO|STEP|WARN|ERROR|USER)\]\s+(.+)$") {
    $text = $matches[1].Trim()
  } else {
    $text = $Line.Trim()
  }
  if ($text -match "^(RUN|EXIT)\b") { return "" }
  if ($text -match "^(processed file|Successfully processed|Failed processing)\b") { return "" }
  if ($Language -eq "Ru") {
    switch -Regex ($text) {
      "^InstallerPath=(.+)$" { return "Установщик: $($matches[1])" }
      "^ExtractOut=(.+)$" { return "Каталог распаковки: $($matches[1])" }
      "^InstallDir=(.+)$" { return "Каталог установки: $($matches[1])" }
      "^DataDir=(.+)$" { return "Каталог данных: $($matches[1])" }
      "^Port=(\d+) ServicePortRange=([0-9-]+) EndpointFqdn=(.+) ServiceFqdn=(.+)$" { return "Порты: шлюз $($matches[1]), служебные $($matches[2]); имена: $($matches[3]) / $($matches[4])" }
      "^Language=Ru$" { return "Язык интерфейса: русский" }
      "^Installer signature status: Valid$" { return "Подпись установщика проверена" }
      "^Installer signature signer: .+$" { return "" }
      "^Downloading innoextract from (.+)$" { return "Загрузка innoextract: $($matches[1])" }
      "^Downloaded and expanded innoextract official zip: (.+)$" { return "innoextract готов: $($matches[1])" }
      "^Extracting installer payload with (.+)$" { return "Извлечение файлов WAC: $($matches[1])" }
      "^Stopping/removing previous WAC services and bindings$" { return "Остановка прежних служб и привязок WAC" }
      "^Stopping service (.+)$" { return "Остановка службы: $($matches[1])" }
      "^Copying files$" { return "Копирование файлов" }
      "^Granting ACLs on (.+)$" { return "Настройка прав доступа: $($matches[1])" }
      "^Creating self-signed certificate for (.+)$" { return "Создание самоподписанного сертификата для $($matches[1])" }
      "^Reusing self-signed certificate (.+)$" { return "Используется существующий самоподписанный сертификат: $($matches[1])" }
      "^Granting NETWORK SERVICE access to certificate private key$" { return "Выдача NETWORK SERVICE доступа к закрытому ключу сертификата" }
      "^Configuring appsettings\.json$" { return "Запись appsettings.json" }
      "^Registering HTTP\.SYS for port (.+)$" { return "Регистрация HTTP.sys для порта $($matches[1])" }
      "^Registering firewall rules$" { return "Настройка правил брандмауэра" }
      "^Enabling PowerShell remoting$" { return "Включение PowerShell Remoting" }
      "^Initializing WAC database$" { return "Инициализация базы данных WAC" }
      "^Registering services$" { return "Регистрация служб" }
      "^Starting WindowsAdminCenter service$" { return "Запуск службы WindowsAdminCenter" }
      "^Service status: Running$" { return "Служба запущена" }
      "^TCP port (.+) is listening$" { return "TCP-порт $($matches[1]) слушает подключения" }
      "^Open: (.+)$" { return "Открыть: $($matches[1])" }
      "^Log:\s+(.+)$" { return "Журнал: $($matches[1])" }
      "^Лог:\s+(.+)$" { return "Журнал: $($matches[1])" }
      "^\[SC\] CreateService SUCCESS$" { return "Служба создана" }
      "^\[SC\] ChangeServiceConfig2 SUCCESS$" { return "Описание службы обновлено" }
      "^\[SC\] SetServiceObjectSecurity SUCCESS$" { return "Права службы обновлены" }
      "^SSL Certificate successfully added$" { return "TLS-сертификат зарегистрирован" }
      "^SSL Certificate successfully deleted$" { return "Старая TLS-привязка удалена" }
      "^URL reservation successfully added$" { return "Резервирование URL добавлено" }
      "^URL reservation successfully deleted$" { return "Старое резервирование URL удалено" }
    }
  }
  return $text
}

function Get-WacTuiInstallLogLines {
  param([string]$LogPath = "")

  if ([string]::IsNullOrWhiteSpace($LogPath) -or -not (Test-Path -LiteralPath $LogPath)) {
    return ,([string[]]@())
  }

  try {
    $stream = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
      $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
      try {
        $text = $reader.ReadToEnd()
      } finally {
        $reader.Dispose()
      }
    } finally {
      $stream.Dispose()
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return ,([string[]]@()) }
    return ,([string[]](($text -split "`r?`n") | Where-Object { $_ -ne "" } | Select-Object -Last 120))
  } catch {
    return ,([string[]]@())
  }
}

function New-WacTuiInstallStatusLines {
  param(
    [Parameter(Mandatory = $true)]$Plan,
    [Parameter(Mandatory = $true)]$Config,
    [int]$ExitCode = -1,
    [bool]$Completed = $false,
    $RenderState = $null
  )

  $language = $Config.Language
  $logLines = Get-WacTuiInstallLogLines -LogPath $Plan.LogPath
  $progress = Get-WacTuiProgressFromLogLines -Lines $logLines
  if ($Completed -and $ExitCode -eq 0) {
    $progress.Percent = 100
  }
  if ($RenderState) {
    if ($progress.Percent -lt $RenderState.LastPercent) {
      $progress.Percent = $RenderState.LastPercent
      $progress.PhaseName = $RenderState.LastPhaseName
    } elseif ($progress.Percent -eq $RenderState.LastPercent -and [string]::IsNullOrWhiteSpace($progress.PhaseName) -and -not [string]::IsNullOrWhiteSpace($RenderState.LastPhaseName)) {
      $progress.PhaseName = $RenderState.LastPhaseName
    }
    if ($progress.Percent -gt $RenderState.LastPercent -or -not [string]::IsNullOrWhiteSpace($progress.PhaseName)) {
      $RenderState.LastPercent = [Math]::Max([int]$RenderState.LastPercent, [int]$progress.Percent)
      if (-not [string]::IsNullOrWhiteSpace($progress.PhaseName)) {
        $RenderState.LastPhaseName = $progress.PhaseName
      }
    }
  }

  $visibleLogLines = New-Object System.Collections.Generic.List[string]
  foreach ($line in $logLines) {
    $display = Convert-WacTuiInstallLogLine -Line $line -Language $language
    if (-not [string]::IsNullOrWhiteSpace($display)) {
      [void]$visibleLogLines.Add($display)
    }
  }

  $tail = @($visibleLogLines | Select-Object -Last 4)
  $phaseLabel = if ([string]::IsNullOrWhiteSpace($progress.PhaseName)) {
    if (Test-WacTuiUninstallAction -Config $Config) {
      Get-WacTuiUiText -Key "StartingUninstall" -Language $language
    } else {
      Get-WacTuiUiText -Key "StartingSetup" -Language $language
    }
  } else {
    Get-WacTuiPhaseLabel -Name $progress.PhaseName -Language $language
  }

  $lines = New-Object System.Collections.Generic.List[string]
  $operationIcon = if (Test-WacTuiUninstallAction -Config $Config) { "Uninstall" } else { "Install" }
  [void]$lines.Add(("{0}{1}" -f (Get-WacTuiIcon -Name $operationIcon), (New-WacTuiProgressBar -Percent $progress.Percent -Width 42 -UseUnicode:(!$Ascii))))
  [void]$lines.Add(("{0}: {1}" -f (Get-WacTuiUiText -Key "StatusLabel" -Language $language), $phaseLabel))
  [void]$lines.Add(("{0}: {1}" -f (Get-WacTuiUiText -Key "LogLabel" -Language $language), $Plan.LogPath))
  if ($Plan.UsesSudo) {
    $sudoKey = if (Test-WacTuiUninstallAction -Config $Config) { "SudoOperationInline" } else { "SudoInline" }
    [void]$lines.Add((Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key $sudoKey -Language $language)))
  } elseif ($Plan.UsesRunAs) {
    [void]$lines.Add((Add-WacTuiUiDim -Text (Get-WacTuiUiText -Key "RunAsInline" -Language $language)))
  }
  [void]$lines.Add("")
  for ($tailIndex = 0; $tailIndex -lt 4; $tailIndex++) {
    if ($tailIndex -lt $tail.Count) {
      [void]$lines.Add($tail[$tailIndex])
    } else {
      [void]$lines.Add("")
    }
  }
  if ($Completed -and $ExitCode -ne 0) {
    [void]$lines.Add("")
    if ($language -eq "Ru") {
      [void]$lines.Add(("Код завершения: {0}" -f $ExitCode))
    } else {
      [void]$lines.Add(("Exit code: {0}" -f $ExitCode))
    }
  }

  return ,([string[]]$lines.ToArray())
}

function Invoke-WacTuiProcessHidden {
  param([Parameter(Mandatory = $true)]$Plan)

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
  $process.StartInfo.FileName = $Plan.FilePath
  $process.StartInfo.Arguments = Join-WacTuiCommandArguments -ArgumentList $Plan.ArgumentList
  $process.StartInfo.UseShellExecute = $false
  $process.StartInfo.CreateNoWindow = $true
  $process.StartInfo.RedirectStandardOutput = $true
  $process.StartInfo.RedirectStandardError = $true
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  $process.StartInfo.StandardOutputEncoding = $utf8NoBom
  $process.StartInfo.StandardErrorEncoding = $utf8NoBom
  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  return [pscustomobject]@{
    Process = $process
    StdOutTask = $stdoutTask
    StdErrTask = $stderrTask
  }
}

function Invoke-WacTuiProcessRunAs {
  param([Parameter(Mandatory = $true)]$Plan)

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
  $process.StartInfo.FileName = $Plan.FilePath
  $process.StartInfo.Arguments = Join-WacTuiCommandArguments -ArgumentList $Plan.ArgumentList
  $process.StartInfo.UseShellExecute = $true
  $process.StartInfo.Verb = "runas"
  $process.StartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
  [void]$process.Start()
  return [pscustomobject]@{
    Process = $process
    StdOutTask = $null
    StdErrTask = $null
  }
}

function Add-WacTuiChildProcessOutputToLog {
  param(
    [Parameter(Mandatory = $true)]$Plan,
    [Parameter(Mandatory = $true)]$Runner
  )

  if ([string]::IsNullOrWhiteSpace($Plan.LogPath)) { return }

  $entries = New-Object System.Collections.Generic.List[string]
  try {
    $stderr = if ($Runner.StdErrTask) { $Runner.StdErrTask.Result } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
      [void]$entries.Add("[CHILD-STDERR]")
      foreach ($line in ($stderr -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$entries.Add($line) }
      }
    }
  } catch {
    [void]$entries.Add("[CHILD-STDERR-ERROR] $($_.Exception.Message)")
  }

  if ($entries.Count -gt 0) {
    Add-Content -LiteralPath $Plan.LogPath -Value ([string[]]$entries.ToArray()) -Encoding UTF8
  }
}

function New-WacTuiInstallRenderState {
  return [pscustomobject]@{
    LastPercent = 0
    LastPhaseName = ""
    LastSignature = ""
    LastRenderUtc = [datetime]::MinValue
  }
}

function Get-WacTuiInstallRenderSignature {
  param([AllowEmptyString()][string[]]$Lines = @())

  $parts = New-Object System.Collections.Generic.List[string]
  for ($index = 0; $index -lt $Lines.Count; $index++) {
    if ($index -eq 1) { continue }
    $line = $Lines[$index]
    [void]$parts.Add($line)
    if ($line -eq "") { break }
  }
  return ($parts.ToArray() -join "`n")
}

function Test-WacTuiShouldRenderInstallStatus {
  param(
    [Parameter(Mandatory = $true)]$State,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
    [datetime]$NowUtc = [datetime]::UtcNow,
    [bool]$Force = $false
  )

  $signature = Get-WacTuiInstallRenderSignature -Lines $Lines
  if ($Force -or $State.LastSignature -ne $signature) {
    $elapsed = $NowUtc - $State.LastRenderUtc
    if ($Force -or $State.LastRenderUtc -eq [datetime]::MinValue -or $elapsed.TotalMilliseconds -ge 900) {
      $State.LastSignature = $signature
      $State.LastRenderUtc = $NowUtc
      return $true
    }
  }

  return $false
}

function Invoke-WacTuiApply {
  param([Parameter(Mandatory = $true)]$Config)

  $setupEngine = Join-Path $script:ScriptRoot "wac-setup-engine.ps1"
  $powerShellPath = Get-WacTuiWindowsPowerShellPath
  $sudoPath = Get-WacTuiSudoPath
  $logPath = New-WacTuiInstallLogPath

  $plan = New-WacTuiApplyProcessPlan -Config $Config -PowerShellPath $powerShellPath -SetupEnginePath $setupEngine -LogPath $logPath -SudoPath $sudoPath -IsAdmin:(Test-WacTuiAdmin)
  $renderState = New-WacTuiInstallRenderState
  $installTitle = Get-WacTuiOperationTitle -Config $Config -Language $Config.Language
  $statusLines = New-WacTuiInstallStatusLines -Plan $plan -Config $Config -RenderState $renderState
  $previousCursorVisible = Set-WacTuiCursorVisible -Visible $false
  Show-WacTuiFrame -Title $installTitle -Lines $statusLines

  $exitCode = -1
  try {
    $runner = if ($plan.UsesRunAs) {
      Invoke-WacTuiProcessRunAs -Plan $plan
    } else {
      Invoke-WacTuiProcessHidden -Plan $plan
    }
    $process = $runner.Process
    $spinnerFrame = 0
    try {
      while (-not $process.HasExited) {
        Set-WacTuiAnimatedTerminalTitle -Title $installTitle -FrameIndex $spinnerFrame
        $spinnerFrame++
        $statusLines = New-WacTuiInstallStatusLines -Plan $plan -Config $Config -RenderState $renderState
        if (Test-WacTuiShouldRenderInstallStatus -State $renderState -Lines $statusLines) {
          Show-WacTuiFrame -Title $installTitle -Lines $statusLines
        }
        Start-Sleep -Milliseconds 250
      }
      $process.WaitForExit()
      if ($runner.StdOutTask) {
        try { $runner.StdOutTask.Wait(2000) | Out-Null } catch {}
      }
      if ($runner.StdErrTask) {
        try { $runner.StdErrTask.Wait(2000) | Out-Null } catch {}
      }
      $exitCode = $process.ExitCode
      if ($exitCode -ne 0) {
        Add-WacTuiChildProcessOutputToLog -Plan $plan -Runner $runner
      }
    } finally {
      try { $process.Dispose() } catch {}
    }
  } finally {
    if ($null -ne $previousCursorVisible) {
      [void](Set-WacTuiCursorVisible -Visible $previousCursorVisible)
    }
  }

  Show-WacTuiFrame -Title $installTitle -Lines (New-WacTuiInstallStatusLines -Plan $plan -Config $Config -ExitCode $exitCode -Completed:$true -RenderState $renderState)

  if ($exitCode -ne 0) {
    throw ((Get-WacTuiUiText -Key "ApplyFailed" -Language $Config.Language) -f $exitCode, $plan.LogPath)
  }

  $completeLines = New-Object System.Collections.ArrayList
  [void]$completeLines.Add((New-WacTuiProgressBar -Percent 100 -Width 30 -UseUnicode:(!$Ascii)))
  if (-not (Test-WacTuiUninstallAction -Config $Config)) {
    [void]$completeLines.Add(("{0}: https://localhost:{1}" -f (Get-WacTuiUiText -Key "OpenLabel" -Language $Config.Language), $Config.Port))
  }
  [void]$completeLines.Add(("{0}: {1}" -f (Get-WacTuiUiText -Key "LogLabel" -Language $Config.Language), $plan.LogPath))

  Show-WacTuiFrame -Title (Get-WacTuiCompleteTitle -Config $Config -Language $Config.Language) -Lines ([string[]]$completeLines.ToArray())
}

function Start-WacTuiWizard {
  $resolvedLanguage = Get-WacTuiLanguage -Language $Language
  $script:ResolvedLanguage = $resolvedLanguage
  $installState = Get-WacTuiInstallState
  $config = $installState.Config
  $config.Language = $resolvedLanguage
  $platformRisk = Get-WacTuiCurrentPlatformRisk
  if ($platformRisk.Code -eq "Arm64Experimental") {
    $config.SkipArchitectureCheck = $true
  }

  $title = Get-WacTuiText -Key "Title" -Language $resolvedLanguage

  if (-not $PlanOnly) {
    Set-WacTuiWizardWindowSize -Config $config -Language $resolvedLanguage
  }

  Show-WacTuiFrame -Title $title -Lines (New-WacTuiWelcomeLines -Language $resolvedLanguage)
  if ($PlanOnly) {
    return $config
  }
  $welcomeAction = Read-WacTuiWelcomeAction -Title $title -Language $resolvedLanguage
  if ($welcomeAction -eq "Cancel") {
    return $null
  }

  while ($true) {
    while ($true) {
      $licenseAction = Show-WacTuiLicenseScreen -Language $resolvedLanguage
      if ($licenseAction -eq "Back") {
        $welcomeAction = Read-WacTuiWelcomeAction -Title $title -Language $resolvedLanguage
        if ($welcomeAction -eq "Cancel") {
          return $null
        }
        continue
      }
      if ($licenseAction -eq "Cancel") {
        return $null
      }
      $config.AcceptedTerms = $true
      break
    }

    while ($true) {
      $mode = Read-WacTuiModeChoice -Language $resolvedLanguage -InstallState $installState
      if ($mode -eq "Back") {
        break
      }
      if ($mode -eq "Cancel") {
        return $null
      }
      if ($mode -eq "Custom") {
        $config.Action = "Custom"
        $config.InstallMode = "Custom"
        $customAction = Edit-WacTuiCustomConfig -Config $config -Language $resolvedLanguage
        if ($customAction -eq "Back") { continue }
        if ($customAction -eq "Cancel") { return $null }
        break
      }
      if ($mode -eq "Uninstall" -or $mode -eq "UninstallFull") {
        $config.Action = $mode
        $config.InstallMode = $mode
        break
      }
      $config.Action = "Express"
      $config.InstallMode = "Express"
      break
    }
    if ($mode -eq "Back") { continue }

    while ($true) {
      $choice = Read-WacTuiReadyAction -Config $config -Language $resolvedLanguage
      if ($choice -eq "Back") { break }
      if ($choice -eq "Details") {
        [void](Read-WacTuiDetailsAction -Config $config -Language $resolvedLanguage)
        continue
      }
      if ($choice -eq "Cancel") {
        return $null
      }
      if ($choice -eq "Install") {
        Invoke-WacTuiApply -Config $config
        return $config
      }
    }
    if ($choice -eq "Back") {
      continue
    }
  }

  return $config
}

if ($MyInvocation.InvocationName -ne ".") {
  try {
    $wizardResult = Start-WacTuiWizard
    if ($null -eq $wizardResult) {
      Write-Host ""
      Write-Host (Get-WacTuiUiText -Key "Cancelled" -Language $script:ResolvedLanguage)
      Wait-WacTuiOnExit -Language $script:ResolvedLanguage
      exit 0
    }
    Wait-WacTuiOnExit -Language $script:ResolvedLanguage
  } catch {
    $errorLanguage = Get-WacTuiLanguage -Language $Language
    $script:ResolvedLanguage = $errorLanguage
    Write-Host ""
    Write-Host ("{0}: {1}" -f (Get-WacTuiUiText -Key "ErrorPrefix" -Language $errorLanguage), $_.Exception.Message)
    if ($_.ScriptStackTrace) {
      Write-Host $_.ScriptStackTrace
    }
    Wait-WacTuiOnExit -Language $errorLanguage
    exit 1
  }
}




