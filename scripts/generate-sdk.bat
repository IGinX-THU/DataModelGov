@echo off
setlocal enabledelayedexpansion

REM DataModelGov Thrift SDK 一键生成脚本 (Windows批处理版本)
REM 用于生成Java、Go、Python三语言的SDK

title DataModelGov Thrift SDK Generator

REM 项目根目录
set PROJECT_ROOT=%~dp0..
set THRIFT_FILE=%PROJECT_ROOT%\datamodelgov-server\src\main\resources\thrift\api.thrift

REM SDK输出目录
set JAVA_SDK_DIR=%PROJECT_ROOT%\datamodelgov-sdk-java\src\main\java
set GO_SDK_DIR=%PROJECT_ROOT%\datamodelgov-sdk-go\src
set PYTHON_SDK_DIR=%PROJECT_ROOT%\datamodelgov-sdk-python\src

REM 解析命令行参数
set CLEAN_ONLY=0
set VALIDATE_ONLY=0
set SHOW_HELP=0

:parse_args
if "%~1"=="" goto main_start
if /i "%~1"=="--help" set SHOW_HELP=1 & shift & goto parse_args
if /i "%~1"=="-h" set SHOW_HELP=1 & shift & goto parse_args
if /i "%~1"=="--clean" set CLEAN_ONLY=1 & shift & goto parse_args
if /i "%~1"=="-c" set CLEAN_ONLY=1 & shift & goto parse_args
if /i "%~1"=="--validate" set VALIDATE_ONLY=1 & shift & goto parse_args
if /i "%~1"=="-v" set VALIDATE_ONLY=1 & shift & goto parse_args
echo [ERROR] 未知选项: %~1
goto show_help

:main_start
echo ===================================
echo 🚀 DataModelGov Thrift SDK 生成器
echo ===================================
echo.

REM 显示帮助
if %SHOW_HELP%==1 goto show_help

REM 仅清理模式
if %CLEAN_ONLY%==1 goto clean_only

REM 仅验证模式
if %VALIDATE_ONLY%==1 goto validate_only

REM 完整生成流程
call :check_thrift
if errorlevel 1 goto end_error

call :validate_thrift_file
if errorlevel 1 goto end_error

call :cleanup_old_files
call :create_directories
if errorlevel 1 goto end_error

call :generate_java_sdk
if errorlevel 1 goto end_error

call :generate_go_sdk
if errorlevel 1 goto end_error

call :generate_python_sdk
if errorlevel 1 goto end_error

call :verify_sdks
call :show_results
goto end_success

:check_thrift
echo [INFO] 检查Thrift环境...
thrift --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Thrift未安装或不在PATH中
    echo [INFO] 请安装Thrift: https://thrift.apache.org/download
    exit /b 1
)

for /f "tokens=*" %%i in ('thrift --version 2^>nul') do set THRIFT_VERSION=%%i
echo [SUCCESS] Thrift环境正常，版本: %THRIFT_VERSION%
exit /b 0

:validate_thrift_file
echo [INFO] 验证Thrift文件语法...

if not exist "%THRIFT_FILE%" (
    echo [ERROR] Thrift文件不存在: %THRIFT_FILE%
    exit /b 1
)

thrift --gen dummy "%THRIFT_FILE%" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Thrift文件语法错误
    exit /b 1
)

echo [SUCCESS] Thrift文件语法正确
exit /b 0

:create_directories
echo [INFO] 创建输出目录...

if not exist "%JAVA_SDK_DIR%" mkdir "%JAVA_SDK_DIR%"
if not exist "%GO_SDK_DIR%" mkdir "%GO_SDK_DIR%"
if not exist "%PYTHON_SDK_DIR%" mkdir "%PYTHON_SDK_DIR%"

echo [SUCCESS] 输出目录创建完成
exit /b 0

:generate_java_sdk
echo [INFO] 生成Java SDK...

cd /d "%PROJECT_ROOT%"
thrift --gen java -out "%JAVA_SDK_DIR%" "%THRIFT_FILE%"
if errorlevel 1 (
    echo [ERROR] Java SDK生成失败
    exit /b 1
)

REM 统计生成的文件数
set /a JAVA_FILES=0
for /f %%i in ('dir /b "%JAVA_SDK_DIR%\com\tsinghua\thrift\api\*.java" 2^>nul ^| find /c /v ""') do set /a JAVA_FILES=%%i
echo [SUCCESS] Java SDK生成成功，共 %JAVA_FILES% 个文件

REM 检查关键文件
if exist "%JAVA_SDK_DIR%\com\tsinghua\thrift\api\ParsingRule.java" (
    echo [SUCCESS] ✓ ParsingRule.java 已生成
)

if exist "%JAVA_SDK_DIR%\com\tsinghua\thrift\api\RunTask.java" (
    echo [SUCCESS] ✓ RunTask.java 已生成
)

exit /b 0

:generate_go_sdk
echo [INFO] 生成Go SDK...

cd /d "%PROJECT_ROOT%"
thrift --gen go -out "%GO_SDK_DIR%" "%THRIFT_FILE%"
if errorlevel 1 (
    echo [ERROR] Go SDK生成失败
    exit /b 1
)

