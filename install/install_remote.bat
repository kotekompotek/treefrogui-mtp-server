@echo off
chcp 65001 >nul
rem Same as install.bat plus remote control from the PC (root shell over MTP, see pc/r36.py)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_tfmtp.ps1" -Remote %*
pause
