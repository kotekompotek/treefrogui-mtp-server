# TreeFrogUI MTP fix installer / Установщик исправления MTP для TreeFrogUI
#
#   install_tfmtp.ps1                  - fix the built-in MTP mode + background MTP (tfusbd)
#   install_tfmtp.ps1 -Remote          - also enable remote control from the PC (root shell over MTP)
#   install_tfmtp.ps1 -NoBackground    - only the MTP fix (v1.0 behaviour), no background service
#   install_tfmtp.ps1 -Target F:\      - install to a given card (or a folder with a copy of the card)
#   install_tfmtp.ps1 -Uninstall       - undo everything this package changed
#   install_tfmtp.ps1 -Force           - also install over an unknown usb_mode.sh version (keeps a backup)
param([string]$Target, [switch]$Uninstall, [switch]$Force, [switch]$NoBackground, [switch]$Remote)
$ErrorActionPreference = 'Stop'

$RU = (Get-UICulture).Name -like 'ru*'
function T($en, $ru) { if ($RU) { $ru } else { $en } }
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-Host ((T 'ERROR: ' 'ОШИБКА: ') + $m) -ForegroundColor Red; exit 1 }
function Get-Sha($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
$Utf8 = New-Object System.Text.UTF8Encoding($false)
function Read-Text($p) { [IO.File]::ReadAllText($p, $Utf8) }
function Write-Text($p, $s) { [IO.File]::WriteAllText($p, $s, $Utf8) }
function Touch($p) { if (-not (Test-Path -LiteralPath $p)) { [IO.File]::WriteAllBytes($p, [byte[]]@()) } }
function Remove-IfExists($p) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; $true } else { $false } }

$pkg      = Split-Path $PSScriptRoot -Parent
$srcCg    = Join-Path $pkg 'sdcard\cubegm'
$srcMode  = Join-Path $srcCg 'usb_mode.sh'
$srcMtp   = Join-Path $srcCg 'usb_mtp.sh'
$hookText = (Read-Text (Join-Path $pkg 'patch\zhijack.hook')).Replace("`r`n", "`n")
$bgFiles  = @('tfusbd', 'tfusbd.sh', 'tfkey')
# SHA-256 of the original files shipped with TreeFrogUI v1.8.0_u
$ORIG_MODE = @{ '20AB52FF0AAB3127D6F557FDCE04ADE92AEDE30B13AB00B845A6F8C5C940A0BA' = 'TreeFrogUI v1.8.0_u' }
$ORIG_MTP  = @{ '28F0F74862F2D1C28DCAC58C76310A74BA11608B4A76ADFB40B3BEEDD382697E' = 'TreeFrogUI v1.8.0_u' }

