@echo off
setlocal enabledelayedexpansion

REM Data Model Governance - Simple Windows Stop Script
REM Stops the application running in the same directory

echo ==========================================
echo Data Model Governance - Stopping
echo ==========================================

REM Find and kill Java processes
echo Stopping application...

REM Kill by port 8080
for /f "tokens=5" %%i in ('netstat -ano ^| find ":8080"') do (
    echo Found process using port 8080: %%i
    taskkill /pid %%i /f
    goto :success
)

REM Kill by JAR name
for /f "tokens=2" %%i in ('tasklist /fi "imagename eq java.exe" /fo csv ^| findstr "data-model"') do (
    echo Found data-model process: %%i
    taskkill /pid %%i /f
    goto :success
)

:success
echo.
echo Application stop command sent
echo Please wait a few seconds for application to shut down

REM Wait and verify
timeout /t 3 /nobreak >nul

netstat -ano | find ":8080" >nul
if !errorlevel! equ 0 (
    echo WARNING: Application may still be running
) else (
    echo SUCCESS: Application stopped successfully
)

echo.
echo ==========================================
pause
