# treefrogui-mtp-server

[![build](https://github.com/kotekompotek/treefrogui-mtp-server/actions/workflows/build.yml/badge.svg)](https://github.com/kotekompotek/treefrogui-mtp-server/actions/workflows/build.yml)
[![release](https://img.shields.io/github/v/release/kotekompotek/treefrogui-mtp-server)](https://github.com/kotekompotek/treefrogui-mtp-server/releases/latest)
[![license: MIT](https://img.shields.io/badge/tfmtp-MIT-blue)](LICENSE)

**Working USB file transfer (MTP) for [TreeFrogUI](https://github.com/tzubertowski/TreeFrogUI) handhelds, in the background, plus optional remote control from the PC.** Plug the console into a PC and copy games, saves and any other files while you keep playing. No card reader needed.

**[Русская версия →](README.ru.md)**

---

## What you get

- **MTP that works.** The stock MTP mode never shows up in Explorer on a real SD card; `tfmtp` appears as **R36S → SD card** within a second or two.
- **Background MTP (new in v2.0).** Plug the cable into the OTG port: the console appears on the PC in 2–4 s while the menu and games keep running. No menu item needed.
- **The OTG port keeps working.** The `tfusbd` service switches the port between host (mouse, pad, flash drive) and device (PC) by itself.
- **Games stay smooth.** MTP only gets CPU time the game does not need (`SCHED_IDLE`).
- **Remote control (optional, new in v2.0).** From the PC: Linux commands as root, files, button presses, screenshots, reboot with automatic reconnect — `pc\r36.py`.

How it was done, with measurements and dead ends: **[docs/BACKGROUND.md](docs/BACKGROUND.md)** (v2.0) and **[docs/TECHNICAL.md](docs/TECHNICAL.md)** (the original MTP fix).

## The original problem

TreeFrogUI ships a built-in **USB (MTP)** mode, but on a real SD card it does not work. Windows detects a "USB MTP device", installs its driver, and then **nothing appears in Explorer**. The upstream issue ([#48](https://github.com/tzubertowski/TreeFrogUI/issues/48)) was closed as *won't fix*.

- The stock `cubegm/mtp-server` **walks the entire SD card** before it reads its first command from the PC. On a card with 34,036 files this takes **167 seconds** at 100 % CPU.
- Windows waits **30 seconds** for the answer to `OpenSession`. Then it cancels, logs *"driver start failed" (HRESULT 0x802A0006)*, and never retries until the cable is replugged.

```
PC   22:44:32  OpenSession ──►            (no answer)          22:45:02  cancel, "driver start failed"
SD           mtp-server: scanning MAME… roms… cubegm/cheat… ─────────────►  167 s later: "OK" — nobody listening
```

**`tfmtp`** is a small MTP server written from scratch: a folder is read only when the PC opens it, the way modern Android phones work. A single static MIPS binary (113 KB), ~0.3 MB of RAM.

## Tested

Clone of the R36S on a **HiChip HC16xx** (MIPS32 LE, Linux 4.4.186), **TreeFrogUI v1.8.0_u** (device profile GB350), 16 GB FAT32 card with ~34,000 objects, **Windows 10 22H2**.

| | stock `mtp-server` | `tfmtp` (menu) | `tfmtp` + `tfusbd` (background, game running) |
|---|---|---|---|
| Shows up in Explorer | never | ~0.5 s after connect | 2–4 s after plugging the cable |
| First session | — | 930 requests, 0 errors | — |
| 24 MB console → PC | — | 9.8 MB/s | 7.3–7.6 MB/s |
| 24 MB PC → console | — | 3.3 MB/s | 1.7–2.1 MB/s |
| Game stutter during a transfer | — | (menu mode, no game) | none noticed with `SCHED_IDLE` |
| SHA-256 of copied files | — | match | match |

Also verified: Cyrillic file names, exit with **B** (menu mode), mouse on the OTG port detected and released, remote reboot back online in 27 s, remote START press paused a game. Not tested yet: Linux/macOS hosts, other TreeFrogUI versions and device profiles, a flash drive on OTG while the service runs.

**Only the OTG port carries data.** On this board the DC port is charge-only (measured, see [BACKGROUND.md §3](docs/BACKGROUND.md#3-which-port-can-be-a-usb-device)).

## Install

**You need:** a microSD card reader, and a USB cable that carries data (not a charge-only cable).

1. Download **`treefrogui-mtp-server-v2.0.0.zip`** from [Releases](https://github.com/kotekompotek/treefrogui-mtp-server/releases/latest) and unzip it.
2. Turn the console off and put its SD card into the PC.
3. **Windows:** run one of
   - `install\install.bat` — MTP fix + background MTP (recommended);
   - `install\install_remote.bat` — the same plus remote control from the PC (read *Security* below);
   - `install\install.bat -NoBackground` — only the v1.0 MTP fix, used from the USB (MTP) menu item.

   The installer finds the TreeFrogUI card, checks `cubegm/usb_mode.sh` and `usb_mtp.sh` against the stock v1.8.0_u by SHA-256, keeps backups (`*.orig`), copies `tfmtp`, `tfusbd`, `tfusbd.sh`, `tfkey`, adds two autostart lines to `cubegm/zhijack.sh` ([`patch/zhijack.hook`](patch/zhijack.hook)), creates `cubegm/tfusbd.on` and verifies the checksums.
4. Eject the card and put it back into the console.

**Other OS / by hand:** copy `sdcard/cubegm/*` into the card's `cubegm/` (back up `usb_mode.sh` and `usb_mtp.sh` first), insert the lines of `patch/zhijack.hook` into `cubegm/zhijack.sh` right before the line `PICOARCH=/mnt/sdcard/cubegm/picoarch`, and create an empty `cubegm/tfusbd.on`. Keep LF line endings.

**A different TreeFrogUI version?** The installer refuses to overwrite a `usb_mode.sh` it does not recognise. Apply [`patch/usb_mode.sh.patch`](patch/usb_mode.sh.patch) instead (`git apply` / `patch -p1` from the card root), or make the edits by hand, described in [README.ru.md §3.3](README.ru.md#33-ручная-установка-на-другую-версию-treefrogui-3-правки).

**Uninstall:** `install\uninstall.bat` restores `usb_mode.sh`, `usb_mtp.sh` and `zhijack.sh` and removes everything this package added.

> ⚠️ A TreeFrogUI update may overwrite `cubegm/usb_mode.sh`, `usb_mtp.sh` and `zhijack.sh`. Re-run the installer afterwards.

## Use

**Background (default):** switch the console on, plug the PC cable into the **OTG** port, and **R36S** appears in *This PC* within a few seconds. Keep playing. To use a mouse, pad or flash drive, plug it in through the OTG adapter instead: the service switches the port by itself. To turn background MTP off, delete `cubegm/tfusbd.on`.

**Menu (v1.0 way):** TreeFrogUI menu → **USB (MTP)** → plug the cable in; press **B** to leave. While the background service runs, this menu item simply returns to the menu.

Large folders take a while to open: ~50 s for ~2,900 files. Windows asks for each file's properties one by one, and the console kernel's FAT driver searches folders linearly. Splitting big ROM sets into subfolders helps.

### Remote control

Installed with `install_remote.bat` (the file `cubegm/tfmtp.remote`). The PC needs Python 3 and `comtypes` (`pip install comtypes`). It talks to the console through the stock Windows MTP driver (WPD vendor operations), so no extra driver is needed and Explorer can stay open.

```bat
python pc\r36.py info  & rem version and state
python pc\r36.py sh "uname -a; df -h"  & rem any Linux command, as root
python pc\r36.py shell  & rem interactive, one command per line
python pc\r36.py ls /roms
python pc\r36.py put game.zip /roms/FC/game.zip
python pc\r36.py get /cubegm/logs/zhijack.log zhijack.log
python pc\r36.py key press START  & rem UP DOWN LEFT RIGHT A B X Y L1 R1 START SELECT
python pc\r36.py key seq "A 100, 500, B 100"  & rem button ms, pause ms, ...
python pc\r36.py shot screen.png  & rem screenshot
python pc\r36.py reboot  & rem reboot and wait until the console is back
```

> ⚠️ **Security.** With `cubegm/tfmtp.remote` present, **any PC the console is plugged into gets root on it.** Do not enable remote control if you plug the console into computers you do not trust. Delete the file to turn it off.

## Troubleshooting

- **Service log:** `python pc\r36.py sh "/mnt/sdcard/cubegm/tfusbd.sh status"` (or `/tmp/tfusbd.log` on the console). Lines like `PC detected`, `PC gone`, `USB device attached`.
- **Debug log of the MTP server:** put an empty `log.txt` in the **root of the SD card** and use the menu USB (MTP) mode; every request is logged as `TFMTP <uptime> REQ … / RESP … -> 0x2001 OK (n ms)`. **Delete `log.txt` afterwards**: it slows things down and grows quickly.
- *"Unknown USB device (device descriptor request failed)"* → the stock `usb_mode.sh` ordering issue; install the patched script.
- *"USB MTP device" in Device Manager but nothing in Explorer* → the stock `mtp-server` is still in use. Check that `cubegm/tfmtp` exists.
- Nothing happens on the DC port: expected, it has no data lines. Use the OTG port.
- PC-side tools ([`tools/`](tools)): USB device monitor, USBPcap capture, an MTP timeline decoder ("which request did the console not answer?"), and an automated speed and integrity test.

## Build

```sh
./build.sh                 # needs Zig >= 0.17 — builds sdcard/cubegm/{tfmtp,tfusbd,tfkey} and runs the tfmtp self-test
```

or manually:

```sh
zig cc -target mipsel-linux-musleabi -mcpu=mips32 -static -Os -s -o tfmtp  src/tfmtp.c
zig cc -target mipsel-linux-musleabi -mcpu=mips32 -static -Os -s -o tfusbd src/tfusbd.c
zig cc -target mipsel-linux-musleabi -mcpu=mips32 -static -Os -s -o tfkey  src/tfkey.c
zig cc -DTFMTP_TEST -o tfmtp_test src/tfmtp.c && ./tfmtp_test   # protocol self-test against a fake USB link
```

The builds are reproducible. CI builds the MIPS binaries and runs the self-test on every push.

## Repository layout

| Path | What |
|---|---|
| `src/tfmtp.c` | the MTP server, with the optional remote-control operations |
| `src/tfusbd.c` | background service: OTG host/device switching, PC detection, keeps `tfmtp` running |
| `src/tfkey.c` | button injection through cubevol's `/tmp/joy_key` shared memory |
| `sdcard/cubegm/` | `tfusbd.sh` (start/stop/status), patched `usb_mode.sh` and `usb_mtp.sh` (v1.8.0_u base) |
| `patch/` | original `usb_mode.sh` / `usb_mtp.sh` v1.8.0_u, unified diff, the `zhijack.sh` autostart lines |
| `install/` | Windows installer / uninstaller |
| `pc/` | `r36.py` remote control client, `fbshot.py` screenshots (Windows, Python 3 + comtypes) |
| `tools/` | optional PC-side USB diagnostics (PowerShell) |
| `docs/` | technical write-ups (EN / RU) |

## License

- **`tfmtp`, `tfusbd`, `tfkey`, `tfusbd.sh`, `pc/`, `install/`, `tools/`, `build.sh`:** [MIT](LICENSE) © 2026 Pavel Kotek. See [NOTICE.md](NOTICE.md).
- **`usb_mode.sh`, `usb_mtp.sh`** (patched and original copies) and the lines inserted into **`zhijack.sh`** belong to **TreeFrogUI** by Tomasz Zubertowski and contributors. They are redistributed with changes marked, under TreeFrogUI's license: **CC BY-NC-SA 4.0**, non-commercial use only.

Not affiliated with the TreeFrogUI project. Upstream pull requests with these changes: [TreeFrogUI#104](https://github.com/tzubertowski/TreeFrogUI/pull/104) (MTP fix) and [TreeFrogUI#108](https://github.com/tzubertowski/TreeFrogUI/pull/108) (background service, remote control).
