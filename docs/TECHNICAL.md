# tfmtp — technical write-up

Why TreeFrogUI's built-in MTP did not work, how the fix works, how to build it, and how to repeat the diagnosis on another console. Installation: [README.md](../README.md). [Русская версия](TECHNICAL.ru.md).

---

## 1. System

| Component | Value |
|---|---|
| SoC | HiChip HC16xx, MIPS32 little-endian, ~43 MB RAM visible to Linux (`MemTotal: 43160 kB`), 128 MB swap in `cubegm/pagefile.sys` |
| Kernel | `Linux 4.4.186-release #23 PREEMPT ... mips` |
| Firmware | TreeFrogUI v1.8.0_u on top of the stock CubeGM firmware, device profile `GB350` |
| USB | two MUSB OTG controllers: `usb@18844000` → `musb-hdrc.0.auto` (the PC-facing port), `usb@18850000` → `musb-hdrc.1.auto`; both boot in host mode (`b_idle`) |
| Role switch | `/sys/devices/platform/soc/18844000.usb/musb-hdrc.0.auto/mode` ← `peripheral` (reads back as `b_peripheral`) |
| Gadget | configfs + `libcomposite`; MTP function `usb_f_mtp.ko` (the Android `f_mtp` driver) from `cubegm/modules/4.4.186-release/` |
| MTP node | `/dev/mtp_usb`, misc `10, 58`, created by `mkdir functions/mtp.usb0` |
| SD card | 16 GB microSD, FAT32 (`vfat`, `iocharset=utf8`), mounted at `/mnt/sdcard`, ~34,000 objects |

Stock TreeFrogUI chain: USB menu item → `cubegm/usb_mtp.sh` → `cubegm/usb_mode.sh mtp` → `run_mtp_mode()`, which does the following:

1. Builds the configfs gadget: VID/PID `18D1:4E22`, Microsoft OS descriptors, `compatible_id=MTP`.
2. Switches the role to `peripheral` and binds the UDC.
3. Starts `cubegm/mtp-server /mnt/sdcard` plus `cubegm/usb_exit_watcher <pid>`. The watcher reads the buttons from `cubevol`'s SysV shared memory (`ftok("/tmp/joy_key",'a')`, 4 bytes, B = bit 14 `0x4000`) and kills the server when B is pressed.

---

## 2. Finding the cause

### 2.1 Symptom

- Windows shows a "USB MTP device" (`USB\VID_18D1&PID_4E22`), and the inbox driver (`wpdmtp.inf`, service `WUDFWpdMtp`) installs without errors.
- Nothing appears in Explorer.
- `Microsoft-Windows-WPD-MTPClassDriver/Operational` logs two events:
  - event 1007: *"device does not respond to operation **0x1002** … attempting to cancel; HRESULT 0x802A0006"*;
  - event 1006: *"driver start failed, HRESULT 0x802A0006"*.

### 2.2 Instrumentation

- **PC side:**
  - USBPcap + tshark for raw USB packets;
  - the `WPD-MTPClassDriver` (Operational + Analytic), `DriverFrameworks-UserMode` and `Kernel-PnP` event logs;
  - a device-arrival monitor.

  All of these are in [`tools/`](../tools).
- **Console side:** tracing added to `usb_mode.sh`, enabled by a `log.txt` file in the SD root. Every 2 s it records, for the server process:
  - each thread's state, kernel wait channel (`wchan`), current syscall and CPU ticks;
  - its open files (which shows the directory being scanned), RSS, free RAM and swap;
  - the UDC state and new `dmesg` lines.

### 2.3 Timeline (one session, seen from both ends)