REM 统计生成的文件数
set /a GO_FILES=0
for /f %%i in ('dir /b "%GO_SDK_DIR%\tsinghua\api\*.go" 2^>nul ^| find /c /v ""') do set /a GO_FILES=%%i
echo [SUCCESS] Go SDK生成成功，共 %GO_FILES% 个文件

REM 检查关键文件
if exist "%GO_SDK_DIR%\tsinghua\api\api.go" (
    echo [SUCCESS] ✓ api.go 已生成
)

exit /b 0

:generate_python_sdk
echo [INFO] 生成Python SDK...

cd /d "%PROJECT_ROOT%"
thrift --gen py -out "%PYTHON_SDK_DIR%" "%THRIFT_FILE%"
if errorlevel 1 (
    echo [ERROR] Python SDK生成失败
    exit /b 1
)

REM 统计生成的文件数
set /a PYTHON_FILES=0
for /f %%i in ('dir /b "%PYTHON_SDK_DIR%\tsinghua\api\*.py" 2^>nul ^| find /c /v ""') do set /a PYTHON_FILES=%%i
echo [SUCCESS] Python SDK生成成功，共 %PYTHON_FILES% 个文件

REM 检查关键文件
if exist "%PYTHON_SDK_DIR%\tsinghua\api\ttypes.py" (
    echo [SUCCESS] ✓ ttypes.py 已生成
)

exit /b 0

:verify_sdks
echo [INFO] 验证生成的SDK...

REM 验证Java SDK
if exist "%JAVA_SDK_DIR%\com\tsinghua\thrift\api\ApiService.java" (
    for %%F in ("%JAVA_SDK_DIR%\com\tsinghua\thrift\api\ApiService.java") do set JAVA_SIZE=%%~zF
    echo [SUCCESS] ✓ Java ApiService.java (!JAVA_SIZE! bytes)
)

REM 验证Go SDK
if exist "%GO_SDK_DIR%\tsinghua\api\api.go" (
    for %%F in ("%GO_SDK_DIR%\tsinghua\api\api.go") do set GO_SIZE=%%~zF
    echo [SUCCESS] ✓ Go api.go (!GO_SIZE! bytes)
)

REM 验证Python SDK
if exist "%PYTHON_SDK_DIR%\tsinghua\api\ApiService.py" (
    for %%F in ("%PYTHON_SDK_DIR%\tsinghua\api\ApiService.py") do set PYTHON_SIZE=%%~zF
    echo [SUCCESS] ✓ Python ApiService.py (!PYTHON_SIZE! bytes)
)

exit /b 0

:cleanup_old_files
echo [INFO] 清理旧的生成文件...

REM 清理Java SDK
if exist "%JAVA_SDK_DIR%\com\tsinghua\thrift\api" (
    rmdir /s /q "%JAVA_SDK_DIR%\com\tsinghua\thrift\api"
    echo [INFO] 已清理旧的Java SDK文件
)

REM 清理Go SDK
if exist "%GO_SDK_DIR%\tsinghua" (
    rmdir /s /q "%GO_SDK_DIR%\tsinghua"
    echo [INFO] 已清理旧的Go SDK文件
)

REM 清理Python SDK
if exist "%PYTHON_SDK_DIR%\tsinghua" (
    rmdir /s /q "%PYTHON_SDK_DIR%\tsinghua"
    echo [INFO] 已清理旧的Python SDK文件
)

exit /b 0

:clean_only
call :cleanup_old_files
echo [SUCCESS] 清理完成
goto end_success

:validate_only
call :check_thrift
if errorlevel 1 goto end_error

call :validate_thrift_file
if errorlevel 1 goto end_error

echo [SUCCESS] 验证通过
goto end_success

:show_results
echo.
echo ===================================
echo 🎉 SDK生成完成！
echo ===================================
echo.
echo 📁 生成位置:
echo   Java SDK:  %JAVA_SDK_DIR%\com\tsinghua\thrift\api\
echo   Go SDK:    %GO_SDK_DIR%\tsinghua\api\
echo   Python SDK: %PYTHON_SDK_DIR%\tsinghua\api\
echo.
echo 📋 新增API支持:
echo   ✅ ParsingRule - 解析规则管理 (包含example字段)
echo   ✅ RunTask - 运行任务管理
echo   ✅ ExtractModelFileRequest - 模型文件提取
echo.
echo 🚀 使用方法:
echo   启动应用: mvn spring-boot:run
echo   Thrift服务将在端口9090启动
echo.
echo 📖 更多信息请查看各SDK模块的README.md文件
exit /b 0

:show_help
echo DataModelGov Thrift SDK 生成脚本 (Windows批处理版本)
echo.
echo 用法: %~nx0 [选项]
echo.
echo 选项:
echo   -h, --help     显示帮助信息
echo   -c, --clean    仅清理旧文件，不生成新SDK
echo   -v, --validate 仅验证Thrift文件，不生成SDK
echo.
echo 示例:
echo   %~nx0              # 完整生成SDK
echo   %~nx0 --clean      # 清理旧文件
echo   %~nx0 --validate   # 验证Thrift文件
exit /b 0

:end_success
echo.
echo [SUCCESS] 操作完成！
pause
exit /b 0

:end_error
echo.
echo [ERROR] 操作失败！
pause
exit /b 1
