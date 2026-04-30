function Get-WacTuiInstallPhases {
  return ,([pscustomobject[]]@(
    [pscustomobject]@{ Name = "Extract"; Percent = 5; LabelEn = "Extracting payload"; LabelRu = "Распаковка установщика" }
    [pscustomobject]@{ Name = "Cleanup"; Percent = 5; LabelEn = "Removing previous services"; LabelRu = "Удаление прежних служб" }
    [pscustomobject]@{ Name = "CopyFiles"; Percent = 25; LabelEn = "Copying files"; LabelRu = "Копирование файлов" }
    [pscustomobject]@{ Name = "Acls"; Percent = 35; LabelEn = "Configuring permissions"; LabelRu = "Настройка прав доступа" }
    [pscustomobject]@{ Name = "Certificate"; Percent = 45; LabelEn = "Configuring certificate"; LabelRu = "Настройка сертификата" }
    [pscustomobject]@{ Name = "Config"; Percent = 55; LabelEn = "Writing configuration"; LabelRu = "Запись конфигурации" }
    [pscustomobject]@{ Name = "HttpSys"; Percent = 63; LabelEn = "Registering HTTP.sys"; LabelRu = "Регистрация HTTP.sys" }
    [pscustomobject]@{ Name = "Firewall"; Percent = 70; LabelEn = "Configuring firewall"; LabelRu = "Настройка брандмауэра" }
    [pscustomobject]@{ Name = "WinRm"; Percent = 76; LabelEn = "Configuring WinRM"; LabelRu = "Настройка WinRM" }
    [pscustomobject]@{ Name = "Database"; Percent = 82; LabelEn = "Initializing database"; LabelRu = "Инициализация базы данных" }
    [pscustomobject]@{ Name = "Services"; Percent = 88; LabelEn = "Registering services"; LabelRu = "Регистрация служб" }
    [pscustomobject]@{ Name = "Start"; Percent = 94; LabelEn = "Starting service"; LabelRu = "Запуск службы" }
    [pscustomobject]@{ Name = "PortCheck"; Percent = 100; LabelEn = "Checking HTTPS port"; LabelRu = "Проверка HTTPS-порта" }
  ))
}

function Get-WacTuiPhasePercent {
  param(
    [string]$Name = ""
  )

  foreach ($phase in (Get-WacTuiInstallPhases)) {
    if ($phase.Name -eq $Name) {
      return $phase.Percent
    }
  }

  return 0
}

function Get-WacTuiPhaseLabel {
  param(
    [string]$Name = "",
    [ValidateSet("Ru", "En")][string]$Language = "En"
  )

  foreach ($phase in (Get-WacTuiInstallPhases)) {
    if ($phase.Name -eq $Name) {
      if ($Language -eq "Ru") { return $phase.LabelRu }
      return $phase.LabelEn
    }
  }

  return $Name
}

function Get-WacTuiPhaseFromLogLine {
  param([string]$Line = "")

  if ($Line -match "\[STEP\].*Extracting installer payload") { return "Extract" }
  if ($Line -match "\[STEP\].*Stopping/removing previous WAC services") { return "Cleanup" }
  if ($Line -match "\[STEP\].*Copying files") { return "CopyFiles" }
  if ($Line -match "\[INFO\].*Granting ACLs") { return "Acls" }
  if ($Line -match "\[INFO\].*(Creating self-signed certificate|Reusing self-signed certificate|Granting NETWORK SERVICE access to certificate private key)") { return "Certificate" }
  if ($Line -match "\[INFO\].*Configuring appsettings\.json") { return "Config" }
  if ($Line -match "\[INFO\].*Registering HTTP\.SYS") { return "HttpSys" }
  if ($Line -match "\[INFO\].*Registering firewall rules") { return "Firewall" }
  if ($Line -match "\[STEP\].*Enabling PowerShell remoting") { return "WinRm" }
  if ($Line -match "\[INFO\].*Initializing WAC database") { return "Database" }
  if ($Line -match "\[INFO\].*Registering services") { return "Services" }
  if ($Line -match "\[STEP\].*Starting WindowsAdminCenter service") { return "Start" }
  if ($Line -match "\[INFO\].*TCP port .* is listening") { return "PortCheck" }
  return ""
}

function Get-WacTuiProgressFromLogLines {
  param([string[]]$Lines = @())

  $phaseName = ""
  $percent = 0
  foreach ($line in $Lines) {
    $candidate = Get-WacTuiPhaseFromLogLine -Line $line
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    $candidatePercent = Get-WacTuiPhasePercent -Name $candidate
    if ($candidatePercent -ge $percent) {
      $phaseName = $candidate
      $percent = $candidatePercent
    }
  }

  return [pscustomobject]@{
    PhaseName = $phaseName
    Percent = $percent
  }
}
