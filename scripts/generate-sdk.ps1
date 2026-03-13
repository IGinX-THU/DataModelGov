# DataModelGov Thrift SDK 一键生成脚本 (PowerShell版本)
# 用于生成Java、Go、Python三语言的SDK

param(
    [switch]$Clean,
    [switch]$Validate,
    [switch]$Help
)

# 颜色定义
$Colors = @{
    Red = "Red"
    Green = "Green"
    Yellow = "Yellow"
    Blue = "Blue"
    White = "White"
}

# 项目根目录
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ThriftFile = Join-Path $ProjectRoot "datamodelgov-server\src\main\resources\thrift\api.thrift"

# SDK输出目录
$JavaSdkDir = Join-Path $ProjectRoot "datamodelgov-sdk-java\src\main\java"
$GoSdkDir = Join-Path $ProjectRoot "datamodelgov-sdk-go\src"
$PythonSdkDir = Join-Path $ProjectRoot "datamodelgov-sdk-python\src"

# 日志函数
function Write-LogInfo {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Colors.Blue
}

function Write-LogSuccess {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor $Colors.Green
}

function Write-LogWarning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $Colors.Yellow
}

function Write-LogError {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $Colors.Red
}

# 检查Thrift环境
function Test-ThriftEnvironment {
    Write-LogInfo "检查Thrift环境..."
    
    try {
        $ThriftVersion = & thrift --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "Thrift环境正常，版本: $ThriftVersion"
            return $true
        } else {
            Write-LogError "Thrift未安装或不在PATH中"
            Write-LogInfo "请安装Thrift: https://thrift.apache.org/download"
            return $false
        }
    } catch {
        Write-LogError "无法执行thrift命令"
        Write-LogInfo "请安装Thrift: https://thrift.apache.org/download"
        return $false
    }
}

# 验证Thrift文件
function Test-ThriftFile {
    Write-LogInfo "验证Thrift文件语法..."
    
    if (-not (Test-Path $ThriftFile)) {
        Write-LogError "Thrift文件不存在: $ThriftFile"
        return $false
    }
    
    try {
        $null = & thrift --gen dummy $ThriftFile 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "Thrift文件语法正确"
            return $true
        } else {
            Write-LogError "Thrift文件语法错误"
            return $false
        }
    } catch {
        Write-LogError "验证Thrift文件时出错"
        return $false
    }
}

# 创建输出目录
function New-OutputDirectories {
    Write-LogInfo "创建输出目录..."
    
    try {
        New-Item -ItemType Directory -Force -Path $JavaSdkDir | Out-Null
        New-Item -ItemType Directory -Force -Path $GoSdkDir | Out-Null
        New-Item -ItemType Directory -Force -Path $PythonSdkDir | Out-Null
        Write-LogSuccess "输出目录创建完成"
        return $true
    } catch {
        Write-LogError "创建输出目录失败: $($_.Exception.Message)"
        return $false
    }
}

# 生成Java SDK
function New-JavaSdk {
    Write-LogInfo "生成Java SDK..."
    
    try {
        Push-Location $ProjectRoot
        $null = & thrift --gen java -out $JavaSdkDir $ThriftFile
        Pop-Location
        
        if ($LASTEXITCODE -eq 0) {
            # 统计生成的文件数
            $JavaFiles = (Get-ChildItem -Path "$JavaSdkDir\com\tsinghua\thrift\api" -Filter "*.java" -ErrorAction SilentlyContinue).Count
            Write-LogSuccess "Java SDK生成成功，共 $JavaFiles 个文件"
            
            # 检查关键文件
            $ParsingRuleFile = Join-Path $JavaSdkDir "com\tsinghua\thrift\api\ParsingRule.java"
            if (Test-Path $ParsingRuleFile) {
                Write-LogSuccess "✓ ParsingRule.java 已生成"
            }
            
            $RunTaskFile = Join-Path $JavaSdkDir "com\tsinghua\thrift\api\RunTask.java"
            if (Test-Path $RunTaskFile) {
                Write-LogSuccess "✓ RunTask.java 已生成"
            }
            
            return $true
        } else {
            Write-LogError "Java SDK生成失败"
            return $false
        }
    } catch {
        Write-LogError "生成Java SDK时出错: $($_.Exception.Message)"
        return $false
    }
}