| PC (USBPcap + driver log) | Console (`log.txt`) |
|---|---|
| 22:44:32.194 — bulk OUT 16 bytes: **OpenSession** (`0x1002`, tid 0, SessionID 1), transfer completed OK | `mtp-server` in state `R`, 100 % CPU, `wchan=0`, holding `/mnt/sdcard/MAME`, then `roms/*`, `cubegm/cheat/*` open: **walking the whole card** |
| 22:45:02.300 — after 30 s: `GetDeviceStatus` (class request 0x67), pending bulk IN cancelled (`USBD_STATUS_CANCELED 0xC0010000`), "driver start failed" | still walking |
| 22:47:14 — cable replugged → new OpenSession, cancelled again after 30 s | still walking |
| — (Windows sends nothing more) | **167 s** after start: `MTP indexed 34036 objects under /mnt/sdcard`, then `MTP_REQ op=1002` → `MTP_RESP op=1002 code=2001` (OK): the answer goes nowhere |
| — | then 5 minutes in `S`, `wchan=mtp_read`: the server waits for commands that never come |

**Conclusions:**

- The USB hardware, the `f_mtp` driver and the protocol all work: the server eventually answers correctly.
- The stock `mtp-server` (closed source, based on old Android `MtpServer` code) **indexes the whole card first**, at about 200 objects/s on this CPU, and only then reads its first command.
- Windows waits ~30 s for OpenSession and does not retry until the cable is replugged.

Memory is not a factor: the server's RSS is ~8 MB and swap is unused.

### 2.4 Side trap: "Unknown USB device"

The first attempt at a fix ("bind USB only after indexing") made Windows report *"device descriptor request failed"* (`USB\VID_0000&PID_0002`). The cause: the role was switched to `peripheral` before the gadget was bound. MUSB already pulls D+ up, the PC starts enumeration, and nothing answers the descriptor requests. So the role must be switched **right before** writing `UDC`. Until then the controller stays in host mode, and the PC sees nothing at all.

---

## 3. The fix

### 3.1 tfmtp: an MTP server with lazy enumeration

A single C file ([`src/tfmtp.c`](../src/tfmtp.c), ~1000 lines), no dependencies, statically linked for MIPS. Invoked like the stock server: `tfmtp <root>`.

**Lazy handles.**

- An object gets its MTP handle only when the PC lists the folder that contains it (`GetObjectHandles`, or `GetObjectPropList` with depth = 1).
- The object table holds `{parent, name, is_dir, deleted}`, with a hash on (parent, name), so listing a folder again returns the same handles.
- Full paths are rebuilt by walking up the parents.
- Size and dates come from `stat()` at request time.

**Transport: the stock Android `f_mtp` interface.**

