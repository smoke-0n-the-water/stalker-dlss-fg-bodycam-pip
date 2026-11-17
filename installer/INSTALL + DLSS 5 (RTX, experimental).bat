@echo off
REM Same as "INSTALL - double-click me.bat" plus DLSS 5 / Neural Rendering
REM (STEP 6: OptiScaler as Anomaly\bin\dxgi.dll). RTX + NVIDIA driver 616.56+.
REM Experimental, costs fps. Undo: rename Anomaly\bin\dxgi.dll to dxgi.dll.off
title GAMMA v0.6-dev installer + DLSS 5
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Dlss5
if errorlevel 1 pause
