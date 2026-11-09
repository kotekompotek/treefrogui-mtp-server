# Changelog

## v2.1.2 — 2026-11-10

- **tfusbd frees ~5 MB of unswappable RAM at boot.** The RAM copies of `/bin /sbin /lib /usr /etc` hidden under TreeFrogUI's SD bind mounts and the stock "game corrupted" bitmaps are deleted from the initramfs. Unevictable 14,140 → 9,200 kB; MemAvailable ~19 MB in the menu.
- **tfmtp runs at nice 19 instead of `SCHED_IDLE`.** Under a game using 100 % of the CPU, `SCHED_IDLE` starved MTP and Windows dropped the device with timeouts.

## v2.1.1 — 2026-11-10

- **tfusbd: frees RAM that picoarch leaks.** picoarch extracts zipped ROMs to `/tmp/pa-<name>` (tmpfs, i.e. RAM) and never deletes them. On a 43 MB console one or two games were enough for the next one to be killed by the OOM killer: pcsx4all died at start with an 8 MB GBA ROM still in `/tmp`. Every 10 s, while no game runs, tfusbd now deletes `/tmp/pa-*` files that no process has open or mapped, and logs what it freed.

## v2.1.0 — 2026-11-10

Gameplay recording. Write-up: [docs/BACKGROUND.md §12](docs/BACKGROUND.md#12-recording-video-and-sound-v21).

- **tfshim** (new): a layer with the same exports as the console's display/sound driver (`driver_gb350.so`, 117 functions + 7 variables). It forwards everything through 8-instruction trampolines and copies frames (`video_driver_disp_frame`) and audio (`sound_driver_playframe`) into shared memory while a recording runs; otherwise each call costs 18 instructions. Enabled for picoarch by `PICOARCH_DRIVER` in the `zhijack.sh` autostart lines when `cubegm/tfshim.on` exists (GB350 only).
- **tfrec** (new): lossless delta + RLE compression of frames, 48 kHz audio, streamed to the PC over the remote-control channel.
- **pc/r36rec.py** (new) + `tfcodec.dll`: records an MP4 (H.264 + AAC) with ffmpeg, A/V-synced by timestamps.
- **Installer**: `-Record` (included in `install_remote.bat`); updates the v2.0 autostart lines in place.
- Measured: Moonwalker (Mega Drive), 320×240 at 30 fps, 3 of 398 frames lost, audio lossless, no stutter noticed.

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