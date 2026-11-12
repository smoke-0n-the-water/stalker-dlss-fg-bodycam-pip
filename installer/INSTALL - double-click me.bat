@echo off
REM Runs install.ps1 from this folder. Both files are plain text - read
REM install.ps1 in Notepad first if you like.
REM -ExecutionPolicy Bypass applies ONLY to this one run.
title GAMMA v0.6-dev installer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 pause