# 生成Go SDK
function New-GoSdk {
    Write-LogInfo "生成Go SDK..."
    
    try {
        Push-Location $ProjectRoot
        $null = & thrift --gen go -out $GoSdkDir $ThriftFile
        Pop-Location
        
        if ($LASTEXITCODE -eq 0) {
            # 统计生成的文件数
            $GoFiles = (Get-ChildItem -Path "$GoSdkDir\tsinghua\api" -Filter "*.go" -ErrorAction SilentlyContinue).Count
            Write-LogSuccess "Go SDK生成成功，共 $GoFiles 个文件"
            
            # 检查关键文件
            $ApiFile = Join-Path $GoSdkDir "tsinghua\api\api.go"
            if (Test-Path $ApiFile) {
                Write-LogSuccess "✓ api.go 已生成"
            }
            
            return $true
        } else {
            Write-LogError "Go SDK生成失败"
            return $false
        }
    } catch {
        Write-LogError "生成Go SDK时出错: $($_.Exception.Message)"
        return $false
    }
}

# 生成Python SDK
function New-PythonSdk {
    Write-LogInfo "生成Python SDK..."
    
    try {
        Push-Location $ProjectRoot
        $null = & thrift --gen py -out $PythonSdkDir $ThriftFile
        Pop-Location
        
        if ($LASTEXITCODE -eq 0) {
            # 统计生成的文件数
            $PythonFiles = (Get-ChildItem -Path "$PythonSdkDir\tsinghua\api" -Filter "*.py" -ErrorAction SilentlyContinue).Count
            Write-LogSuccess "Python SDK生成成功，共 $PythonFiles 个文件"
            
            # 检查关键文件
            $TtypesFile = Join-Path $PythonSdkDir "tsinghua\api\ttypes.py"
            if (Test-Path $TtypesFile) {
                Write-LogSuccess "✓ ttypes.py 已生成"
            }
            
            return $true
        } else {
            Write-LogError "Python SDK生成失败"
            return $false
        }
    } catch {
        Write-LogError "生成Python SDK时出错: $($_.Exception.Message)"
        return $false
    }
}

# 验证生成的SDK
function Test-GeneratedSdks {
    Write-LogInfo "验证生成的SDK..."
    
    # 验证Java SDK
    $JavaApiFile = Join-Path $JavaSdkDir "com\tsinghua\thrift\api\ApiService.java"
    if (Test-Path $JavaApiFile) {
        $JavaSize = (Get-Item $JavaApiFile).Length
        Write-LogSuccess "✓ Java ApiService.java ($JavaSize bytes)"
    }
    
    # 验证Go SDK
    $GoApiFile = Join-Path $GoSdkDir "tsinghua\api\api.go"
    if (Test-Path $GoApiFile) {
        $GoSize = (Get-Item $GoApiFile).Length
        Write-LogSuccess "✓ Go api.go ($GoSize bytes)"
    }
    
    # 验证Python SDK
    $PythonApiFile = Join-Path $PythonSdkDir "tsinghua\api\ApiService.py"
    if (Test-Path $PythonApiFile) {
        $PythonSize = (Get-Item $PythonApiFile).Length
        Write-LogSuccess "✓ Python ApiService.py ($PythonSize bytes)"
    }
}

# 显示生成结果
function Show-Results {
    Write-Host ""
    Write-Host "===================================" -ForegroundColor $Colors.Green
    Write-Host "🎉 SDK生成完成！" -ForegroundColor $Colors.Green
    Write-Host "===================================" -ForegroundColor $Colors.Green
    Write-Host ""
    Write-Host "📁 生成位置:" -ForegroundColor $Colors.White
    Write-Host "  Java SDK:  $JavaSdkDir\com\tsinghua\thrift\api\" -ForegroundColor $Colors.White
    Write-Host "  Go SDK:    $GoSdkDir\tsinghua\api\" -ForegroundColor $Colors.White
    Write-Host "  Python SDK: $PythonSdkDir\tsinghua\api\" -ForegroundColor $Colors.White
    Write-Host ""
    Write-Host "📋 新增API支持:" -ForegroundColor $Colors.White
    Write-Host "  ✅ ParsingRule - 解析规则管理 (包含example字段)" -ForegroundColor $Colors.Green
    Write-Host "  ✅ RunTask - 运行任务管理" -ForegroundColor $Colors.Green
    Write-Host "  ✅ ExtractModelFileRequest - 模型文件提取" -ForegroundColor $Colors.Green
    Write-Host ""
    Write-Host "🚀 使用方法:" -ForegroundColor $Colors.White
    Write-Host "  启动应用: mvn spring-boot:run" -ForegroundColor $Colors.White
    Write-Host "  Thrift服务将在端口9090启动" -ForegroundColor $Colors.White
    Write-Host ""
    Write-Host "📖 更多信息请查看各SDK模块的README.md文件" -ForegroundColor $Colors.White
}

