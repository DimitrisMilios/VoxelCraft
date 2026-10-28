@echo off
title VoxelCraft Production Packager
echo Exporting VoxelCraft as a single standalone release executable...
rem Needs the official Godot 4.7.2 export templates (Editor > Manage Export Templates).
if not exist "%~dp0build" mkdir "%~dp0build"
if exist "%~dp0build\VoxelCraft.pck" del "%~dp0build\VoxelCraft.pck"
"C:\Program Files\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0." --export-release "Windows Desktop" "%~dp0build\VoxelCraft.exe"
echo Production build ready in build\VoxelCraft.exe!
pause
