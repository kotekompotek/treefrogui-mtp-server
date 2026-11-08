# Changelog

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