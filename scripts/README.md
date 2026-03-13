# DataModelGov SDK 生成脚本

这个目录包含了用于生成DataModelGov Thrift SDK的一键生成脚本。

## 📁 文件说明

- `generate-sdk.sh` - Linux/macOS Bash脚本
- `generate-sdk.ps1` - Windows PowerShell脚本
- `generate-sdk.bat` - Windows 批处理脚本
- `README.md` - 本说明文档

## 🚀 使用方法

### Windows (批处理)

```cmd
# 进入scripts目录
cd scripts

# 完整生成SDK
generate-sdk.bat

# 仅验证Thrift文件
generate-sdk.bat -validate

# 仅清理旧文件
generate-sdk.bat -clean

# 显示帮助
generate-sdk.bat -help
```

### Windows (PowerShell)

```powershell
# 进入scripts目录
cd scripts

# 完整生成SDK
.\generate-sdk.ps1

# 仅验证Thrift文件
.\generate-sdk.ps1 -Validate

# 仅清理旧文件
.\generate-sdk.ps1 -Clean

# 显示帮助
.\generate-sdk.ps1 -Help
```

### Linux/macOS (Bash)

```bash
# 进入scripts目录
cd scripts

# 给脚本执行权限
chmod +x generate-sdk.sh

# 完整生成SDK
./generate-sdk.sh

# 仅验证Thrift文件
./generate-sdk.sh --validate

# 仅清理旧文件
./generate-sdk.sh --clean

# 显示帮助
./generate-sdk.sh --help
```

## 📋 脚本对比

| 特性 | 批处理脚本 | PowerShell脚本 | Bash脚本 |
|------|------------|----------------|----------|
| **平台** | Windows | Windows | Linux/macOS |
| **依赖** | 无 | PowerShell 5.1+ | Bash 4.0+ |
| **彩色输出** | ❌ | ✅ | ✅ |
| **错误处理** | 基础 | 完善 | 完善 |
| **文件统计** | ✅ | ✅ | ✅ |
| **进度显示** | ✅ | ✅ | ✅ |
| **推荐使用** | ✅ | ✅ | ✅ |

> 💡 **推荐**: Windows用户优先使用批处理脚本，简单直接；需要更高级功能时可使用PowerShell脚本。

## 📋 脚本功能

### 🔧 环境检查
- 自动检查Thrift编译器是否安装
- 验证Thrift版本
- 检查PATH配置

### ✅ 文件验证
- 验证Thrift IDL文件语法
- 检查文件是否存在
- 确保文件可读

### 🏗️ SDK生成
- **Java SDK**: 生成到 `datamodelgov-sdk-java/src/main/java/`
- **Go SDK**: 生成到 `datamodelgov-sdk-go/src/`
- **Python SDK**: 生成到 `datamodelgov-sdk-python/src/`

### 🧹 清理功能
- 自动清理旧的生成文件
- 确保干净的生成环境

### ✅ 验证功能
- 检查关键文件是否生成
- 统计生成的文件数量
- 验证文件大小

## 📊 生成结果

脚本成功执行后，将生成以下文件：

### Java SDK
```
datamodelgov-sdk-java/src/main/java/com/tsinghua/thrift/api/
├── ApiService.java (1.3MB) - 主服务接口
├── ParsingRule.java (27KB) - 解析规则实体
├── RunTask.java (60KB) - 运行任务实体
├── RunTaskRequest.java (38KB) - 任务请求实体
├── RunTaskQueryRequest.java (34KB) - 任务查询实体
├── ParsingRulesQueryRequest.java (20KB) - 解析规则查询实体
├── ExtractModelFileRequest.java (16KB) - 模型文件提取实体
└── ... (其他实体类)
```

### Go SDK
```
datamodelgov-sdk-go/src/tsinghua/api/
├── api.go (630KB) - 主服务接口
├── api-consts.go (586B) - 常量定义
└── api_service-remote/ - 远程服务
```