# 清理旧文件
function Remove-OldFiles {
    Write-LogInfo "清理旧的生成文件..."
    
    # 清理Java SDK
    $JavaApiDir = Join-Path $JavaSdkDir "com\tsinghua\thrift\api"
    if (Test-Path $JavaApiDir) {
        Remove-Item -Recurse -Force $JavaApiDir
        Write-LogInfo "已清理旧的Java SDK文件"
    }
    
    # 清理Go SDK
    $GoTsinghuaDir = Join-Path $GoSdkDir "tsinghua"
    if (Test-Path $GoTsinghuaDir) {
        Remove-Item -Recurse -Force $GoTsinghuaDir
        Write-LogInfo "已清理旧的Go SDK文件"
    }
    
    # 清理Python SDK
    $PythonTsinghuaDir = Join-Path $PythonSdkDir "tsinghua"
    if (Test-Path $PythonTsinghuaDir) {
        Remove-Item -Recurse -Force $PythonTsinghuaDir
        Write-LogInfo "已清理旧的Python SDK文件"
    }
}

# 显示帮助信息
function Show-Help {
    Write-Host "DataModelGov Thrift SDK 生成脚本 (PowerShell版本)" -ForegroundColor $Colors.White
    Write-Host ""
    Write-Host "用法:" -ForegroundColor $Colors.White
    Write-Host "  .\generate-sdk.ps1 [选项]" -ForegroundColor $Colors.White
    Write-Host ""
    Write-Host "选项:" -ForegroundColor $Colors.White
    Write-Host "  -Help       显示帮助信息" -ForegroundColor $Colors.White
    Write-Host "  -Clean      仅清理旧文件，不生成新SDK" -ForegroundColor $Colors.White
    Write-Host "  -Validate    仅验证Thrift文件，不生成SDK" -ForegroundColor $Colors.White
    Write-Host ""
    Write-Host "示例:" -ForegroundColor $Colors.White
    Write-Host "  .\generate-sdk.ps1              # 完整生成SDK" -ForegroundColor $Colors.White
    Write-Host "  .\generate-sdk.ps1 -Clean      # 清理旧文件" -ForegroundColor $Colors.White
    Write-Host "  .\generate-sdk.ps1 -Validate   # 验证Thrift文件" -ForegroundColor $Colors.White
}

# 主函数
function Main {
    Write-Host "===================================" -ForegroundColor $Colors.Blue
    Write-Host "🚀 DataModelGov Thrift SDK 生成器" -ForegroundColor $Colors.Blue
    Write-Host "===================================" -ForegroundColor $Colors.Blue
    Write-Host ""
    
    # 显示帮助
    if ($Help) {
        Show-Help
        return
    }
    
    # 仅清理模式
    if ($Clean) {
        Remove-OldFiles
        Write-LogSuccess "清理完成"
        return
    }
    
    # 仅验证模式
    if ($Validate) {
        if (-not (Test-ThriftEnvironment)) {
            exit 1
        }
        if (-not (Test-ThriftFile)) {
            exit 1
        }
        Write-LogSuccess "验证通过"
        return
    }
    
    # 完整生成流程
    if (-not (Test-ThriftEnvironment)) {
        exit 1
    }
    if (-not (Test-ThriftFile)) {
        exit 1
    }
    
    Remove-OldFiles
    
    if (-not (New-OutputDirectories)) {
        exit 1
    }
    
    # 生成各语言SDK
    if (-not (New-JavaSdk)) {
        exit 1
    }
    if (-not (New-GoSdk)) {
        exit 1
    }
    if (-not (New-PythonSdk)) {
        exit 1
    }
    
    # 验证和显示结果
    Test-GeneratedSdks
    Show-Results
}

# 执行主函数
Main
