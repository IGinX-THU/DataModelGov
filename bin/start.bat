@echo off
setlocal enabledelayedexpansion

REM Data Model Governance - Windows Startup Script
REM Supports both zip package and extracted directory

echo ==========================================
echo Data Model Governance Software - Starting
echo ==========================================

REM Get script directory
cd /d "%~dp0"

REM Check if we have a zip package to extract
set ZIP_FILE=
for %%f in (*.zip) do (
    if "%%~nf"=="data-model-gov-1.0.0-standalone" (
        set ZIP_FILE=%%f
        goto :found_zip
    )
)

:found_zip
if defined ZIP_FILE (
    echo Found deployment package: !ZIP_FILE!
    echo Extracting to deployment directory...
    
    REM Create deployment directory
    if not exist "deployment" mkdir deployment
    
    REM Extract zip file
    powershell -Command "Expand-Archive -Path '!ZIP_FILE!' -DestinationPath 'deployment' -Force"
    
    if errorlevel 1 (
        echo ERROR: Failed to extract deployment package
        pause
        exit /b 1
    )
    
    echo Extraction completed!
    cd deployment
)

REM Check application JAR
set APP_JAR=
if exist "app\data-model-gov-1.0.0.jar" (
    set APP_JAR=app\data-model-gov-1.0.0.jar
) else (
    for %%f in (*.jar) do (
        if not "%%f"=="%%~nf-sources.jar" if not "%%f"=="%%~nf-javadoc.jar" (
            set APP_JAR=%%f
            goto :found_jar
        )
    )
)

:found_jar
if not defined APP_JAR (
    echo ERROR: Application JAR file not found
    echo Please ensure deployment package is extracted or JAR file exists
    pause
    exit /b 1
)

echo Found application JAR: !APP_JAR!

REM Check Java environment
if exist "jre\bin\java.exe" (
    echo Using embedded JRE
    set JAVA_CMD=jre\bin\java.exe
) else (
    echo Using system Java
    java -version >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Java environment not found
        echo Please ensure Java 8+ is installed or JRE directory exists
        pause
        exit /b 1
    )
    set JAVA_CMD=java
)

REM Set Java options
set JAVA_OPTS=-Xmx2g -Xms1g -XX:+UseG1GC -XX:+UseStringDeduplication

REM Check for config directory (优先使用外部配置)
if exist "..\config\application.yml" (
    set CONFIG_PATH=..\config\application.yml,..\config\config\iginx-config.properties
    echo Using external config: !CONFIG_PATH!
) else if exist "..\config\application.properties" (
    set CONFIG_PATH=..\config\application.properties,..\config\config\iginx-config.properties
    echo Using external config: !CONFIG_PATH!
) else if exist "config\application.yml" (
    set CONFIG_PATH=config\application.yml,config\iginx-config.properties
    echo Using internal config: !CONFIG_PATH!
) else if exist "config\application.properties" (
    set CONFIG_PATH=config\application.properties,config\iginx-config.properties
    echo Using internal config: !CONFIG_PATH!
) else (
    echo WARNING: No configuration file found, using defaults
    set CONFIG_PATH=
)

REM Start application
echo.
echo Starting Data Model Governance...
echo Java command: %JAVA_CMD%
echo Java options: !JAVA_OPTS!
if defined CONFIG_PATH echo Config file: !CONFIG_PATH!
echo.

REM Create logs directory if not exists
if not exist "logs" mkdir logs

REM Start the application
if defined CONFIG_PATH (
    %JAVA_CMD% !JAVA_OPTS! -jar "!APP_JAR!" --spring.config.location=!CONFIG_PATH! --spring.profiles.active=standalone
) else (
    %JAVA_CMD% !JAVA_OPTS! -jar "!APP_JAR!" --spring.profiles.active=standalone
)

REM Check if application started successfully
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

REM Keep the script running
pause
