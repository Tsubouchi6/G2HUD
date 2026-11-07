@echo off
rem Starts the G2HUD PC bridge. Put a shortcut to this file in shell:startup
rem to start it when Windows logs in.
title G2HUD bridge
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bridge.ps1"
