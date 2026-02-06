# 数据与模型一体化管理软件 - 部署使用说明

## 🎯 使用方式

### 方式1：一键启动（推荐）
将以下文件放在同一目录，直接运行启动脚本：

```
deployment-directory/
├── data-model-gov-1.0.0-standalone.zip  # 部署包
├── config/                               # 配置文件目录（可选）
│   ├── application.yml                  # 主配置文件
│   └── iginx-config.properties          # IGinX配置文件
├── start.bat                            # Windows启动脚本
├── start.sh                             # Linux/macOS启动脚本
├── stop.bat                             # Windows停止脚本
└── stop.sh                              # Linux/macOS停止脚本
```

**使用方法**：
- Windows: 双击 `start.bat` 或命令行运行
- Linux/macOS: `./start.sh`

脚本会自动：
1. 检测并解压部署包到 `deployment/` 目录
2. 优先使用外部 `config/` 目录的配置文件
3. 启动应用

### 方式2：手动解压
手动解压部署包到任意目录，然后运行脚本：

```
extracted-directory/
├── jre/                    # Java运行环境
├── lib/                    # 依赖库
├── static/                 # 前端资源
├── config/                 # 配置文件
├── bin/                    # 脚本目录
│   ├── start.bat
│   ├── start.sh
│   ├── stop.bat
│   └── stop.sh
└── app/                    # 应用程序
    └── data-model-gov-1.0.0.jar
```

**使用方法**：
- Windows: 进入 `bin/` 目录，运行 `start.bat`
- Linux/macOS: 进入 `bin/` 目录，运行 `./start.sh`

## 🚀 启动和停止

### 启动应用

**Windows:**
```cmd
start.bat
```

**Linux/macOS:**
```bash
chmod +x start.sh
./start.sh
```

### 停止应用

**Windows:**
```cmd
stop.bat
```

**Linux/macOS:**
```bash
chmod +x stop.sh
./stop.sh
```

## ⚙️ 配置文件

### 配置文件优先级
1. **外部配置**：`../config/application.yml` + `../config/config/iginx-config.properties` （方式1）
2. **内部配置**：`config/application.yml` + `config/iginx-config.properties` （方式2）
3. **默认配置**：JAR包内置配置

### 修改配置
- **方式1**：直接修改 `config/` 目录下的配置文件
- **方式2**：修改解压后目录的 `config/` 目录下的配置文件

#### 主配置文件 (application.yml)
```yaml
server:
  port: 8080              # 服务端口

spring:
  profiles:
    active: standalone    # 运行模式

logging:
  level:
    root: INFO           # 日志级别
  file:
    name: logs/app.log   # 日志文件
```

#### IGinX配置文件 (iginx-config.properties)
```properties
# IGinX连接配置
iginx.ip=127.0.0.1
iginx.port=6667
iginx.username=root
iginx.password=root
iginx.timeout=30000

# 存储引擎配置
storageEngineList=127.0.0.1#6668#filesystem#dir=./data/iginx#iginx_port=8080#has_data=false#is_read_only=false
```

## 🌐 访问地址

启动成功后访问：http://localhost:8080

## 📁 目录结构说明

### 部署包内容
- **jre/**: 内嵌Java运行环境
- **lib/**: 所有依赖库
- **static/**: 前端静态资源
- **config/**: 默认配置文件
- **app/**: 应用程序JAR
- **bin/**: 启动停止脚本

### 脚本特性
- **自动解压**: 检测ZIP包并自动解压
- **智能配置**: 优先使用外部配置文件
- **跨平台**: Windows和Linux/macOS通用
- **环境检测**: 自动检测Java环境

## 🔧 故障排除

### 启动失败
1. 检查ZIP包是否存在且完整
2. 确保有足够的磁盘空间解压
3. 检查Java环境（如果未使用内嵌JRE）
4. 查看控制台错误信息

### 配置不生效
1. 确认配置文件路径正确
2. 检查YAML语法是否正确
3. 重启应用使配置生效

### 端口占用
1. 修改配置文件中的端口号
2. 或停止占用8080端口的其他程序

## 💡 最佳实践

1. **生产环境**：使用方式1，便于配置管理和版本升级
2. **开发测试**：使用方式2，便于调试和修改
3. **配置管理**：将配置文件放在外部目录，便于修改
4. **日志监控**：定期检查 `logs/` 目录的日志文件
