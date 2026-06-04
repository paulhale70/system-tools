@echo off
setlocal

REM Build a single-file self-contained .exe for win-x64.
REM Output: bin\Release\net8.0-windows\win-x64\publish\SystemTools.Desktop.exe
REM
REM Requires the .NET 8 SDK (download from https://dotnet.microsoft.com/download/dotnet/8.0).
REM
REM Optional code-signing:
REM   set SIGNING_PFX=C:\certs\code.pfx
REM   set SIGNING_PFX_PWD=hunter2
REM   build.bat
REM The signed .exe avoids the SmartScreen warning on family machines.

dotnet publish "%~dp0SystemTools.Desktop.csproj" -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true

if errorlevel 1 goto buildfail

set "EXE=%~dp0bin\Release\net8.0-windows\win-x64\publish\SystemTools.Desktop.exe"

if not defined SIGNING_PFX goto skipsign

echo.
echo Signing %EXE% with %SIGNING_PFX% ...
where signtool >nul 2>&1
if errorlevel 1 goto nosigntool

if defined SIGNING_PFX_PWD goto signpwd
signtool sign /fd sha256 /tr http://timestamp.digicert.com /td sha256 /f "%SIGNING_PFX%" "%EXE%"
goto signcheck

:signpwd
signtool sign /fd sha256 /tr http://timestamp.digicert.com /td sha256 /f "%SIGNING_PFX%" /p "%SIGNING_PFX_PWD%" "%EXE%"

:signcheck
if errorlevel 1 goto signfail
echo Signed.
goto done

:skipsign
echo.
echo Skipping code-signing. Set SIGNING_PFX to enable.
goto done

:nosigntool
echo signtool.exe not found on PATH. Install Windows SDK or add the SDK bin dir to PATH.
pause
exit /b 1

:signfail
echo signtool failed.
pause
exit /b 1

:buildfail
echo.
echo Build failed. If you see 'dotnet not recognized', install the .NET 8 SDK.
pause
exit /b 1

:done
echo.
echo Built: %EXE%
echo.
echo Before distributing, copy ..\diagnostics\system-diagnostics.ps1,
echo diff-diagnostics.ps1, trends-diagnostics.ps1, and the plugins
echo subfolder next to the .exe. The GUI looks for them in a
echo 'diagnostics' subdirectory.
pause
