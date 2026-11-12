@echo off
REM Removes Slop-Ray Engine and puts your original GAMMA files back.
REM Plain text, like uninstall.ps1 - read it in Notepad first if you like.
REM Works from the pack folder or from your GAMMA folder (where the installer
REM leaves a copy). -ExecutionPolicy Bypass applies ONLY to this one run.
title Slop-Ray Engine uninstaller
set "SR_PS1=%~dp0uninstall.ps1"
if not exist "%SR_PS1%" set "SR_PS1=%~dp0.slopray\tool\uninstall.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SR_PS1%"
if errorlevel 1 pause
