@echo off
title Media Inventory Scanner

echo Checking Python...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Python not found. Install from https://python.org
    pause
    exit /b 1
)

echo Installing / updating dependencies...
pip install -r requirements.txt --quiet
if %errorlevel% neq 0 (
    echo WARNING: Could not install all dependencies.
    echo Barcode lookup and cover art may not work.
    pause
)

echo.
echo Starting Media Inventory Scanner...
python main.py
if %errorlevel% neq 0 (
    echo.
    echo Application exited with an error. See output above.
    pause
)
