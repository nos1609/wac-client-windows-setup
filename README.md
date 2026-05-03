# wac-client-windows-setup

English version: [README.en.md](README.en.md)

Неофициальный установочный пакет для Windows Admin Center v2 на клиентских Windows x64.

Штатный установщик WAC сейчас может отказываться работать на клиентской Windows и требовать серверную редакцию. В этом пакете установщик Microsoft не изменяется: сценарий распаковывает содержимое Inno Setup и вручную настраивает систему.

## Статус и границы проекта

Это неофициальный установочный сценарий и не продукт Microsoft. Репозиторий не должен содержать официальный установщик Windows Admin Center, распакованные файлы WAC или бинарник `innoextract`: эти компоненты скачиваются во время установки либо передаются пользователем явно.

Код и документация этого проекта распространяются по лицензии MIT, см. `LICENSE`. Эта лицензия относится только к собственному коду и документации проекта. Она не распространяется на Microsoft Windows, Windows Admin Center, официальный установщик Windows Admin Center, распакованные файлы WAC, расширения Microsoft, уведомления Microsoft о сторонних компонентах или любое другое программное обеспечение Microsoft.

Windows Admin Center является программным обеспечением Microsoft и используется на условиях Microsoft Windows Admin Center и других применимых условий Microsoft и Windows. Отдельные юридические уведомления проекта описаны в `NOTICE.md` и `NOTICE.en.md`.

## Целевая система

- Windows 10 x64 версии 1709 или новее.
- Windows 11 x64.
- Последняя проверенная локально система: Windows 11 x64 26H1.
- Запуск от локального администратора.
- ARM64 не является поддерживаемой целевой платформой WAC; установка на ARM64 остается экспериментальной и без гарантий.

## Официальная поддержка клиентских Windows

Microsoft в текущей документации описывает сценарий `Local client`: установка Windows Admin Center на локальный клиентский компьютер с Windows 10 или 11 для быстрого старта, тестов, разовых задач и небольших окружений:

