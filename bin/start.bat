@echo off
setlocal enabledelayedexpansion

:: 检查Java环境（优先使用系统Java，无则提示）
java -version >nul 2>&1
if %errorlevel% neq 0 (
    echo 未检测到Java环境，请先安装JDK8或配置JAVA_HOME环境变量
    pause
    exit /b 1
)

:: 启动SpringBoot应用
echo 正在启动数据与模型一体化管理软件...
java -jar target/data-model-gov-1.0.0.jar --spring.profiles.active=prod

:: 启动成功提示
echo 系统启动成功！请打开浏览器访问：http://localhost:8080
pause
endlocal