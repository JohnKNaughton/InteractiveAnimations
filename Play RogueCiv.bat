@echo off
title RogueCiv
rem Finds Godot next to this file, one level up, or on the Desktop, then runs the game.
setlocal
set "PROJ=%~dp0rogueciv_godot"

for %%G in (
  "%~dp0Godot_v4.6.2-stable_win64.exe"
  "%~dp0..\Godot_v4.6.2-stable_win64.exe"
  "%USERPROFILE%\OneDrive\Desktop\Godot_v4.6.2-stable_win64.exe"
  "%USERPROFILE%\Desktop\Godot_v4.6.2-stable_win64.exe"
) do (
  if exist %%G (
    start "" %%G --path "%PROJ%"
    exit /b 0
  )
)

echo Could not find Godot_v4.6.2-stable_win64.exe.
echo Put it beside this file, or open %PROJ%\project.godot in Godot yourself.
pause
