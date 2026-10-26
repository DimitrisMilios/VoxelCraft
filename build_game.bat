@echo off
title VoxelCraft Production Packager
echo Packaging VoxelCraft into production PCK and executable...
if not exist "%~dp0build" mkdir "%~dp0build"
if not exist "%~dp0build\VoxelCraft.exe" (
    copy "C:\Program Files\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" "%~dp0build\VoxelCraft.exe"
)
"C:\Program Files\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --headless --export-pack "Windows Desktop" "%~dp0build\VoxelCraft.pck"
echo Production build ready in build\VoxelCraft.exe!
pause
