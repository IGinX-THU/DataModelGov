# DataModelGov 客户端示例

本目录包含 DataModelGov 各语言客户端的使用示例，专注于演示SDK的使用方法。

## 📁 目录结构

```
datamodelgov-examples/
├── java-client-example/          # Java 客户端示例
│   ├── SimpleJavaClientExample.java  # 简单SDK调用示例
│   └── JavaClientExample.java         # Web服务示例
├── go-client-example/            # Go 客户端示例
│   ├── simple_example.go             # 简单SDK调用示例
│   └── main.go                      # Web服务示例
├── python-client-example/        # Python 客户端示例
│   ├── simple_example.py             # 简单SDK调用示例
│   └── main.py                      # Web服务示例
└── README.md                     # 本文档
```

## 🚀 快速开始

### **运行简单SDK示例（推荐）**

#### **Java 简单示例**
```bash
cd java-client-example
javac -cp "datamodelgov-sdk-java-1.0.0.jar" src/main/java/com/tsinghua/datamodelgov/examples/SimpleJavaClientExample.java
java -cp ".:datamodelgov-sdk-java-1.0.0.jar" com.tsinghua.datamodelgov.examples.SimpleJavaClientExample
```

#### **Go 简单示例**
```bash
cd go-client-example
go run simple_example.go
```

#### **Python 简单示例**
```bash
cd python-client-example
python simple_example.py
```

### **运行Web服务示例**

#### **Java Web示例**
```bash
cd java-client-example
mvn spring-boot:run
```

#### **Go Web示例**
```bash
cd go-client-example
go run main.go
```

#### **Python Web示例**
```bash
cd python-client-example
python main.py
```

## 📋 示例类型

### **1. 简单SDK调用示例**
- ✅ **专注SDK使用** - 只演示SDK方法调用
- ✅ **命令行运行** - 直接运行，无需Web服务器
- ✅ **完整演示** - 涵盖所有SDK功能
- ✅ **JSON序列化** - 展示数据处理

### **2. Web服务示例**
- ✅ **RESTful API** - HTTP接口演示
- ✅ **实际应用** - 模拟真实使用场景
- ✅ **错误处理** - 完整的异常处理
- ✅ **日志记录** - 详细的调用日志

## 🎯 SDK功能演示

所有示例都演示以下SDK功能：

### **数据模型管理**
- ✅ **创建模型** - `createModel()`
- ✅ **查询模型** - `getModels()`, `getModel()`
- ✅ **更新模型** - `updateModel()`
- ✅ **删除模型** - `deleteModel()`

### **数据分析**
- ✅ **数据分析** - `analyzeData()`

### **客户端管理**
- ✅ **客户端初始化** - 构造函数
- ✅ **配置管理** - 基础配置
- ✅ **错误处理** - 异常捕获

## 📚 简单示例输出

### **Java 简单示例输出**
```
=== DataModelGov Java SDK 客户端示例 ===

1. 创建客户端
SDK调用: DataModelClient client = new DataModelClient("http://localhost:8080")
客户端创建成功

2. 创建数据模型
SDK调用: client.createModel(model)
创建成功: model_1234567890
模型名称: 用户模型
模型描述: 用户数据模型示例

3. 查询数据模型
SDK调用: client.getModels()
查询到 2 个模型:
  - 用户模型 (model_1234567890)
  - 订单模型 (model_1234567891)

...（更多输出）
```

### **Go 简单示例输出**
```
=== DataModelGov Go SDK 客户端示例 ===

1. 创建客户端
SDK调用: client := NewDataModelGovClient("http://localhost:8080")
客户端创建成功

2. 创建数据模型
SDK调用: CreateModel() - 创建数据模型: {...}
创建成功: model_1234567890
模型名称: 用户模型
模型描述: 用户数据模型示例

...（更多输出）
```

### **Python 简单示例输出**
```
=== DataModelGov Python SDK 客户端示例 ===

1. 创建客户端
SDK调用: client = DataModelGovClient("http://localhost:8080")
客户端创建成功

2. 创建数据模型
SDK调用: create_model() - 创建数据模型: {...}
创建成功: model_1234567890
模型名称: 用户模型
模型描述: 用户数据模型示例

...（更多输出）
```

## 🔧 SDK调用对比

### **Java SDK**
```java
// 创建客户端
DataModelClient client = new DataModelClient("http://localhost:8080");

// 创建模型
Model model = new Model();
model.setName("用户模型");
Model created = client.createModel(model);

// 查询模型
Model[] models = client.getModels();
```

### **Go SDK**
```go
// 创建客户端
client := datamodelgov.NewClient("http://localhost:8080")

// 创建模型
model := &datamodelgov.Model{Name: "用户模型"}
created, err := client.CreateModel(model)

// 查询模型
models, err := client.GetModels()
```

### **Python SDK**
```python
# 创建客户端
client = DataModelClient("http://localhost:8080")

# 创建模型
model = Model(name="用户模型")
created = client.create_model(model)

# 查询模型
models = client.get_models()
```

## 🛠️ 环境要求

### **简单示例**
- **Java**: JDK 8+
- **Go**: Go 1.19+
- **Python**: Python 3.8+

### **Web示例**
- **Java**: JDK 8+ + Maven
- **Go**: Go 1.19+ + gorilla/mux
- **Python**: Python 3.8+ + Flask

## 📝 开发建议

### **1. 先运行简单示例**
建议先运行简单示例了解SDK基本用法：
```bash
# Java
java -cp "datamodelgov-sdk-java-1.0.0.jar" SimpleJavaClientExample

# Go
go run simple_example.go

# Python
python simple_example.py
```

### **2. 集成到项目**
将示例代码集成到实际项目时：
- 移除模拟代码
- 替换为真实SDK调用
- 添加适当的错误处理
- 配置生产环境参数

### **3. 参考Web示例**
Web示例展示了更完整的使用场景，包括：
- RESTful API设计
- 错误处理策略
- 日志记录规范
- 响应格式标准化

## 🔍 故障排除

### **常见问题**

#### **1. SDK依赖缺失**
```bash
# Java
mvn clean install -P java-sdk-only

# Go
go mod tidy

# Python
pip install datamodelgov-sdk-python
```

#### **2. 服务连接失败**
- 检查DataModelGov服务是否启动
- 验证服务地址和端口
- 检查网络连接

#### **3. 认证失败**
- 检查认证token配置
- 验证API权限
- 确认token有效期

## 📞 技术支持

- **SDK文档**: 查看各SDK目录下的README.md
- **API参考**: 查看项目API文档
- **问题反馈**: 在项目仓库中提交Issue

---

**推荐从简单示例开始，快速掌握DataModelGov SDK的使用方法！** 🚀
