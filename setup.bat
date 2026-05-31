@echo off
title Agent Team Kanban - Setup

echo.
echo  ============================================
echo   Agent Team Kanban Board - Setup
echo  ============================================
echo.

echo  [1/3] Checking Python...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo  [FAIL] Python not found.
    echo         Install from https://www.python.org/downloads/
    echo         Check "Add Python to PATH" during installation!
    pause
    exit /b 1
)
python --version
echo  [OK]
echo.

echo  [2/3] Checking Node.js...
node --version >nul 2>&1
if %errorlevel% neq 0 (
    echo  [FAIL] Node.js not found.
    echo         Install LTS from https://nodejs.org/
    pause
    exit /b 1
)
node --version
echo  [OK]
echo.

echo  [3/3] Installing Electron dependencies...
cd /d "%~dp0desktop"
if not exist "node_modules\electron" (
    echo  Running npm install (first time only)...
    call npm install
    if %errorlevel% neq 0 (
        echo  [FAIL] npm install failed. Check errors above.
        pause
        exit /b 1
    )
) else (
    echo  [OK] Already installed
)

echo.
echo  ============================================
echo   Setup Complete!
echo  ============================================
echo.
echo   To run: double-click start.bat
echo   Or:     python server.py (server only)
echo.
pause
