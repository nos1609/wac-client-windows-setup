function ConvertFrom-WacTuiCodePoint {
  param([Parameter(Mandatory = $true)][int[]]$CodePoint)

  return -join ($CodePoint | ForEach-Object { [char]$_ })
}

$script:WacTuiStrings = @{
  Title = @{
    En = "Windows Admin Center Setup"
    Ru = "Установка Windows Admin Center"
  }
  Back = @{
    En = "Back"
    Ru = "Назад"
  }
  Next = @{
    En = "Next"
    Ru = "Далее"
  }
  Cancel = @{
    En = "Cancel"
    Ru = "Отмена"
  }
  Details = @{
    En = "Details"
    Ru = "Подробно"
  }
  Install = @{
    En = "Install"
    Ru = "Установить"
  }
  Uninstall = @{
    En = "Uninstall"
    Ru = "Удалить"
  }
  UninstallFull = @{
    En = "Uninstall fully"
    Ru = "Удалить полностью"
  }
  LicenseTitle = @{
    En = "License and Privacy"
    Ru = "Лицензия и конфиденциальность"
  }
  LicenseIntro = @{
    En = "Review Microsoft license terms and privacy statement before installing."
    Ru = "Перед установкой ознакомьтесь с условиями лицензии Microsoft и заявлением о конфиденциальности."
  }
  LicenseProjectNotice = @{
    En = "This setup script is independent and not affiliated with Microsoft; the MIT license covers only this project's code."
    Ru = "Этот установочный сценарий независим и не связан с Microsoft; лицензия MIT покрывает только код проекта."
  }
  LicenseNoLocal = @{
    En = "Local third-party notices are not available yet; they remain inside the Microsoft installer until payload extraction."
    Ru = "Локальные уведомления о сторонних компонентах пока недоступны: они остаются внутри установщика Microsoft до распаковки."
  }
  LicenseTermsUrl = @{
    En = "Windows Admin Center licensing: https://learn.microsoft.com/windows-server/windows-server-licensing/windows-admin-center-licensing"
    Ru = "Лицензирование Windows Admin Center: https://learn.microsoft.com/windows-server/windows-server-licensing/windows-admin-center-licensing"
  }
  LicenseEulaUrl = @{
    En = "Windows Admin Center product EULA: https://learn.microsoft.com/legal/windows-server/windows-admin-center/wac-product-ga-eula"
    Ru = "Условия EULA для Windows Admin Center: https://learn.microsoft.com/legal/windows-server/windows-admin-center/wac-product-ga-eula"
  }
  PrivacyUrl = @{
    En = "Privacy statement: https://privacy.microsoft.com/privacystatement"
    Ru = "Заявление о конфиденциальности: https://privacy.microsoft.com/privacystatement"
  }
  ThirdParty = @{
    En = "Third-party notices: {0}"
    Ru = "Уведомления о сторонних компонентах: {0}"
  }
  LicenseCheckbox = @{
    En = "[ ] I accept the license terms and understand the privacy statement"
    Ru = "[ ] Условия лицензии приняты, заявление о конфиденциальности прочитано"
  }
  LicenseCheckboxOn = @{
    En = "[x] I accept the license terms and understand the privacy statement"
    Ru = "[x] Условия лицензии приняты, заявление о конфиденциальности прочитано"
  }
  LicensePrompt = @{
    En = "Space - toggle, Enter - continue, C - cancel"
    Ru = "Пробел - поставить или снять флажок, Enter - продолжить, C - отменить"
  }
  LicenseRequired = @{
    En = "Select the checkbox before continuing."
    Ru = "Чтобы продолжить, сначала поставьте флажок принятия условий."
  }
  ModeTitle = @{
    En = "Action"
    Ru = "Действие"
  }
  ModeExpress = @{
    En = "Express setup"
    Ru = "Быстрая установка"
  }
  ModeCustom = @{
    En = "Custom setup"
    Ru = "Выборочная установка"
  }
  ActionRepair = @{
    En = "Reinstall / repair"
    Ru = "Переустановить / восстановить"
  }
  ActionChange = @{
    En = "Change settings"
    Ru = "Изменить параметры"
  }
  ActionUninstall = @{
    En = "Uninstall Windows Admin Center"
    Ru = "Удалить Windows Admin Center"
  }
  ActionUninstallFull = @{
    En = "Full uninstall, including WAC data"
    Ru = "Удалить полностью, включая данные WAC"
  }
  ModeRisk = @{
    En = "Server-style options are shown as risk states on client Windows."
    Ru = "Параметры, рассчитанные на серверную установку, на клиентской Windows будут помечены как рискованные."
  }
  ModeArm64Warning = @{
    En = "ARM64 detected: install path is verified best-effort, but Windows Admin Center runtime is not guaranteed on ARM64."
    Ru = "Обнаружена ARM64: путь установки проверен как best-effort, но работа Windows Admin Center на ARM64 не гарантируется."
  }
  ChooseMode = @{
    En = "Choose 1 or 2"
    Ru = "Выберите 1 или 2"
  }
  ReadyTitle = @{
    En = "Ready to install"
    Ru = "Готово к установке"
  }
  ReadyUninstallTitle = @{
    En = "Ready to uninstall"
    Ru = "Готово к удалению"
  }
  DetailsTitle = @{
    En = "Install details"
    Ru = "Подробный план установки"
  }
  DetailsUninstallTitle = @{
    En = "Uninstall details"
    Ru = "Подробный план удаления"
  }
  DetailsPrompt = @{
    En = "[D] Details  [I] Install  [C] Cancel"
    Ru = "[D] Подробно  [I] Установить  [C] Отмена"
  }
  PressEnter = @{
    En = "Press Enter to return"
    Ru = "Нажмите Enter, чтобы вернуться"
  }
  PressEnterToClose = @{
    En = "Press Enter to close"
    Ru = "Нажмите Enter, чтобы закрыть"
  }
  Cancelled = @{
    En = "Installation cancelled by user."
    Ru = "Установка отменена пользователем."
  }
  ErrorPrefix = @{
    En = "ERROR"
    Ru = "ОШИБКА"
  }
  ApplyFailed = @{
    En = "Setup engine failed with exit code {0}. Log: {1}"
    Ru = "Установочный движок завершился с кодом {0}. Журнал: {1}"
  }
  InstallingTitle = @{
    En = "Installing Windows Admin Center"
    Ru = "Установка Windows Admin Center"
  }
  UninstallingTitle = @{
    En = "Uninstalling Windows Admin Center"
    Ru = "Удаление Windows Admin Center"
  }
  StartingSetup = @{
    En = "Starting setup engine..."
    Ru = "Запускаю установочный движок..."
  }
  StartingUninstall = @{
    En = "Starting uninstall..."
    Ru = "Запускаю удаление..."
  }
  StatusLabel = @{
    En = "Status"
    Ru = "Состояние"
  }
  SudoInline = @{
    En = "UAC may ask for confirmation; installation output stays in this window."
    Ru = "Окно контроля учетных записей может запросить подтверждение; ход установки останется здесь."
  }
  SudoOperationInline = @{
    En = "UAC may ask for confirmation; operation output stays in this window."
    Ru = "Окно контроля учетных записей может запросить подтверждение; ход операции останется здесь."
  }
  RunAsInline = @{
    En = "Windows sudo was not found; UAC will start an elevated helper and this window will keep reading the log."
    Ru = "Windows sudo не найден; UAC запустит повышенный дочерний процесс, а это окно продолжит читать журнал."
  }
  CompleteTitle = @{
    En = "Installation complete"
    Ru = "Установка завершена"
  }
  UninstallCompleteTitle = @{
    En = "Uninstall complete"
    Ru = "Удаление завершено"
  }
  OpenLabel = @{
    En = "Open"
    Ru = "Открыть"
  }
  LogLabel = @{
    En = "Log"
    Ru = "Журнал"
  }
  SummaryMode = @{
    En = "Mode: {0}"
    Ru = "Режим: {0}"
  }
  SummaryOpen = @{
    En = "Open after install: https://localhost:{0}"
    Ru = "После установки откройте: https://localhost:{0}"
  }
  SummaryUninstallTarget = @{
    En = "Target: Windows Admin Center services and files"
    Ru = "Цель: службы и файлы Windows Admin Center"
  }
  SummaryUninstallKeepData = @{
    En = "Data: keep existing Windows Admin Center data"
    Ru = "Данные: сохранить существующие данные Windows Admin Center"
  }
  SummaryUninstallPurgeData = @{
    En = "Data: remove Windows Admin Center data"
    Ru = "Данные: удалить данные Windows Admin Center"
  }
  SummaryUninstallServices = @{
    En = "Services: stop and remove WindowsAdminCenter services"
    Ru = "Службы: остановить и удалить службы WindowsAdminCenter"
  }
  SummaryUninstallNetwork = @{
    En = "Network: remove HTTP.sys bindings and firewall rules"
    Ru = "Сеть: удалить привязки HTTP.sys и правила брандмауэра"
  }
  SummaryCertificate = @{
    En = "Certificate: {0}"
    Ru = "Сертификат: {0}"
  }
  CertExisting = @{
    En = "existing certificate"
    Ru = "существующий сертификат"
  }
  CertGenerated = @{
    En = "generated self-signed certificate"
    Ru = "новый самоподписанный сертификат"
  }
  SummaryServices = @{
    En = "Services: WindowsAdminCenter and account management service"
    Ru = "Службы: WindowsAdminCenter и служба управления учетными записями"
  }
  SummaryNetwork = @{
    En = "Network: firewall and WinRM according to selected options"
    Ru = "Сеть: правила брандмауэра и WinRM согласно выбранным параметрам"
  }
  WelcomeMode = @{
    En = "Mode: interactive wizard over setup engine"
    Ru = "Режим: интерактивный мастер поверх установочного движка"
  }
  WelcomeSource = @{
    En = "Source: https://aka.ms/WACDownload"
    Ru = "Источник: https://aka.ms/WACDownload"
  }
  WelcomeInvoke = @{
    En = "wac-setup-engine.ps1 runs after final confirmation."
    Ru = "После итогового подтверждения будет запущен wac-setup-engine.ps1."
  }
  AssertLicense = @{
    En = "License terms and privacy statement must be accepted before installation."
    Ru = "Перед установкой нужно принять условия лицензии и ознакомиться с заявлением о конфиденциальности."
  }
  CustomTitle = @{
    En = "Custom setup"
    Ru = "Выборочная установка"
  }
  CustomPrompt = @{
    En = "Up/Down - select, Space - toggle, Enter - edit/press"
    Ru = "Вверх/вниз - выбор, Пробел - переключить, Enter - изменить или нажать"
  }
  NavigationPrompt = @{
    En = "Up/Down - select, Enter - press"
    Ru = "Вверх/вниз - выбор, Enter - нажать"
  }
  KeepCurrentPrompt = @{
    En = "New value (empty keeps current)"
    Ru = "Новое значение (оставьте пустым, чтобы не менять)"
  }
  ChooseTlsPrompt = @{
    En = "TLS certificate: 1 - generate self-signed, 2 - use installed certificate"
    Ru = "TLS-сертификат: 1 - создать самоподписанный, 2 - использовать установленный"
  }
  ChooseUpdatePrompt = @{
    En = "Updates: 1 - Automatic, 2 - Manual, 3 - Notification"
    Ru = "Обновления: 1 - автоматически, 2 - вручную, 3 - только уведомлять"
  }
  InvalidValue = @{
    En = "Invalid value."
    Ru = "Недопустимое значение."
  }
  ValueSelfSigned = @{
    En = "generate self-signed certificate"
    Ru = "создать самоподписанный сертификат"
  }
  ValueInstalledCert = @{
    En = "use installed certificate by thumbprint"
    Ru = "использовать установленный сертификат по отпечатку"
  }
  Enabled = @{
    En = "enabled"
    Ru = "включено"
  }
  Disabled = @{
    En = "disabled"
    Ru = "отключено"
  }
  NotApplied = @{
    En = "shown only, not applied by this setup engine"
    Ru = "не применяется"
  }
  OptInstallDir = @{
    En = "Install directory"
    Ru = "Каталог установки"
  }
  OptDataDir = @{
    En = "Data directory"
    Ru = "Каталог данных"
  }
  OptPort = @{
    En = "Gateway HTTPS port"
    Ru = "HTTPS-порт шлюза"
  }
  OptServicePortStart = @{
    En = "Service port range start"
    Ru = "Начало диапазона служебных портов"
  }
  OptServicePortEnd = @{
    En = "Service port range end"
    Ru = "Конец диапазона служебных портов"
  }
  OptEndpointFqdn = @{
    En = "Endpoint FQDN"
    Ru = "FQDN внешней точки входа"
  }
  OptServiceFqdn = @{
    En = "Internal service FQDN"
    Ru = "FQDN внутренней службы"
  }
  OptTlsMode = @{
    En = "TLS certificate mode"
    Ru = "Режим TLS-сертификата"
  }
  OptCertThumbprint = @{
    En = "Certificate thumbprint"
    Ru = "Отпечаток сертификата"
  }
  OptCertSubject = @{
    En = "Generated certificate subject"
    Ru = "Субъект создаваемого сертификата"
  }
  OptUpdateMode = @{
    En = "Automatic updates"
    Ru = "Автоматические обновления"
  }
  OptTrustSelfSigned = @{
    En = "Trust generated self-signed certificate"
    Ru = "Доверять созданному самоподписанному сертификату"
  }
  OptPsRemoting = @{
    En = "Enable PowerShell remoting"
    Ru = "Включить PowerShell Remoting"
  }
  OptKeepData = @{
    En = "Keep existing WAC data"
    Ru = "Сохранить существующие данные WAC"
  }
  OptArm64 = @{
    En = "ARM64 best-effort install"
    Ru = "ARM64: установка возможна, работа WAC не гарантируется"
  }
  OptDiagnostic = @{
    En = "Diagnostic data preference"
    Ru = "Уровень диагностических данных"
  }
  OptNetworkAccess = @{
    En = "Network access"
    Ru = "Сетевой доступ"
  }
  OptTrustedHosts = @{
    En = "Trusted hosts mode"
    Ru = "Режим TrustedHosts"
  }
  OptWinRmHttps = @{
    En = "WinRM over HTTPS"
    Ru = "WinRM поверх HTTPS"
  }
  EnglishOnlyProbe = @{
    En = "English fallback"
  }
}

function Get-WacTuiLanguage {
  param(
    [ValidateSet("Auto", "Ru", "En")]
    [string]$Language = "Auto",
    $Culture = [Globalization.CultureInfo]::CurrentUICulture
  )

  if ($Language -ne "Auto") { return $Language }
  if ($Culture.TwoLetterISOLanguageName -eq "ru") { return "Ru" }
  return "En"
}

function Get-WacTuiText {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [ValidateSet("Ru", "En")][string]$Language = "En"
  )

  if (-not $script:WacTuiStrings.ContainsKey($Key)) {
    throw "Unknown TUI string key: $Key"
  }

  $entry = $script:WacTuiStrings[$Key]
  if ($entry.ContainsKey($Language)) { return $entry[$Language] }
  if ($entry.ContainsKey("En")) { return $entry["En"] }
  throw "String key '$Key' has no '$Language' or 'En' value."
}