if (-not $Uninstall) {
    foreach ($b in @('tfmtp') + $(if ($NoBackground) { @() } else { $bgFiles })) {
        if (-not (Test-Path (Join-Path $srcCg $b))) {
            Die ((T "sdcard\cubegm\$b is missing. Download the release zip (it contains the compiled binaries) or run build.sh." `
                    "нет sdcard\cubegm\$b. Скачайте zip из раздела Releases (в нём собранные файлы) или соберите build.sh."))
        }
    }
}

# ---- locate the card ----
if (-not $Target) {
    $cands = Get-PSDrive -PSProvider FileSystem | Where-Object { Test-Path (Join-Path $_.Root 'cubegm\usb_mode.sh') } | ForEach-Object { $_.Root }
    if (@($cands).Count -eq 1) { $Target = @($cands)[0] }
    elseif (@($cands).Count -gt 1) { Die ((T 'several TreeFrogUI cards found: ' 'найдено несколько карт TreeFrogUI: ') + ($cands -join ', ') + (T '. Pick one: -Target F:\' '. Укажите нужную: -Target F:\')) }
    else { Die (T 'no TreeFrogUI card found (no cubegm\usb_mode.sh on any drive). Insert the card into a card reader or use -Target.' 'карта TreeFrogUI не найдена (нет cubegm\usb_mode.sh ни на одном диске). Вставьте карту в картридер или укажите -Target.') }
}
$cg = Join-Path $Target 'cubegm'
$dstMode = Join-Path $cg 'usb_mode.sh'; $bakMode = Join-Path $cg 'usb_mode.sh.orig'
$dstMtp  = Join-Path $cg 'usb_mtp.sh';  $bakMtp  = Join-Path $cg 'usb_mtp.sh.orig'
$zhijack = Join-Path $cg 'zhijack.sh';  $bakZh   = Join-Path $cg 'zhijack.sh.orig-tfusbd'
$flagOn  = Join-Path $cg 'tfusbd.on';   $flagRemote = Join-Path $cg 'tfmtp.remote'
if (-not (Test-Path $dstMode)) { Die ("$dstMode " + (T 'not found - this is not a TreeFrogUI card.' 'не найден - это не карта TreeFrogUI.')) }
if (-not (Test-Path $dstMtp)) { Die (T 'cubegm\usb_mtp.sh is missing - this TreeFrogUI version has no built-in MTP mode.' 'на карте нет cubegm\usb_mtp.sh - в этой версии TreeFrogUI нет встроенного MTP-режима.') }
$ver = Get-Content (Join-Path $cg 'version.txt') -ErrorAction SilentlyContinue
Say ((T 'Card: ' 'Карта: ') + "$Target   TreeFrogUI: $ver") 'Cyan'

$patchedMode = Get-Sha $srcMode
$patchedMtp  = Get-Sha $srcMtp

# ---- zhijack.sh hook helpers ----
function Remove-Hook {
    if (-not (Test-Path $zhijack)) { return $false }
    $s = Read-Text $zhijack
    if (-not $s.Contains('tfusbd.on')) { return $false }
    $n = $s.Replace($hookText + "`n", '')
    if ($n -eq $s) { $n = $s.Replace($hookText, '') }
    if ($n -eq $s) { Say (T 'zhijack.sh: the tfusbd lines were edited by hand - remove them manually.' 'zhijack.sh: строки tfusbd изменены вручную - удалите их сами.') 'Yellow'; return $false }
    Write-Text $zhijack $n
    Remove-IfExists $bakZh | Out-Null
    return $true
}
function Add-Hook {
    if (-not (Test-Path $zhijack)) { Say (T 'zhijack.sh not found - autostart not installed (start tfusbd by hand: cubegm/tfusbd.sh start).' 'zhijack.sh не найден - автозапуск не установлен (запуск вручную: cubegm/tfusbd.sh start).') 'Yellow'; return }
    $s = Read-Text $zhijack
    if ($s.Contains('tfusbd.on')) { Say (T 'zhijack.sh: autostart already present (skipped).' 'zhijack.sh: автозапуск уже есть (пропускаю).') 'Green'; return }
    $anchor = "`nPICOARCH=/mnt/sdcard/cubegm/picoarch`n"
    $i = $s.IndexOf($anchor)
    if ($i -lt 0 -or $s.IndexOf($anchor, $i + 1) -ge 0) {
        Say (T 'zhijack.sh: insertion point (PICOARCH=...) not found exactly once - add the lines of patch\zhijack.hook by hand before the UI loop.' 'zhijack.sh: место вставки (PICOARCH=...) не найдено однозначно - добавьте строки из patch\zhijack.hook вручную перед циклом меню.') 'Yellow'
        return
    }
    if (-not (Test-Path $bakZh)) { Copy-Item -LiteralPath $zhijack -Destination $bakZh }
    Write-Text $zhijack ($s.Substring(0, $i + 1) + $hookText + "`n" + $s.Substring($i + 1))
    Say (T 'zhijack.sh: autostart added (backup: cubegm\zhijack.sh.orig-tfusbd).' 'zhijack.sh: автозапуск добавлен (резервная копия: cubegm\zhijack.sh.orig-tfusbd).') 'Green'
}

# ================= uninstall =================
if ($Uninstall) {
    if (Remove-Hook) { Say (T 'zhijack.sh: autostart removed.' 'zhijack.sh: автозапуск удалён.') 'Green' }
    foreach ($b in $bgFiles + @('tfusbd.on', 'tfmtp.remote')) { if (Remove-IfExists (Join-Path $cg $b)) { Say ("cubegm\$b " + (T 'removed' 'удалён')) 'Green' } }
    foreach ($pair in @(@($dstMtp, $bakMtp, $patchedMtp, 'usb_mtp.sh'), @($dstMode, $bakMode, $patchedMode, 'usb_mode.sh'))) {
        $dst, $bak, $ph, $name = $pair
        if (Test-Path $bak) {
            Copy-Item -LiteralPath $bak -Destination $dst -Force; Remove-Item -LiteralPath $bak -Force
            Say ("$name " + (T "restored from $name.orig" "восстановлен из $name.orig")) 'Green'
        } elseif ((Get-Sha $dst) -eq $ph) {
            Say ("$name " + (T 'is patched but there is no .orig backup. Take the original from the patch\ folder (v1.8.0_u only).' 'исправлен, но резервной копии .orig нет. Возьмите оригинал из папки patch\ (только для v1.8.0_u).')) 'Yellow'
        }
    }
    if (Remove-IfExists (Join-Path $cg 'tfmtp')) { Say (T 'cubegm\tfmtp removed (the stock mtp-server will be used).' 'cubegm\tfmtp удалён (будет использоваться штатный mtp-server).') 'Green' }
    Say (T 'Done. Safely eject the card.' 'Готово. Безопасно извлеките карту.') 'Cyan'
    exit 0
}

# ================= install =================
# ---- usb_mode.sh ----
$cur = Get-Sha $dstMode
if ($cur -eq $patchedMode) {
    Say (T 'usb_mode.sh: already patched (skipped).' 'usb_mode.sh: уже исправлен (пропускаю).') 'Green'
} elseif ($ORIG_MODE.ContainsKey($cur)) {
    if (-not (Test-Path $bakMode)) { Copy-Item -LiteralPath $dstMode -Destination $bakMode }
    Copy-Item -LiteralPath $srcMode -Destination $dstMode -Force
    Say ((T 'usb_mode.sh: replaced (was: ' 'usb_mode.sh: заменён (было: ') + $ORIG_MODE[$cur] + (T '; backup: cubegm\usb_mode.sh.orig)' '; резервная копия: cubegm\usb_mode.sh.orig)')) 'Green'
} elseif ($Force) {
    $b = "$dstMode.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $dstMode -Destination $b
    Copy-Item -LiteralPath $srcMode -Destination $dstMode -Force
    Say ((T 'usb_mode.sh: UNKNOWN version replaced (-Force). Backup: ' 'usb_mode.sh: НЕИЗВЕСТНАЯ версия заменена принудительно (-Force). Резервная копия: ') + $b) 'Yellow'
} else {
    Die ((T "usb_mode.sh on the card differs from v1.8.0_u (SHA-256 $cur).`nReplacing a different TreeFrogUI version wholesale could break its USB mode.`nOptions: (1) apply the edits by hand - README, 'Manual install';`n         (2) apply patch\usb_mode.sh.patch (git apply / patch -p1);`n         (3) force it: install_tfmtp.ps1 -Force" `
            "usb_mode.sh на карте отличается от версии v1.8.0_u (SHA-256 $cur).`nЗамена целиком может сломать USB-режим другой версии TreeFrogUI.`nВарианты: (1) внести правки вручную - README.ru.md, раздел 'Ручная установка';`n          (2) применить patch\usb_mode.sh.patch (git apply / patch -p1);`n          (3) заменить принудительно: install_tfmtp.ps1 -Force"))
}

# ---- tfmtp ----
Copy-Item -LiteralPath (Join-Path $srcCg 'tfmtp') -Destination (Join-Path $cg 'tfmtp') -Force
Say (T 'cubegm\tfmtp: copied.' 'cubegm\tfmtp: скопирован.') 'Green'

# ---- background service ----
if ($NoBackground) {
    if (Remove-Hook) { Say (T 'zhijack.sh: autostart removed (-NoBackground).' 'zhijack.sh: автозапуск удалён (-NoBackground).') 'Green' }
    Remove-IfExists $flagOn | Out-Null
    foreach ($b in $bgFiles) { Remove-IfExists (Join-Path $cg $b) | Out-Null }
} else {
    foreach ($b in $bgFiles) { Copy-Item -LiteralPath (Join-Path $srcCg $b) -Destination (Join-Path $cg $b) -Force }
    Say (T 'cubegm\tfusbd, tfusbd.sh, tfkey: copied.' 'cubegm\tfusbd, tfusbd.sh, tfkey: скопированы.') 'Green'
    $m = Get-Sha $dstMtp
    if ($m -eq $patchedMtp) {
        Say (T 'usb_mtp.sh: already patched (skipped).' 'usb_mtp.sh: уже исправлен (пропускаю).') 'Green'
    } elseif ($ORIG_MTP.ContainsKey($m)) {
        if (-not (Test-Path $bakMtp)) { Copy-Item -LiteralPath $dstMtp -Destination $bakMtp }
        Copy-Item -LiteralPath $srcMtp -Destination $dstMtp -Force
        Say (T 'usb_mtp.sh: the USB (MTP) menu item now just returns to the menu while tfusbd runs.' 'usb_mtp.sh: пункт меню USB (MTP) при работающей службе просто возвращает в меню.') 'Green'
    } else {
        Say (T 'usb_mtp.sh: unknown version, left as is (tfusbd still takes over a menu-started MTP session).' 'usb_mtp.sh: неизвестная версия, оставлен как есть (tfusbd всё равно перехватит MTP-сеанс из меню).') 'Yellow'
    }
    Add-Hook
    Touch $flagOn
    Say (T 'cubegm\tfusbd.on: background MTP enabled (delete this file to disable).' 'cubegm\tfusbd.on: фоновый MTP включён (удалите файл, чтобы выключить).') 'Green'
}

# ---- remote control ----
if ($Remote) {
    Touch $flagRemote
    Say (T 'cubegm\tfmtp.remote: REMOTE CONTROL ENABLED - any PC this console is plugged into can run commands as root (pc\r36.py).' 'cubegm\tfmtp.remote: УДАЛЁННОЕ УПРАВЛЕНИЕ ВКЛЮЧЕНО - любой ПК, к которому подключена консоль, может выполнять команды от root (pc\r36.py).') 'Yellow'
} elseif (Remove-IfExists $flagRemote) {
    Say (T 'cubegm\tfmtp.remote removed: remote control disabled (use -Remote to enable).' 'cubegm\tfmtp.remote удалён: удалённое управление выключено (включить: -Remote).') 'Green'
}

# ---- verify ----
$ok = ((Get-Sha (Join-Path $cg 'tfmtp')) -eq (Get-Sha (Join-Path $srcCg 'tfmtp'))) -and ((Get-Sha $dstMode) -eq $patchedMode)
if (-not $NoBackground) { foreach ($b in $bgFiles) { $ok = $ok -and ((Get-Sha (Join-Path $cg $b)) -eq (Get-Sha (Join-Path $srcCg $b))) } }
if (-not $ok) { Die (T 'checksums do not match after copying. Check the card and retry.' 'контрольные суммы после копирования не совпали. Проверьте карту и повторите.') }
if ($Target -match '^[A-Za-z]:\\?$') { try { Write-VolumeCache -DriveLetter $Target.Substring(0,1) -ErrorAction Stop } catch {} }
Say (T 'SHA-256 check: OK. Installation complete.' 'Проверка SHA-256: OK. Установка завершена.') 'Cyan'
if ($NoBackground) {
    Say (T 'Next: eject the card, put it in the console, TreeFrogUI menu -> USB (MTP), connect the cable to the PC.' 'Дальше: извлеките карту, вставьте в консоль, меню TreeFrogUI -> USB (MTP), подключите кабель к ПК.') 'Cyan'
} else {
    Say (T 'Next: eject the card, put it in the console and switch it on. Plug the cable into the OTG port: the console appears on the PC by itself within a few seconds, while you keep using the menu and games.' 'Дальше: извлеките карту, вставьте в консоль и включите. Подключите кабель к порту OTG: консоль сама появится на ПК через несколько секунд, а меню и игры продолжают работать.') 'Cyan'
}
