@echo off
REM Same as "INSTALL + DLSS 5 (RTX, experimental).bat", with the newer
REM OptiScaler F5 0.1.38 instead of 0.1.35. 0.1.38 adds DLSS 5 "Model
REM resolution" ([DlssNr] WorkingScale in OptiScaler.ini). Not played in
REM game yet: if it misbehaves, run the 0.1.35 DLSS 5 .bat again (it swaps back).
REM RTX + NVIDIA driver 616.56+. Experimental, costs fps.
title GAMMA v0.7.1-dev installer + DLSS 5 (OptiScaler 0.1.38)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Dlss5 -OptiScaler 0.1.38
if errorlevel 1 pause
