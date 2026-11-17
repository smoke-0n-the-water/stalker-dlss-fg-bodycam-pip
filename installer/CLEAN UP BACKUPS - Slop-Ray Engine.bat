@echo off
REM Optional, after a COMPLETE uninstall only: deletes the backup copies of
REM your original files that are already back in place. Asks first. Never
REM touches the recovery folder. Plain text, like cleanup_backups.ps1.
title Slop-Ray Engine backup clean-up
set "SR_PS1=%~dp0cleanup_backups.ps1"
if not exist "%SR_PS1%" set "SR_PS1=%~dp0.slopray\tool\cleanup_backups.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SR_PS1%"
if errorlevel 1 pause
