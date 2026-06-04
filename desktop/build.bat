@echo off
REM Build a single-file self-contained .exe for win-x64.
REM Output: bin\Release\net8.0-windows\win-x64\publish\SystemTools.Desktop.exe
REM
REM Requires the .NET 8 SDK (download from https://dotnet.microsoft.com/download/dotnet/8.0).

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

echo.
echo Built: %~dp0bin\Release\net8.0-windows\win-x64\publish\SystemTools.Desktop.exe
echo.
echo Before distributing, copy ..\diagnostics\system-diagnostics.ps1 next to
echo the .exe (the runner looks for it in a 'diagnostics' subfolder).
pause
