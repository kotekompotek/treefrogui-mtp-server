# Changelog

## v2.0.1 — 2026-11-10

- **tfusbd**: the MTP server's per-request log went to `/tmp/tfmtp.log`, which is RAM on the console and grew without limit (about 1 MB in 20 minutes of browsing). It now goes to `/dev/null`, or to `log.txt` in the SD root when that file exists (the usual TreeFrogUI debug switch).

## v2.0.0 — 2026-11-10

Background MTP and remote control. Write-up: [docs/BACKGROUND.md](docs/BACKGROUND.md).

- **tfusbd** (new): background service started at boot (opt-in file `cubegm/tfusbd.on`, two lines added to `cubegm/zhijack.sh`).
  - Switches the OTG port between host (mouse, pad, flash drive) and device (PC) on its own.
  - Detects the PC from the MUSB FRAME (SOF) counter: on this board VBUS always reads valid and the UDC state stays `configured` after an unplug.
  - Runs `tfmtp` with `SCHED_IDLE`, so transfers do not take CPU time from games.
  - Takes over a session started from the USB (MTP) menu item the same way the B button ends it (SIGKILL left the display black until reboot).
  - 0 % CPU when idle; started from RAM so the SD card is never kept busy.
- **tfmtp 1.2**: optional remote shell over MTP vendor operations 0x9A00–0x9A04 (exec / read / write / signal / info), only when `cubegm/tfmtp.remote` exists. Jobs run with normal scheduling.
- **tfkey** (new): presses console buttons through cubevol's `/tmp/joy_key` shared memory.
- **usb_mtp.sh**: returns to the menu immediately while tfusbd is running.
- **pc/r36.py** (new): Windows client — `info`, `sh`, `shell`, `ls`, `put`, `get`, `rm`, `key`, `shot`, `reboot`. Uses the stock MTP driver (WPD MTP extension commands); **pc/fbshot.py**: screenshots.
- **Installer**: installs the service by default; `-Remote` (or `install_remote.bat`) enables remote control; `-NoBackground` keeps the v1.0 behaviour; uninstall restores `usb_mode.sh`, `usb_mtp.sh` and `zhijack.sh` byte for byte.
- Finding: the DC port of this board is charge-only; MTP works on the OTG port only.

## v1.0.0 — 2026-11-08

First release.

- **tfmtp**: new MTP responder for TreeFrogUI with lazy folder enumeration. It answers the PC immediately instead of indexing the whole SD card first; the stock `mtp-server` needs ~167 s for 34k files, while Windows gives up after 30 s.
- **usb_mode.sh** (TreeFrogUI v1.8.0_u):
  - uses `cubegm/tfmtp` when present;
  - binds USB only once the responder is ready;
  - switches the controller role right before binding, which fixes "device descriptor request failed";
  - optional deep tracing when `log.txt` is in the SD root.
- Windows installer/uninstaller with SHA-256 verification and version check.
- PC-side diagnostics: device monitor, USBPcap capture, MTP timeline decoder, automated speed and integrity test.
- Tested on a HiChip HC16xx R36S clone (TreeFrogUI v1.8.0_u, GB350 profile) with Windows 10 22H2.