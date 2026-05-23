@echo off
title System Diagnostics Collector
color 0B
echo.
echo  ==================================================================
echo    System Diagnostics Collector
echo  ==================================================================
echo.
echo   This tool collects information about your PC (Windows version,
echo   hardware, recent errors, network state, installed updates).
echo.
echo   It does NOT collect passwords, your documents, your photos, or
echo   anything you've typed.
echo.
echo   When it finishes, a folder and a zip file appear on your
echo   Desktop. Email the zip file to the person who sent you this.
echo.
echo  ------------------------------------------------------------------
echo    Press any key to start, or close this window to cancel.
echo  ------------------------------------------------------------------
pause >nul

echo.
echo   Downloading the latest diagnostic script...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $tmp = Join-Path $env:TEMP 'system-diagnostics.ps1'; try { Invoke-WebRequest 'https://raw.githubusercontent.com/paulhale70/System-tools/claude/powershell-diagnostic-script-Ev7P3/system-diagnostics.ps1?nc=%random%' -OutFile $tmp -UseBasicParsing; & $tmp -ProjectName ('PC-' + $env:COMPUTERNAME) } catch { Write-Host ''; Write-Host ('  ERROR: ' + $_.Exception.Message) -ForegroundColor Red; Write-Host ''; Write-Host '  Please take a screenshot of this window and send it back.' -ForegroundColor Yellow }"

echo.
echo  ------------------------------------------------------------------
echo    All done. Look on your Desktop for the zip file:
echo       PC-^<your-pc-name^>-Diagnostics-^<date^>.zip
echo    Email that zip file to the person who sent you this tool.
echo  ------------------------------------------------------------------
echo.
pause
