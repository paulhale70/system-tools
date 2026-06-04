@echo off
setlocal

REM Build a single-file self-contained .exe for win-x64.
REM Output: bin\Release\net8.0-windows\win-x64\publish\SystemTools.Desktop.exe
REM
REM Requires the .NET 8 SDK (download from https://dotnet.microsoft.com/download/dotnet/8.0).
REM
REM Optional code-signing:
REM   Set the SIGNING_PFX environment variable to a .pfx path (and optionally
REM   SIGNING_PFX_PWD to its password) before running, e.g.:
REM     set SIGNING_PFX=C:\certs\code.pfx
REM     set SIGNING_PFX_PWD=hunter2
REM     build.bat
REM   The signed .exe avoids the SmartScreen "Windows protected your PC"
REM   dialog on family machines.

dotnet publish "%~dp0SystemTools.Desktop.csproj" -c Release -r win-x64 --self-contained true ^
  -p:PublishSingleFile=true ^
  -p:IncludeNativeLibrariesForSelfExtract=true ^
  -p:EnableCompressionInSingleFile=true

if errorlevel 1 (
  echo.
  echo Build failed. If you see 'dotnet not recognized', install the .NET 8 SDK.
  pause
  exit /b 1
)

set EXE=%~dp0bin\Release\net8.0-windows\win-x64\publish\SystemTools.Desktop.exe

if defined SIGNING_PFX (
  echo.
  echo Signing %EXE% with %SIGNING_PFX% ...
  where signtool >nul 2>&1
  if errorlevel 1 (
    echo signtool.exe not found on PATH. Install Windows SDK or add the SDK bin dir to PATH.
    pause
    exit /b 1
  )
  if defined SIGNING_PFX_PWD (
    signtool sign /fd sha256 /tr http://timestamp.digicert.com /td sha256 ^
                  /f "%SIGNING_PFX%" /p "%SIGNING_PFX_PWD%" "%EXE%"
  ) else (
    signtool sign /fd sha256 /tr http://timestamp.digicert.com /td sha256 ^
                  /f "%SIGNING_PFX%" "%EXE%"
  )
  if errorlevel 1 (
    echo signtool failed.
    pause
    exit /b 1
  )
  echo Signed.
) else (
  echo.
  echo Skipping code-signing (set SIGNING_PFX to enable).
)

echo.
echo Built: %EXE%
echo.
echo Before distributing, copy ..\diagnostics\system-diagnostics.ps1,
echo diff-diagnostics.ps1, trends-diagnostics.ps1, and the plugins
echo subfolder next to the .exe (the GUI looks for them in a
echo 'diagnostics' subdirectory).
pause
