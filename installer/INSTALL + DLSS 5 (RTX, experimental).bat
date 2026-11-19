@echo off
REM Same as "INSTALL - double-click me.bat" plus DLSS 5 / Neural Rendering
REM (STEP 6: OptiScaler as Anomaly\bin\dxgi.dll). RTX + NVIDIA driver 616.56+.
REM OptiScaler F5 0.1.35, the version played since v0.5. Newer 0.1.38: use the
REM "INSTALL + DLSS 5 - OptiScaler 0.1.38" .bat instead (re-running either swaps).
REM Experimental, costs fps. Undo: rename Anomaly\bin\dxgi.dll to dxgi.dll.off
title GAMMA v0.7.2-dev installer + DLSS 5 (OptiScaler 0.1.35)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Dlss5
if errorlevel 1 pause
