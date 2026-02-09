# DataModelGov
Web app for governing data and model

## 🎯 部署使用说明

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
1. **配置文件**：`config/application.yml` + `config/iginx-config.properties`
2. **默认配置**：JAR包内置配置

### 修改配置
修改解压后目录的 `config/` 目录下的配置文件

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
- **手动解压**: 适用于已解压的部署包
- **智能配置**: 自动检测配置文件
- **跨平台**: Windows和Linux/macOS通用
- **环境检测**: 自动检测Java环境

## 🔧 故障排除

### 启动失败
1. 确认已正确解压部署包
2. 检查 `app/data-model-gov-1.0.0.jar` 文件是否存在
3. 检查Java环境（如果未使用内嵌JRE）
4. 查看控制台错误信息

### 配置不生效
1. 确认配置文件路径正确
2. 检查YAML语法是否正确
3. 重启应用使配置生效

### 端口占用
1. 修改配置文件中的端口号
2. 或停止占用8080端口的其他程序
