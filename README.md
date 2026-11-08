# treefrogui-mtp-server

[![build](https://github.com/kotekompotek/treefrogui-mtp-server/actions/workflows/build.yml/badge.svg)](https://github.com/kotekompotek/treefrogui-mtp-server/actions/workflows/build.yml)
[![release](https://img.shields.io/github/v/release/kotekompotek/treefrogui-mtp-server)](https://github.com/kotekompotek/treefrogui-mtp-server/releases/latest)
[![license: MIT](https://img.shields.io/badge/tfmtp-MIT-blue)](LICENSE)

**Working USB file transfer (MTP) for [TreeFrogUI](https://github.com/tzubertowski/TreeFrogUI) handhelds.** Connect the console to a PC with a cable and copy games, saves and any other files. No card reader needed.

**[Русская версия →](README.ru.md)**

---

## The problem

TreeFrogUI ships a built-in **USB (MTP)** mode, but on a real SD card it does not work. Windows detects a "USB MTP device", installs its driver, and then **nothing appears in Explorer**. The upstream issue ([#48](https://github.com/tzubertowski/TreeFrogUI/issues/48)) was closed as *won't fix*.

The cause, measured on both ends of the cable:

- The stock `cubegm/mtp-server` **walks the entire SD card** before it reads its first command from the PC. On a card with 34,036 files this takes **167 seconds** at 100 % CPU.
- Windows waits **30 seconds** for the answer to `OpenSession`. Then it cancels, logs *"driver start failed" (HRESULT 0x802A0006)*, and never retries until the cable is replugged.

```
PC   22:44:32  OpenSession ──►            (no answer)          22:45:02  cancel, "driver start failed"
SD           mtp-server: scanning MAME… roms… cubegm/cheat… ─────────────►  167 s later: "OK" — nobody listening
```

## The fix

**`tfmtp`** is a small MTP server written from scratch that replaces the stock one:

- **Lazy listing.** A folder is read only when the PC opens it, the way modern Android phones work. It answers the PC immediately, however many files the card holds.
- Shows up in Explorer as **R36S → SD card** about **0.5 s** after the USB link comes up.
- Supports **browse, copy both ways, create folders, rename, delete**. UTF-8 / Cyrillic file names work.
- A single static MIPS binary, **104 KB**, no dependencies. Uses ~0.3 MB of RAM (stock: ~8 MB).
- Logs every MTP operation, with timings, when debug logging is on.

A small patch to TreeFrogUI's `usb_mode.sh` makes the built-in **USB (MTP)** menu item use `tfmtp`. It also connects USB only once the server is ready. The menu, the on-screen messages and **B to exit** stay exactly as they were.

## Tested

Clone of the R36S on a **HiChip HC16xx** (MIPS32 LE, Linux 4.4.186), **TreeFrogUI v1.8.0_u** (device profile GB350), 16 GB FAT32 card with ~34,000 objects, **Windows 10 22H2**.

| | stock `mtp-server` | `tfmtp` |
|---|---|---|
| Ready to answer the PC | after 167 s | **immediately** |
| Shows up in Explorer | never | **~0.5 s after connect** |
| First session | — | 930 requests, **0 errors** |
| Open folder: 34 / 109 / 2,908 items | — | instant / 1.3 s / 52 s |
| 24 MB console → PC | — | **9.8 MB/s**, SHA-256 match |
| 24 MB PC → console | — | **3.3 MB/s**, SHA-256 match |
| RAM (RSS) | 8.3 MB | **0.3 MB** |

Also verified: Cyrillic file names, copying into subfolders, exit with **B**. The full list is in [README.ru.md §5](README.ru.md#5-что-было-протестировано). Not tested on real hardware yet: Linux/macOS hosts, other TreeFrogUI versions. Folder create, rename and delete pass the protocol self-test but were not clicked through in Explorer on the console.

## Install

**You need:** a microSD card reader, and a USB cable that carries data (not a charge-only cable).

1. Download **`treefrogui-mtp-server-v1.0.0.zip`** from [Releases](https://github.com/kotekompotek/treefrogui-mtp-server/releases/latest) and unzip it.
2. Turn the console off and put its SD card into the PC.
3. **Windows:** run `install\install.bat`. It:
   - finds the TreeFrogUI card;
   - checks that `cubegm/usb_mode.sh` is the stock v1.8.0_u (by SHA-256);
   - backs it up as `usb_mode.sh.orig`;
   - installs the patched script and `tfmtp`;
   - verifies the checksums.

   **Other OS:** back up `cubegm/usb_mode.sh`, then copy `sdcard/cubegm/tfmtp` and `sdcard/cubegm/usb_mode.sh` onto the card's `cubegm/` folder.
4. Eject the card and put it back into the console.

**A different TreeFrogUI version?** The installer refuses to overwrite a `usb_mode.sh` it does not recognise. Apply [`patch/usb_mode.sh.patch`](patch/usb_mode.sh.patch) instead (`git apply` / `patch -p1` from the card root), or make the three small edits by hand, described in [README.ru.md §3.3](README.ru.md#33-ручная-установка-на-другую-версию-treefrogui-3-правки). The first edit alone, "use `cubegm/tfmtp` if present", is the key one.

**Uninstall:** `install\uninstall.bat`, or delete `cubegm/tfmtp` and restore `usb_mode.sh.orig`.

> ⚠️ A TreeFrogUI update may overwrite `cubegm/usb_mode.sh`. Re-run the installer afterwards.

## Use

TreeFrogUI menu → **USB (MTP)** → plug the cable in → **R36S** appears in *This PC* within a couple of seconds. Drag files in both directions. Press **B** on the console to leave USB mode.

Large folders take a while to open: a folder with ~2,900 files takes about 50 s. Windows asks for each file's properties one by one, and the console kernel's FAT driver searches folders linearly. Splitting big ROM sets into subfolders helps.

## Troubleshooting

- **Debug log.** Put an empty `log.txt` in the **root of the SD card**. Run USB mode, then read `log.txt`: every request is logged as `TFMTP <uptime> REQ … / RESP … -> 0x2001 OK (n ms)`, together with USB state, kernel messages and transfer speeds. **Delete `log.txt` afterwards**: it slows things down and grows quickly.
- *"Unknown USB device (device descriptor request failed)"* → the stock `usb_mode.sh` ordering issue; install the patched script.
- *"USB MTP device" in Device Manager but nothing in Explorer* → the stock `mtp-server` is still in use. Check that `cubegm/tfmtp` exists.
- PC-side tools ([`tools/`](tools)): USB device monitor, USBPcap capture, an MTP timeline decoder ("which request did the console not answer?"), and an automated speed and integrity test.

The full diagnosis, the design and the measurements are in **[docs/TECHNICAL.md](docs/TECHNICAL.md)**.

## Build

```sh
./build.sh                 # needs Zig ≥ 0.17 — builds sdcard/cubegm/tfmtp and runs the self-test
```

or manually:

```sh
zig cc -target mipsel-linux-musleabi -mcpu=mips32 -static -Os -s -o tfmtp src/tfmtp.c
zig cc -DTFMTP_TEST -o tfmtp_test src/tfmtp.c && ./tfmtp_test   # protocol self-test against a fake USB link
```

CI builds the MIPS binary and runs the self-test on every push.

## Repository layout

| Path | What |
|---|---|
| `src/tfmtp.c` | the MTP server (single C file) |
| `sdcard/cubegm/usb_mode.sh` | patched TreeFrogUI USB-mode script (v1.8.0_u base) |
| `patch/` | original `usb_mode.sh` v1.8.0_u + unified diff |
| `install/` | Windows installer / uninstaller |
| `tools/` | optional PC-side diagnostics (PowerShell) |
| `docs/` | technical write-up (EN / RU) |

## License

- **`tfmtp`** (`src/`, the compiled binary, `build.sh`, `install/`, `tools/`): [MIT](LICENSE) © 2026 Pavel Kotek. See [NOTICE.md](NOTICE.md).
- **`usb_mode.sh`**, both the patched and the original copy, is part of **TreeFrogUI** by Tomasz Zubertowski and contributors. It is redistributed with changes marked (`FIX (2026-11-08)`), under TreeFrogUI's license: **CC BY-NC-SA 4.0**, non-commercial use only.

Not affiliated with the TreeFrogUI project.