- Commands and small data phases: `read()`/`write()` on `/dev/mtp_usb` with a 16,384-byte buffer (the driver's `mtp_rx_req_len` limit).
- Sending a file to the PC: `ioctl(MTP_SEND_FILE_WITH_HEADER = 0x80204D04, struct mtp_file_range)`. The kernel builds the container header and handles the ZLP. The ioctl number and the 32-byte struct size were cross-checked against the stock `mtp-server`'s machine code (`lui 0x8020` + `addiu 0x4D01/0x4D03/0x4D04`).
- Receiving a file from the PC: a `read()` loop in 16 KB chunks, written to the file. The data phase is **always** drained completely, even when writing fails, to keep the protocol in sync. Using `MTP_RECEIVE_FILE (0x80204D01)` is a possible speed-up.

**Operations** (advertised in `GetDeviceInfo`):

| Group | Operations |
|---|---|
| Session and device | `GetDeviceInfo`, `OpenSession`, `CloseSession`, `GetDevicePropDesc`/`GetDevicePropValue` (only `0xD402` DeviceFriendlyName = "R36S") |
| Storage | `GetStorageIDs` (one, `0x00010001`), `GetStorageInfo` (`statvfs`, removable RAM, hierarchical FS) |
| Enumeration | `GetNumObjects`, `GetObjectHandles`, `GetObjectInfo`, `GetObjectReferences` (always empty) |
| Read | `GetObject`, `GetPartialObject` |
| Write | `SendObjectInfo` (format `0x3001` → immediate `mkdir`), `SendObject`, `DeleteObject` (recursive), `SetObjectPropValue` (rename via `0xDC07`/`0xDC44`) |
| Properties | `GetObjectPropsSupported`, `GetObjectPropDesc`, `GetObjectPropValue`, `GetObjectPropList` (depth 0 and 1; groups and depth > 1 answer `0xA805`/`0xA808`) |

- **Object properties:** StorageID, ObjectFormat, ProtectionStatus, ObjectSize (u64), ObjectFileName (writable), DateCreated, DateModified, ParentObject, PersistentUID, Name.
- **Formats:** Undefined, Association (folder), text, WAV, MP3, AVI, JPEG, BMP, GIF, PNG and MP4, chosen by file extension.
- **Strings:** UTF-8 file names (FAT is mounted with `utf8`) ↔ UTF-16LE MTP strings, including surrogate pairs.
- **Vendor extension:** `microsoft.com: 1.0;` (VendorExtensionID 6).

**Logging.** Every operation goes to stderr (`TFMTP <uptime> REQ/RESP …`, with processing time and transfer speed). `usb_mode.sh` sends stderr to `/mnt/sdcard/log.txt` only if that file exists, otherwise to `/dev/null`. Timestamps use `CLOCK_MONOTONIC`, so they line up with uptime and `dmesg`.

### 3.2 Changes to `usb_mode.sh`

Full diff: [`patch/usb_mode.sh.patch`](../patch/usb_mode.sh.patch). It has 5 hunks and was verified with `git apply` and `patch -p1` against the stock v1.8.0_u.

1. **Server selection:** use `cubegm/tfmtp` when it exists and is executable, otherwise the stock `mtp-server`. `TF_USB_MTP_RESPONDER` still overrides both.
2. **Start order:**
   1. build the gadget while still in host role;
   2. start the server and the B-button watcher;
   3. wait until the server's `/proc/<pid>/wchan` reads `mtp_read`, meaning it is ready for commands. Meanwhile the screen shows *"Preparing MTP: scanning SD card files… N s (B = cancel)"* every 10 s; the wait is capped at 900 s (`TF_USB_MTP_INDEX_TIMEOUT`);
   4. only then switch to `peripheral` and bind the UDC.

   If the server exits during the wait (B pressed), USB is never enabled. With `tfmtp` the wait takes 0 s.
3. **Tracing** (`mtp_trace_init/tick/kmsg`): active only when `log.txt` exists; otherwise these functions return immediately.

---

## 4. Building

Requires [Zig](https://ziglang.org/), which bundles clang and musl for MIPS. Tested with Zig 0.17.0 on Windows; CI uses Linux.

```sh
# console: static MIPS32 LE, soft-float (no dependency on the card's libraries)
zig cc -target mipsel-linux-musleabi -mcpu=mips32 -static -Os -s -o tfmtp src/tfmtp.c

# host self-test: the same protocol code against a fake USB link and a scratch folder
zig cc -DTFMTP_TEST -o tfmtp_test src/tfmtp.c && ./tfmtp_test   # → "SELF-TEST: all checks passed"
# on Windows add: -Dstrcasecmp=_stricmp
```

The self-test runs 21 checks:

- `GetDeviceInfo` → `OpenSession` → storage queries;
- listing the root and `GetObjectInfo`;
- `GetObjectPropList` with depth = 1;
- reading a 40,000-byte file, and a partial read;
- creating a folder, uploading 70,000 bytes in 16 KB packets under a Cyrillic name, reading it back and comparing byte for byte;
- renaming, deleting the folder, checking that the deleted handle is invalid, and an unknown operation.

`-target mipsel-linux-musl` (without `eabi`) fails in Zig 0.17 with "unable to provide libc". Use `musleabi` or `musleabihf`. Soft-float `musleabi` was chosen because the SoC's FPU is unknown, and tfmtp uses floating point only for log formatting.

The build is reproducible: compiling the released source gives a byte-identical binary.

---

## 5. Results on the console

Windows 10, cable connected directly to the PC:

| Metric | stock `mtp-server` | `tfmtp` |
|---|---|---|
| Ready after start | 167 s (indexing 34,036 objects) | 0 s |
| Windows opens the session | never (30 s timeout) | ~0.5 s after the USB bind |
| Errors in the first session | — | 0 of 930 requests |
| Server RSS | ~8.3 MB | ~0.3 MB |
| Root (34) / `roms` (109) / `roms\FC` (2,908) | — | instant / ~1.3 s / ~52 s |
| 24 MB to the console | — | 7.3 s server-side (**3.3 MB/s**) |
| 24 MB to the PC | — | 2.4 s server-side (**9.8 MB/s**), SHA-256 match |

**Why large folders are slow.** Analysis of the `roms\FC` session: 17,456 requests in 59 s.

- For each object, Windows sends `GetObjectPropList` for `0xDC02`, `0xDC03` and `0xDC04`, then `GetObjectInfo`, `GetObjectPropList(all)` and `GetObjectReferences`: 6 requests per object. It does not use depth = 1 to fetch them in bulk.
- Server time is 41 of the 59 s, almost all of it in the first `stat()` of each file: `GetObjectPropList` averages 2.9 ms, while the `GetObjectInfo` that follows takes 0.09 ms.
- `vfat_lookup` → `fat_search_long` scans the directory from the start for every name. Each lookup costs O(position), so listing a whole folder costs O(n²).
- Caching does not help: only the first lookup is expensive, and later ones hit the dcache.
- The only real fix is to parse the FAT directory straight from the block device. That was judged not worth it for this version.

---

## 6. Repeating the diagnosis on another console or firmware

1. **Check the prerequisites on the console.** Use `log.txt` while running USB mode, or any shell you have:
   - `/dev/mtp_usb` appears after `mtp.usb0` is created (the `TRACE devnode:` line in the log);
   - the UDC name (`ls /sys/class/udc`) matches `UDC_NAME` in `usb_mode.sh` (here `musb-hdrc.0.auto`);
   - the architecture is little-endian MIPS (`uname -m` = `mips`). For anything else, rebuild with a matching `-target`; the code is portable.
2. **Check the driver's ioctls** if the kernel differs. Look for `0x8020` / `0x4D04` in the stock `mtp-server`, as in §3.1. Or simply confirm in tfmtp's log that `GetObject` transfers the file (`sent N bytes`) rather than logging `send file failed`.
3. **Capture both ends:**
   - console: `log.txt` in the SD root;
   - PC: `tools/usb_trace_setup.ps1` (once, as admin, then reboot), `tools/usb_capture.ps1` during the test, then `tools/usb_mtp_report.ps1`.

   Line the two up by time. On the console, use `TFMTP <uptime>` and `KMSG [uptime]`; on the PC, the timestamps in the report. The anchor is the connect event: `gadget connet` in `dmesg` ↔ the device arrival in the monitor.
4. **Signatures:**
   - the request was sent (bulk OUT OK), no answer came, and the server is in `R` at 100 % CPU → the server is busy, for example indexing;
   - the server sits in `wchan=mtp_read` while a request was sent → the problem is lower down, in the driver or the cable;
   - the PC sends no requests at all and there is no `gadget connet` in `KMSG` → USB never came up (role, UDC or cable).

---

## 7. Reference checksums

- SHA-256 of the stock `usb_mode.sh`, TreeFrogUI v1.8.0_u: `20AB52FF0AAB3127D6F557FDCE04ADE92AEDE30B13AB00B845A6F8C5C940A0BA`
- SHA-256 of the stock `mtp-server` from the same release: `6A26099FFBB5106B0772753FC5E9070613679A65F80F9F13F27EC6FA3EB3CA9D`