[Microsoft Learn: Windows Admin Center installation options](https://learn.microsoft.com/windows-server/manage/windows-admin-center/plan/installation-options)

В FAQ Microsoft прямо указано, что Windows Admin Center можно установить на Windows 10 версии 1709 или новее и на Windows 11:

[Microsoft Learn: Windows Admin Center FAQ](https://learn.microsoft.com/windows-server/manage/windows-admin-center/understand/faq)

Судя по истории выпусков, Windows Admin Center стал GA в версии 1804, а Windows 11 как поддерживаемая платформа для установки и управления была отдельно заявлена в релизе 2110:

- [Microsoft Learn: Windows Admin Center release history](https://learn.microsoft.com/windows-server/manage/windows-admin-center/support/release-history)
- [Microsoft Tech Community: Windows Admin Center version 2110 is now generally available](https://techcommunity.microsoft.com/t5/windows-admin-center-blog/windows-admin-center-version-2110-is-now-generally-available/ba-p/2911579)

Поэтому отказ актуального установщика на клиентской Windows трактуется здесь как поведение конкретной версии установщика, а не как попытка обойти лицензионный запрет или распространять измененный Microsoft-бинарник.

## Состав пакета

- `install-wac.cmd` - минимальный ASCII-only запускатель. Снимает `Zone.Identifier` через `Unblock-File` и открывает интерактивный TUI-мастер через PowerShell с `-ExecutionPolicy Bypass`.
- `interactive-installer.ps1` и `tui\*.ps1` - интерактивный терминальный мастер без внешних PowerShell-модулей. Он повторяет документированный ход установки Microsoft и после итогового подтверждения запускает `wac-setup-engine.ps1` скрытым процессом, оставляя ход установки и журнал в основном окне.
- `wac-setup-engine.ps1` - основной установочный сценарий. Его можно запускать напрямую для автоматизации, удаления, пересоздания сертификата и экспериментального запуска на ARM64.
- `LICENSE`, `NOTICE.md` и `NOTICE.en.md` - лицензия проекта и границы между этим open-source-кодом и программным обеспечением Microsoft.

## Проверка и сборка релиза

Перед публикацией из корня репозитория:

```powershell
.\scripts\test-release.ps1
.\scripts\build-dist.ps1
```

`test-release.ps1` проверяет синтаксис PowerShell, запускает Pester-тесты, запускает PSScriptAnalyzer при наличии модуля, ищет локальные пути и запрещенные бинарники. `build-dist.ps1` собирает `dist\wac-client-windows-setup.zip` и рядом кладет SHA256.

## Быстрый запуск

1. Распаковать zip в локальную папку, например:

```text
C:\Temp\wac-client-windows-setup
```

2. Запустить `install-wac.cmd`.
3. Согласиться с UAC.
4. Дождаться завершения.
5. Открыть:

```text
https://localhost:6600
```

Самоподписанный сертификат создается на 60 дней. Браузер будет предупреждать о сертификате, если не передать свой доверенный сертификат или не доверить созданный.

Если WAC должен открываться не только как `https://localhost:6600`, но и через внешний DNS-алиас, например через HTTP-прокси на роутере, укажите это имя в `FQDN внешней точки входа`. При создании самоподписанного сертификата установщик добавляет в него внешний FQDN, FQDN внутренней службы, имя компьютера и `localhost`, поэтому локальный вход через `localhost` остается рабочим.

## TUI-мастер

`install-wac.cmd` по умолчанию открывает интерактивный терминальный мастер. Он использует только встроенные возможности PowerShell, показывает короткий итоговый план перед установкой и выносит подробности в отдельный пункт `Подробно`, чтобы не перегружать основной экран.

Во время установки мастер не открывает отдельную администраторскую консоль, если это технически возможно. Если текущее окно уже повышенное, установочный движок запускается прямо из него. Если окно обычное и в системе включен Windows sudo, мастер показывает только запрос UAC, а затем продолжает обновлять тот же экран. Если Windows sudo недоступен, используется запасной запуск через стандартный `runas`: UAC запускает повышенный дочерний процесс, а основное окно продолжает читать общий журнал установки. Для самого установочного движка используется Windows PowerShell 5.1, чтобы `Enable-PSRemoting` настраивал классический WinRM, а не только конфигурации PowerShell 7.

Прогресс установки берется из реального журнала `C:\WAC-Diag\wac-setup-install-*.log`: мастер двигает шкалу только при появлении фактических этапов установки, а внизу показывает очищенные последние строки без технического шума `RUN`/`EXIT`.

В режиме выборочной установки параметры меняются прямо в мастере. Между строками можно перемещаться стрелками, `Пробел` переключает флажки и циклические значения, `Enter` редактирует выбранное поле или нажимает выбранную кнопку.

Доступны: каталог установки, каталог данных, HTTPS-порт шлюза, диапазон служебных портов, FQDN внешней точки входа, FQDN внутренней службы, режим TLS-сертификата, отпечаток сертификата, `Subject` создаваемого сертификата, режим обновлений, уровень диагностических данных, сетевой доступ, доверие самоподписанному сертификату, PowerShell Remoting, режим `TrustedHosts`, WinRM поверх HTTPS и сохранение существующих данных.

Если мастер запущен на ARM64, на первом экране действия показывается отдельное красное предупреждение. Отдельной галки ARM64 в выборочной установке нет: интерактивный мастер сам передает `-SkipArchitectureCheck`, а прямой запуск `wac-setup-engine.ps1` требует этот параметр явно.

Если WAC уже был установлен этим пакетом, мастер определяет это по файлу `C:\ProgramData\WindowsAdminCenter\wac-setup.json` и первым пунктом предлагает удаление. Обычное удаление снимает службы, задачу планировщика, HTTP.SYS-привязку, правила брандмауэра и каталог программных файлов, но оставляет данные WAC. Полное удаление дополнительно удаляет каталог данных WAC и подсвечивается как рискованное действие.

Каноничная ссылка Microsoft на загрузку установщика: `https://aka.ms/WACDownload`. Эта ссылка указана в Microsoft Learn для PowerShell-установки Windows Admin Center.

Официальный установщик WAC не включен в релизный пакет. `wac-setup-engine.ps1` сначала использует Windows Package Manager только для скачивания:

```cmd
winget download --id Microsoft.WindowsAdminCenter --exact --source winget --architecture x64 --download-directory <каталог>
```

Если `winget.exe` недоступен или скачивание не удалось, сценарий переходит к `https://aka.ms/WACDownload`. В обоих случаях штатный установщик WAC не запускается: скачанный Microsoft-бинарник только распаковывается установочным движком.

Если нужен запуск без скачивания WAC, передайте путь к заранее скачанному официальному установщику явно:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -InstallerPath C:\Temp\WindowsAdminCenter.exe
```

`innoextract` не включен в релизный пакет. Если `-InnoExtractPath` не передан явно, сценарий скачивает Windows-сборку `innoextract` для Inno Setup 6.7.0 из `https://github.com/UserUnknownFactor/innoextract_win/releases/download/670/innoextract670.zip`, проверяет SHA256 `79B69B9B1FCD98F42CCD4B245EFDF6A03BCFB674BA6AF482F5A46891C9ED4D14` и распаковывает ее в `C:\ProgramData\WACSetup\tools`. Чтобы использовать уже скачанный `innoextract.exe` без сети, передайте `-InnoExtractPath` явно. Исходники этой сборки: `https://github.com/UserUnknownFactor/innoextract_win`.

Экран принятия условий не просит вводить `ACCEPT`: в TUI есть обычная строка-флажок `[ ]`, переключается пробелом и подтверждается Enter. Мастер показывает страницу лицензирования Windows Admin Center в Microsoft Learn, отдельные условия EULA для текущего продукта и заявление о конфиденциальности Microsoft:

- [Microsoft Learn: Windows Admin Center licensing](https://learn.microsoft.com/windows-server/windows-server-licensing/windows-admin-center-licensing)
- [Microsoft EULA: Windows Admin Center product GA EULA](https://learn.microsoft.com/legal/windows-server/windows-admin-center/wac-product-ga-eula)
- [Заявление о конфиденциальности Microsoft](https://privacy.microsoft.com/privacystatement)

Уведомления о сторонних компонентах WAC остаются внутри официального установщика Microsoft и не дублируются в релизном пакете. После распаковки содержимого WAC или после установки их можно найти в динамическом каталоге, обычно:

```text
C:\ProgramData\WACSetup\payload*\commonappdata\WindowsAdminCenter\UX\legal\3rdPartyDisclosure.html
C:\ProgramData\WindowsAdminCenter\UX\legal\3rdPartyDisclosure.html
```

Если этот файл уже есть после предыдущей распаковки или установки, TUI показывает путь на странице лицензии.

Для автоматизации или диагностики можно запускать основной движок напрямую:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1
```

## Параметры выборочной установки

На экране `Выборочная установка` все строки выбираются стрелками. `Enter` редактирует текстовые/числовые поля или нажимает выбранную кнопку. `Пробел` переключает флажки и циклические значения. Цвета в TUI имеют смысл: желтый - системная опция, которая меняет безопасность или удаленное управление; красный - разрушительное или неподдерживаемое действие.

| Пункт | Что означает | Что делает установщик |
| --- | --- | --- |
| `Каталог установки` | Папка программных файлов WAC. | Копирует файлы службы и веб-интерфейса. По умолчанию `C:\Program Files\WindowsAdminCenter`. |
| `Каталог данных` | Каталог для данных WAC. | Копирует или создает данные, расширения и служебное состояние WAC. По умолчанию `C:\ProgramData\WindowsAdminCenter`. |
| `HTTPS-порт шлюза` | Порт, на котором открывается веб-интерфейс WAC. | Настраивает `appsettings.json`, HTTP.SYS SSL-привязку, URL ACL и правило брандмауэра. По умолчанию `6600`. |
| `Начало диапазона служебных портов` | Первый внутренний порт сервисов WAC. | Передается в конфигурацию WAC. По умолчанию `6601`. |
| `Конец диапазона служебных портов` | Последний внутренний порт сервисов WAC. | Передается в конфигурацию WAC. Диапазон должен идти после HTTPS-порта и не быть обратным. По умолчанию `6610`. |
| `FQDN внешней точки входа` | Имя, по которому пользователь открывает WAC. | Записывается в настройки шлюза. Если WAC открывается через DNS-алиас и обратный прокси, укажите здесь внешний CNAME. По умолчанию берется имя компьютера. |
| `FQDN внутренней службы` | Имя для внутренних обращений служб WAC. | Записывается в настройки службы. Обычно оставляют `localhost`. Если указать другое имя, TLS-сертификат должен покрывать и его. |
| `Режим TLS-сертификата` | Использовать существующий сертификат или создать самоподписанный. | Если задан отпечаток, используется сертификат из `LocalMachine\My`; иначе создается самоподписанный сертификат. |
| `Отпечаток сертификата` | Thumbprint существующего TLS-сертификата. | Ищется в `LocalMachine\My`. Сертификат должен подходить для Server Authentication, иметь доступный закрытый ключ и содержать все имена WAC, включая `FQDN внешней точки входа`, `FQDN внутренней службы`, имя компьютера и `localhost`. |
| `Subject создаваемого сертификата` | Имя нового самоподписанного сертификата. | Используется только когда отпечаток не задан. Обычное значение TUI не передается как явный параметр. Если включен WinRM поверх HTTPS, CN создаваемого сертификата берется из `FQDN внешней точки входа`; в SAN также добавляются `FQDN внутренней службы`, имя компьютера и `localhost`. Если передать нестандартный `-CertificateSubject` вручную, он должен совпадать с `-EndpointFqdn`; остальные имена установщик добавит в SAN. |
| `Автоматические обновления` | Режим обновления из штатного мастера. | Установщик записывает выбранное значение в конфигурацию; дальнейшие автообновления этот пакет не обслуживает. |
| `Доверять созданному самоподписанному сертификату` | Добавить созданный сертификат в доверенные корневые. | Желтая опция. Работает только для созданного/переиспользованного самоподписанного сертификата; добавляет его в `LocalMachine\Root`, чтобы браузер и внутренние .NET TLS-вызовы меньше ругались. Удаление WAC не удаляет этот сертификат из `LocalMachine\My` или `LocalMachine\Root`: если он больше не нужен, удалите его вручную по отпечатку. |
| `Включить PowerShell Remoting` | Включить WinRM/PowerShell Remoting. | Желтая опция. По умолчанию включено, потому что WAC использует WinRM даже для локального управления. Если отключить, установщик передаст `-SkipPsRemoting`, и часть сценариев WAC может не работать. |
| `Сохранить существующие данные WAC` | Не удалять текущий `C:\ProgramData\WindowsAdminCenter`. | Полезно при восстановлении или переустановке. Если старые данные повреждены, сохранение может оставить и проблему. |
| `Уровень диагностических данных` | Выбор из штатного мастера Microsoft: обязательные или необязательные диагностические данные. | Записывает `WindowsAdminCenter.System.TelemetryPrivacy` в `appsettings.json`. |
| `Сетевой доступ` | Область входящего доступа к веб-интерфейсу WAC. | `только локально` удаляет/не создает входящие правила WAC; `локальная подсеть` создает правила с `RemoteAddress=LocalSubnet`; `любой адрес` открывает правила для `Any`. HTTP.SYS по-прежнему резервируется для выбранного порта WAC. |
| `Режим TrustedHosts` | Разрешить WAC управлять WinRM `TrustedHosts` для рабочих групп и локальных учетных записей. | Желтая опция. `управлять автоматически (*)` выставляет `WSMan:\localhost\Client\TrustedHosts` в `*`, если параметр не задан политикой. Это означает, что WinRM-клиент может доверять любому удаленному хосту в сценариях workgroup/NTLM; это не открывает веб-интерфейс WAC всем, но остается чувствительной настройкой машины. Установщик сохраняет прежнее значение в служебном файле проекта и при удалении вернет его, только если текущее значение всё еще `*`. `не изменять` оставляет текущее значение. |
| `WinRM поверх HTTPS` | Использовать HTTPS для WinRM-соединений WAC. | Желтая опция. Записывает `WindowsAdminCenter.FeatureParameters.Base.WinRmOverHttps=true`, создает HTTPS-прослушиватель WinRM на `5986` с TLS-сертификатом WAC и открывает правило брандмауэра для `5986`. Отключенное значение не удаляет уже существующие прослушиватели WinRM. |

Для сценария с обратным прокси на роутере обычно достаточно задать `FQDN внешней точки входа` внешним CNAME и оставить `FQDN внутренней службы` равным `localhost`. Внешний прокси ведет пользователя на WAC, а сам WAC и локальные проверки продолжают работать через `localhost`. Если включен `WinRM поверх HTTPS`, имя прослушивателя WinRM должно совпадать с CN или SAN сертификата; поэтому автоматически создаваемый сертификат под этот режим привязывается к внешнему FQDN и дополнительно содержит `FQDN внутренней службы`, имя компьютера и `localhost`. Старый самоподписанный сертификат переиспользуется только если он уже содержит нужные имена и подходит для Server Authentication; иначе установщик создаст новый сертификат.

Соответствие параметров командной строке:

| Пункт TUI | Параметр `wac-setup-engine.ps1` |
| --- | --- |
| `Каталог установки` | `-InstallDir` |
| `Каталог данных` | `-DataDir` |
| `HTTPS-порт шлюза` | `-Port` |
| `Начало диапазона служебных портов` | `-ServicePortStart` |
| `Конец диапазона служебных портов` | `-ServicePortEnd` |
| `FQDN внешней точки входа` | `-EndpointFqdn` |
| `FQDN внутренней службы` | `-ServiceFqdn` |
| `Отпечаток сертификата` | `-CertificateThumbprint` |
| `Subject создаваемого сертификата` | `-CertificateSubject` |
| `Автоматические обновления` | <code>-SoftwareUpdateMode Automatic&#124;Manual&#124;Notification</code> |
| `Уровень диагностических данных` | <code>-DiagnosticDataMode Required&#124;Optional</code> |
| `Сетевой доступ` | <code>-NetworkAccess LocalOnly&#124;LocalSubnet&#124;Any</code> |
| `Доверять созданному самоподписанному сертификату` | `-TrustSelfSignedCertificate` |
| `Включить PowerShell Remoting` | выключенное значение дает `-SkipPsRemoting` |
| `Режим TrustedHosts` | <code>-TrustedHostsMode ConfigureTrustedHosts&#124;NotConfigureTrustedHosts</code> |
| `WinRM поверх HTTPS` | <code>-WinRmHttpsMode Enable&#124;Disable</code> |
| `Сохранить существующие данные WAC` | `-KeepExistingData` |

Удаление из командной строки:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -Uninstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -Uninstall -PurgeData
```

`-Uninstall` оставляет данные WAC и удаляет только служебный файл этого пакета. `-PurgeData` удаляет и каталог данных, поэтому используйте его только когда точно нужен чистый старт. Если установщик выставлял `TrustedHosts=*`, удаление попытается вернуть прежнее значение из служебного файла проекта, но не будет заменять настройку, если после установки она уже изменилась. Ни обычное, ни полное удаление не удаляет сертификаты из `Cert:\LocalMachine\My` или `Cert:\LocalMachine\Root`; если вы включали доверие самоподписанному сертификату, проверьте хранилища по отпечатку и удалите сертификат вручную, когда он больше не нужен.

## Вход в WAC

WAC в этом режиме показывает обычную страницу входа с логином и паролем и проверяет локальную учетную запись Windows. На локальной машине используйте имя пользователя в одном из форматов:

```text
.\USERNAME
COMPUTERNAME\USERNAME
```

Например:

```text
.\wacadmin
PC-NAME\wacadmin
```

Если Windows настроена на Windows Hello/PIN, поведение может выглядеть непривычно: имя пользователя берется от локальной учетной записи, а в поле пароля нужно вводить тот секрет, который Windows принимает при локальном входе для этой учетной записи. Это не означает, что WAC поддерживает Windows Hello как WebAuthn или биометрию в браузере; страница WAC все равно передает `username/password` в `/api/user/login`.

Если вход не проходит, сначала проверьте, что внутренние сервисы WAC поднялись:

```cmd
curl -k -I https://localhost:6601
curl -k -I https://localhost:6602
```

Оба должны отвечать `HTTP/1.1 200 OK`. Если 6601/6602 не слушают, это не проблема пароля, а проблема запуска внутренних сервисов WAC.

## Что меняется в системе

Во время установки сценарий меняет систему так:

- останавливает и удаляет службы `WindowsAdminCenter` и `WindowsAdminCenterAccountManagement`, если они уже есть;
- удаляет старую привязку HTTP.SYS на порту `6600`;
- копирует файлы WAC в `C:\Program Files\WindowsAdminCenter`;
- копирует данные WAC в `C:\ProgramData\WindowsAdminCenter`;
- создает или переиспользует TLS-сертификат для выбранных имен WAC;
- дает `NETWORK SERVICE` доступ к закрытому ключу сертификата;
- настраивает `appsettings.json` на порты `6600-6610`;
- регистрирует HTTP.SYS SSL и URL ACL;
- создает или удаляет входящие правила Windows Firewall согласно `-NetworkAccess`;
- включает WinRM/PowerShell Remoting, если не указан `-SkipPsRemoting`;
- при необходимости меняет WinRM `TrustedHosts`;
- при необходимости включает WinRM поверх HTTPS и открывает порт `5986`; для создаваемого сертификата учитывает внешний FQDN, FQDN внутренней службы, имя компьютера и `localhost`;
- перед распаковкой проверяет Authenticode-подпись установщика WAC: подпись должна быть действительной, а издатель должен быть `O=Microsoft Corporation`;
- запускает `efbundle.exe` для инициализации базы WAC;
- копирует файлы обновлятора и регистрирует задачу планировщика `WindowsAdminCenterUpdater`;
- создает и запускает службы WAC.

Логи:

```text
C:\WAC-Diag
```

## Параметры

В интерактивном режиме параметры меняются в TUI. Для автоматизации передавайте параметры напрямую в `wac-setup-engine.ps1`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -Port 8443 -ServicePortStart 8444 -ServicePortEnd 8453
```

Полезные параметры:

```powershell
-Port 6600
-ServicePortStart 6601
-ServicePortEnd 6610
-EndpointFqdn <name>
-CertificateThumbprint <thumbprint>
-SoftwareUpdateMode Automatic|Manual|Notification
-DiagnosticDataMode Required|Optional
-NetworkAccess LocalOnly|LocalSubnet|Any
-TrustSelfSignedCertificate
-TrustedHostsMode ConfigureTrustedHosts|NotConfigureTrustedHosts
-WinRmHttpsMode Enable|Disable
-KeepExistingData
-SkipPsRemoting
-SkipExtraction
-Language Auto|Ru|En
```

`-Language Auto` - режим по умолчанию: скрипт выбирает русский для русской UI-локали Windows, иначе английский. Если нужен конкретный язык, используйте `-Language Ru` или `-Language En`.

Если есть нормальный TLS-сертификат с Server Authentication в `LocalMachine\My`, лучше передать его отпечаток:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -CertificateThumbprint YOUR_CERT_THUMBPRINT
```

## Ручной запуск без .cmd

Из PowerShell с правами администратора:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -LiteralPath . -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
.\wac-setup-engine.ps1
```

## ARM64: экспериментальная установка

Для Windows 11 ARM64 отдельный `.cmd` не поставляется, чтобы не дублировать основной вход. Для экспериментального запуска используйте установочный движок напрямую:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -SkipArchitectureCheck
```

Это не нативная ARM64-установка. В текущем WAC основные исполняемые файлы и нативные зависимости собраны как `win-x64`; запуск возможен только через x64-эмуляцию Windows 11 ARM64. Установщик с `-SkipArchitectureCheck` был проверен на ARM64, но работа самого Windows Admin Center на ARM64 не гарантируется.

Известные ограничения ARM64:

- Раздел **Приложения и компоненты** может открываться несколько минут. WAC вызывает системный `aeinv.dll` (`Application Inventory Component`) через PowerShell remoting; на ARM64 это может зависать заметно дольше, чем на x64. Обычные настройки совместимости Windows применяются к `.exe`, а не к `aeinv.dll` внутри `wsmprovhost.exe`, поэтому включать compatibility layer для этого места не стоит.
- Разделы обзора и сети могут показывать ошибку вида `Класс производительности сети не найден`. На русской Windows счетчик существует как `Сетевой интерфейс`, а WAC в части расширений может запрашивать английское имя `Network Interface`. Это ограничение WAC/локализации, не признак сломанных счетчиков производительности.
- WAC активно использует WinRM/PowerShell Remoting даже для локального компьютера. Локальная учетная запись без обычного пароля, псевдоним учетной записи Microsoft и Windows Hello/PIN могут давать нестабильные ошибки `New-PSSession`/`WSMan`. Для входа и режима `Управлять от имени` лучше использовать явный формат `COMPUTERNAME\user` и пароль, который Windows принимает для этой учетной записи.

## Учетные данные для подключения к ноде

Вход в веб-интерфейс WAC и подключение к выбранной ноде - разные проверки. Учетная запись, под которой открывается веб-интерфейс, может не иметь прав на управление компьютером. Для подключения через WAC учетная запись должна быть администратором на целевой машине.

Для локальной учетной записи используйте явный формат:

```text
COMPUTERNAME\user
```

Короткое имя `user` может пройти на входе в веб-интерфейс, но не пройти при подключении к ноде через WinRM. Пункт `Использовать для этого подключения ... моя учетная запись Windows` зависит от pass-through-аутентификации и Kerberos delegation; в standalone/workgroup-сценарии без доменной настройки обычно надежнее выбрать `другую учетную запись` и указать администратора целевой машины явно.

## Почему не winget install

`winget install --id Microsoft.WindowsAdminCenter` запускает штатный установщик Windows Admin Center. На локально проверенной Windows 11 x64 26H1 этот путь упирается в предварительную проверку WAC, которая требует серверную редакцию Windows.

`winget download` используется иначе: он только скачивает официальный установщик в каталог `C:\ProgramData\WACSetup\downloads`, после чего работает этот установочный движок. Microsoft-бинарники не изменяются.

## Переустановка и восстановление

Для восстановления или переустановки можно снова запустить TUI:

```cmd
install-wac.cmd
```

По умолчанию старые файлы и данные WAC будут заменены. Если нужно сохранить `C:\ProgramData\WindowsAdminCenter`, включите пункт `Сохранить существующие данные WAC` в TUI или запустите установочный движок напрямую:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -KeepExistingData
```

Если службы WAC запущены, порт `6600` слушает, но браузер или `curl -k -I https://localhost:6600` обрываются на этапе TLS handshake, проверьте Schannel в системном журнале Windows. Ошибка `0x8009030D` обычно означает, что HTTPS-слой не может прочитать закрытый ключ сертификата WAC под `NETWORK SERVICE`.

В таком случае проще не чинить старую привязку ключа, а выдать WAC новый сертификат:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -KeepExistingData -TrustSelfSignedCertificate
```

На ARM64:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -SkipArchitectureCheck -KeepExistingData -TrustSelfSignedCertificate
```

Эти команды сохраняют `C:\ProgramData\WindowsAdminCenter` и создают или переиспользуют сертификат под текущий `FQDN внешней точки входа`. Если WAC должен открываться через внешний CNAME, передайте его явно через `-EndpointFqdn`; при включенном WinRM поверх HTTPS этот FQDN станет CN создаваемого сертификата, а `FQDN внутренней службы` и `localhost` останутся в SAN. Если на машине уже есть старый самоподписанный сертификат WAC с неподходящими именами, он не будет переиспользован.
При восстановлении самоподписанный сертификат также добавляется в `LocalMachine\Root`, потому что часть внутренних TLS-подключений WAC/.NET может не принять недоверенную цепочку даже при рабочем веб-интерфейсе WAC. Этот корневой сертификат остается в хранилище после удаления WAC, пока вы не удалите его вручную.











