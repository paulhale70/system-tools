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
  "$ErrorActionPreference='Stop'; $tmp = Join-Path $env:TEMP 'system-diagnostics.ps1'; try { Invoke-WebRequest 'https://raw.githubusercontent.com/paulhale70/System-tools/main/system-diagnostics.ps1?nc=%random%' -OutFile $tmp -UseBasicParsing; & $tmp -ProjectName ('PC-' + $env:COMPUTERNAME) } catch { Write-Host ''; Write-Host ('  ERROR: ' + $_.Exception.Message) -ForegroundColor Red; Write-Host ''; Write-Host '  Please take a screenshot of this window and send it back.' -ForegroundColor Yellow }"

echo.
echo  ------------------------------------------------------------------
echo    All done. Look on your Desktop for the zip file:
echo       PC-^<your-pc-name^>-Diagnostics-^<date^>.zip
echo  ------------------------------------------------------------------
echo.
choice /M "Open your email program now (we'll copy the zip path to the clipboard so you can paste/drag it as an attachment)"
if errorlevel 2 goto end
powershell -NoProfile -Command "$zip = Get-ChildItem $env:USERPROFILE\Desktop -Filter 'PC-*-Diagnostics-*.zip' | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($zip) { Set-Clipboard -Value $zip.FullName; Write-Host ('Copied to clipboard: ' + $zip.FullName) -ForegroundColor Green; Start-Process 'mailto:?subject=Diagnostics%%20from%%20' -ArgumentList ($env:COMPUTERNAME) }"
:end
echo.
pause
