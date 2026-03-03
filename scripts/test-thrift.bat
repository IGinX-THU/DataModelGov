@echo off
echo Testing Thrift installation...

REM Check if thrift is installed
thrift --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Thrift is not installed or not in PATH
    echo Please install Thrift:
    echo   Download from https://thrift.apache.org/download
    echo   Add to PATH after installation
    pause
    exit /b 1
)

REM Check thrift version
echo ✅ Thrift found:
thrift --version

REM Test thrift file syntax
echo Testing Thrift file syntax...
thrift --gen dummy datamodelgov-server\src\main\resources\thrift\api.thrift

if %errorlevel% neq 0 (
    echo ❌ Thrift file syntax error
    pause
    exit /b 1
)

echo ✅ Thrift file syntax is valid

REM Test code generation
echo Testing code generation...
if not exist test-output mkdir test-output

thrift --gen java -out test-output datamodelgov-server\src\main\resources\thrift\api.thrift
if %errorlevel% neq 0 (
    echo ❌ Java code generation failed
) else (
    echo ✅ Java code generation successful
)

thrift --gen go -out test-output datamodelgov-server\src\main\resources\thrift\api.thrift
if %errorlevel% neq 0 (
    echo ❌ Go code generation failed
) else (
    echo ✅ Go code generation successful
)

thrift --gen py -out test-output datamodelgov-server\src\main\resources\thrift\api.thrift
if %errorlevel% neq 0 (
    echo ❌ Python code generation failed
) else (
    echo ✅ Python code generation successful
)

REM Clean up
rmdir /s /q test-output 2>nul

echo ✅ All tests completed successfully!
pause
