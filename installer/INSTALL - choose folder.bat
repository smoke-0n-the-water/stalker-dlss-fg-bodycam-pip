@echo off
REM Same as "INSTALL - double-click me.bat", but it does not search for the
REM game: it asks you to paste the folder. Use it when you have more than one
REM G.A.M.M.A. install, or when the normal installer picks the wrong one.
REM Paste the folder with Anomaly and GAMMA in it, or either of those two.
title GAMMA v0.7.3-dev installer (choose folder)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -AskPath
if errorlevel 1 pause
