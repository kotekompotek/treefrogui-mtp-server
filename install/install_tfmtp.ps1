# TreeFrogUI MTP fix installer (tfmtp + patched usb_mode.sh) / Установщик исправления MTP для TreeFrogUI
#
#   install_tfmtp.ps1                 - find the TreeFrogUI SD card automatically and install
#   install_tfmtp.ps1 -Target F:\     - install to a given card (or a folder with a copy of the card)
#   install_tfmtp.ps1 -Uninstall      - restore the original usb_mode.sh and remove tfmtp
#   install_tfmtp.ps1 -Force          - also install over an unknown usb_mode.sh version (keeps a backup)
param([string]$Target, [switch]$Uninstall, [switch]$Force)
$ErrorActionPreference = 'Stop'

$RU = (Get-UICulture).Name -like 'ru*'
function T($en, $ru) { if ($RU) { $ru } else { $en } }
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-Host ((T 'ERROR: ' 'ОШИБКА: ') + $m) -ForegroundColor Red; exit 1 }
function Get-Sha($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

$pkg      = Split-Path $PSScriptRoot -Parent
$srcMode  = Join-Path $pkg 'sdcard\cubegm\usb_mode.sh'
$srcTfmtp = Join-Path $pkg 'sdcard\cubegm\tfmtp'
# SHA-256 of the original cubegm/usb_mode.sh shipped with TreeFrogUI v1.8.0_u
$ORIG_KNOWN = @{ '20AB52FF0AAB3127D6F557FDCE04ADE92AEDE30B13AB00B845A6F8C5C940A0BA' = 'TreeFrogUI v1.8.0_u' }

if (-not $Uninstall -and -not (Test-Path $srcTfmtp)) {
    Die (T 'sdcard\cubegm\tfmtp is missing. Download the release zip (it contains the compiled tfmtp) or run build.sh.' `
           'нет sdcard\cubegm\tfmtp. Скачайте zip из раздела Releases (в нём собранный tfmtp) или соберите build.sh.')
}

# ---- locate the card ----
if (-not $Target) {
    $cands = Get-PSDrive -PSProvider FileSystem | Where-Object { Test-Path (Join-Path $_.Root 'cubegm\usb_mode.sh') } | ForEach-Object { $_.Root }
    if (@($cands).Count -eq 1) { $Target = @($cands)[0] }
    elseif (@($cands).Count -gt 1) { Die ((T 'several TreeFrogUI cards found: ' 'найдено несколько карт TreeFrogUI: ') + ($cands -join ', ') + (T '. Pick one: -Target F:\' '. Укажите нужную: -Target F:\')) }
    else { Die (T 'no TreeFrogUI card found (no cubegm\usb_mode.sh on any drive). Insert the card into a card reader or use -Target.' 'карта TreeFrogUI не найдена (нет cubegm\usb_mode.sh ни на одном диске). Вставьте карту в картридер или укажите -Target.') }
}
$cg = Join-Path $Target 'cubegm'
$dstMode = Join-Path $cg 'usb_mode.sh'; $dstTfmtp = Join-Path $cg 'tfmtp'; $bakMode = Join-Path $cg 'usb_mode.sh.orig'
if (-not (Test-Path $dstMode)) { Die ("$dstMode " + (T 'not found - this is not a TreeFrogUI card.' 'не найден - это не карта TreeFrogUI.')) }
if (-not (Test-Path (Join-Path $cg 'usb_mtp.sh'))) { Die (T 'cubegm\usb_mtp.sh is missing - this TreeFrogUI version has no built-in MTP mode.' 'на карте нет cubegm\usb_mtp.sh - в этой версии TreeFrogUI нет встроенного MTP-режима.') }
$ver = Get-Content (Join-Path $cg 'version.txt') -ErrorAction SilentlyContinue
Say ((T 'Card: ' 'Карта: ') + "$Target   TreeFrogUI: $ver") 'Cyan'

$patchedHash = Get-Sha $srcMode
$cur = Get-Sha $dstMode

if ($Uninstall) {
    if (Test-Path $bakMode) {
        Copy-Item -LiteralPath $bakMode -Destination $dstMode -Force
        Remove-Item -LiteralPath $bakMode -Force
        Say (T 'usb_mode.sh restored from usb_mode.sh.orig' 'usb_mode.sh восстановлен из usb_mode.sh.orig') 'Green'
    } elseif ($cur -eq $patchedHash) {
        Die (T 'usb_mode.sh is patched but there is no usb_mode.sh.orig backup. Take the original from patch\usb_mode.sh.orig-v1.8.0_u (v1.8.0_u only).' 'usb_mode.sh исправлен, но резервной копии usb_mode.sh.orig нет. Возьмите оригинал из patch\usb_mode.sh.orig-v1.8.0_u (только для v1.8.0_u).')
    } else { Say (T 'usb_mode.sh was not changed by this package - leaving it as is.' 'usb_mode.sh не изменялся этим пакетом - оставляю как есть.') }
    if (Test-Path $dstTfmtp) { Remove-Item -LiteralPath $dstTfmtp -Force; Say (T 'cubegm\tfmtp removed (the stock mtp-server will be used).' 'cubegm\tfmtp удалён (будет использоваться штатный mtp-server).') 'Green' }
    Say (T 'Done. Safely eject the card.' 'Готово. Безопасно извлеките карту.') 'Cyan'
    exit 0
}

# ---- usb_mode.sh ----
if ($cur -eq $patchedHash) {
    Say (T 'usb_mode.sh: already patched (skipped).' 'usb_mode.sh: уже исправлен (пропускаю).') 'Green'
} elseif ($ORIG_KNOWN.ContainsKey($cur)) {
    if (-not (Test-Path $bakMode)) { Copy-Item -LiteralPath $dstMode -Destination $bakMode }
    Copy-Item -LiteralPath $srcMode -Destination $dstMode -Force
    Say ((T 'usb_mode.sh: replaced (was: ' 'usb_mode.sh: заменён (было: ') + $ORIG_KNOWN[$cur] + (T '; backup: cubegm\usb_mode.sh.orig)' '; резервная копия: cubegm\usb_mode.sh.orig)')) 'Green'
} elseif ($Force) {
    $b = "$dstMode.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $dstMode -Destination $b
    Copy-Item -LiteralPath $srcMode -Destination $dstMode -Force
    Say ((T 'usb_mode.sh: UNKNOWN version replaced (-Force). Backup: ' 'usb_mode.sh: НЕИЗВЕСТНАЯ версия заменена принудительно (-Force). Резервная копия: ') + $b) 'Yellow'
    Say (T 'If USB mode stops working, restore the backup and apply the 3 edits by hand (README, "Manual install").' 'Если USB-режим перестанет работать - верните резервную копию и внесите 3 правки вручную (README, "Ручная установка").') 'Yellow'
} else {
    Die ((T "usb_mode.sh on the card differs from v1.8.0_u (SHA-256 $cur).`nReplacing a different TreeFrogUI version wholesale could break its USB mode.`nOptions: (1) apply the 3 edits by hand - README, 'Manual install';`n         (2) apply patch\usb_mode.sh.patch (git apply / patch -p1);`n         (3) force it: install_tfmtp.ps1 -Force" `
                "usb_mode.sh на карте отличается от версии v1.8.0_u (SHA-256 $cur).`nЗамена целиком может сломать USB-режим другой версии TreeFrogUI.`nВарианты: (1) внести 3 правки вручную - README.ru.md, раздел 'Ручная установка';`n          (2) применить patch\usb_mode.sh.patch (git apply / patch -p1);`n          (3) заменить принудительно: install_tfmtp.ps1 -Force"))
}

# ---- tfmtp ----
Copy-Item -LiteralPath $srcTfmtp -Destination $dstTfmtp -Force
Say (T 'cubegm\tfmtp: copied.' 'cubegm\tfmtp: скопирован.') 'Green'

# ---- verify ----
$ok = ((Get-Sha $dstTfmtp) -eq (Get-Sha $srcTfmtp)) -and ((Get-Sha $dstMode) -eq $patchedHash)
if (-not $ok) { Die (T 'checksums do not match after copying. Check the card and retry.' 'контрольные суммы после копирования не совпали. Проверьте карту и повторите.') }
if ($Target -match '^[A-Za-z]:\\?$') { try { Write-VolumeCache -DriveLetter $Target.Substring(0,1) -ErrorAction Stop } catch {} }
Say (T 'SHA-256 check: OK. Installation complete.' 'Проверка SHA-256: OK. Установка завершена.') 'Cyan'
Say (T 'Next: safely eject the card, put it in the console, TreeFrogUI menu -> USB (MTP), connect the cable to the PC.' 'Дальше: безопасно извлеките карту, вставьте в консоль, меню TreeFrogUI -> USB (MTP), подключите кабель к ПК.') 'Cyan'
