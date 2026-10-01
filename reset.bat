@echo off
rem reset.bat - WoTB_CN all-in-one rollback (PC hosts / PC login cache / emulator hosts / wotblitz.exe.bak)
rem auto UAC elevation, menu driven; result is also written to reset_result.txt next to this script
setlocal
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel%==0 goto :run

echo [i] Administrator required. UAC prompt will appear, please click Yes...
powershell -NoProfile -Command "try { Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0reset.ps1' } catch { exit 9 }"
if %errorlevel%==9 (
    echo [!] UAC cancelled. Nothing was modified.
) else (
    echo [i] Elevated run finished.
)
chcp 65001 >nul
echo [i] ===== result (reset_result.txt) =====
type "%~dp0reset_result.txt"
echo [i] ========================================
pause
exit /b

:run
title reset (admin)
echo [i] Running as admin: %~f0
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0reset.ps1"
echo.
echo [i] Done. Result written to reset_result.txt
pause