### Python SDK
```
datamodelgov-sdk-python/src/tsinghua/api/
├── ApiService.py (250KB) - 主服务接口
├── ttypes.py (80KB) - 类型定义
├── constants.py (403B) - 常量定义
└── ApiService-remote (12KB) - 远程服务
```

## 🎯 新增API支持

生成的SDK包含以下新增的API：

### 解析规则管理 (ParsingRules)
- `saveParsingRule()` - 保存解析规则
- `queryParsingRules()` - 查询解析规则
- `countParsingRules()` - 统计解析规则
- `getParsingRule()` - 获取解析规则详情
- `deleteParsingRule()` - 删除解析规则

### 运行任务管理 (RunTask)
- `runTask()` - 运行任务
- `validateTaskUniqueness()` - 验证任务唯一性
- `stopTask()` - 停止任务
- `getTaskLog()` - 获取任务日志
- `queryTasks()` - 查询任务列表
- `countTasks()` - 统计任务数量
- `getTask()` - 获取任务详情
- `deleteTask()` - 删除任务

### 模型文件提取
- `extractModelFile()` - 提取模型文件

## ⚙️ 环境要求

### 必需
- **Thrift编译器** (版本 0.22.0+)
  - 下载地址: https://thrift.apache.org/download
  - 确保thrift在系统PATH中

### 可选
- **Java 8+** (用于Java SDK)
- **Go 1.16+** (用于Go SDK)
- **Python 3.7+** (用于Python SDK)

## 🔍 故障排除

### Thrift未找到
```
[ERROR] Thrift未安装或不在PATH中
```
**解决方案**: 安装Thrift并添加到PATH

### Thrift文件语法错误
```
[ERROR] Thrift文件语法错误
```
**解决方案**: 检查 `datamodelgov-server/src/main/resources/thrift/api.thrift` 文件语法

### 权限错误 (Linux/macOS)
```
Permission denied
```
**解决方案**: 
```bash
chmod +x generate-sdk.sh
```

### PowerShell执行策略错误 (Windows)
```
无法加载文件，因为在此系统上禁止运行脚本
```
**解决方案**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## 📝 使用示例

### 生成SDK后使用

```java
// Java示例
import com.tsinghua.thrift.api.*;

TSocket transport = new TSocket("localhost", 9090);
TBinaryProtocol protocol = new TBinaryProtocol(transport);
ApiService.Client client = new ApiService.Client(protocol);
transport.open();

// 调用新API
ParsingRule rule = new ParsingRule();
rule.setName("测试解析规则");
rule.setRegexPattern("# @(Input|Output): (.+)");
rule.setExample("# @Input: speed (float) - 车速");
Result result = client.saveParsingRule(rule);
```

```go
// Go示例
import "tsinghua/api"

transport, _ := thrift.NewTSocket("localhost", 9090)
protocol := thrift.NewTBinaryProtocolTransport(transport)
client := api.NewApiServiceClientFactory(protocol, transport)
transport.Open()

rule := &api.ParsingRule{
    Name:         "测试解析规则",
    RegexPattern: "# @(Input|Output): (.+)",
    Example:      "# @Input: speed (float) - 车速",
}
result, _ := client.SaveParsingRule(context.Background(), rule)
```

```python
# Python示例
from tsinghua.api import ApiService, ParsingRule

transport = TSocket.TSocket('localhost', 9090)
protocol = TBinaryProtocol.TBinaryProtocol(transport)
client = ApiService.Client(protocol)
transport.open()

rule = ParsingRule()
rule.name = "测试解析规则"
rule.regex_pattern = "# @(Input|Output): (.+)"
rule.example = "# @Input: speed (float) - 车速"
result = client.saveParsingRule(rule)
```

## 📞 技术支持

如果遇到问题，请检查：
1. Thrift编译器是否正确安装
2. 项目目录结构是否正确
3. 系统PATH配置是否正确
4. 查看脚本输出的错误信息

---

**版本**: v1.0.0  
**更新时间**: 2026-03-13
