@echo off
setlocal enabledelayedexpansion

REM Data Model Governance - Windows Startup Script
REM For manually extracted deployment package

echo ==========================================
echo Data Model Governance Software - Starting
echo ==========================================

REM Get script directory and go to parent directory
cd /d "%~dp0.."

REM Check application JAR
set APP_JAR=app\data-model-gov-1.0.0.jar
if not exist "%APP_JAR%" (
    echo ERROR: Application JAR file not found at %APP_JAR%
    echo Please ensure you have extracted the deployment package correctly
    pause
    exit /b 1
)

echo Found application JAR: !APP_JAR!

REM Test embedded JRE first
if exist "jre\bin\java.exe" (
    echo Testing embedded JRE...
    "jre\bin\java.exe" -version >nul 2>&1
    if errorlevel 1 (
        echo Embedded JRE failed, using system Java
        set JAVA_CMD=java
    ) else (
        echo Using embedded JRE
        set JAVA_CMD=jre\bin\java.exe
    )
) else (
    echo Using system Java
    java -version >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Java environment not found
        echo Please ensure Java 8+ is installed
        pause
        exit /b 1
    )
    set JAVA_CMD=java
)

REM Check for config directory
set CONFIG_PATH=
if exist "config\application.yml" (
    set CONFIG_PATH=config\application.yml,config\config\iginx-config.properties
    echo Using config: !CONFIG_PATH!
) else if exist "config\application.yaml" (
    set CONFIG_PATH=config\application.yaml,config\config\iginx-config.properties
    echo Using config: !CONFIG_PATH!
) else if exist "config\application.properties" (
    set CONFIG_PATH=config\application.properties,config\config\iginx-config.properties
    echo Using config: !CONFIG_PATH!
) else (
    echo WARNING: No configuration file found, using defaults
)

REM Create logs directory if not exists
if not exist "logs" mkdir logs

echo.
echo Starting Data Model Governance...
echo Java command: !JAVA_CMD!
echo JAR file: !APP_JAR!
if defined CONFIG_PATH echo Config file: !CONFIG_PATH!
echo.

REM Start application
if defined CONFIG_PATH (
    "!JAVA_CMD!" -Xmx2g -Xms1g -XX:+UseG1GC -XX:+UseStringDeduplication -jar "!APP_JAR!" --spring.config.location=!CONFIG_PATH! --spring.profiles.active=standalone
) else (
    "!JAVA_CMD!" -Xmx2g -Xms1g -XX:+UseG1GC -XX:+UseStringDeduplication -jar "!APP_JAR!" --spring.profiles.active=standalone
)

if errorlevel 1 (
    echo.
    echo ERROR: Application failed to start
    echo Please check the error message above
    pause
    exit /b 1
) else (
    echo.
    echo Application started successfully!
    echo Access the application at: http://localhost:8080
    echo Press Ctrl+C to stop the application
)

pause
