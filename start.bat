@echo off
title Agent Team Kanban

if not exist "%~dp0desktop\node_modules\electron" (
    echo  Electron not installed. Run setup.bat first.
    pause
    exit /b 1
)

cd /d "%~dp0desktop"
set ELECTRON_RUN_AS_NODE=
node launch.js
