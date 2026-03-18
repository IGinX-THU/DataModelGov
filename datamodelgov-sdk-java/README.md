# DataModelGov Java SDK

Java语言的DataModelGov SDK，提供数据模型管理和数据分析功能。

## 📦 安装

### **Maven依赖**
```xml
<dependency>
    <groupId>com.tsinghua</groupId>
    <artifactId>datamodelgov-sdk-java</artifactId>
    <version>1.0.0</version>
</dependency>
```

### **Gradle依赖**
```gradle
implementation 'com.tsinghua:datamodelgov-sdk-java:1.0.0'
```

### **手动安装**
```bash
# 下载jar包（需要先构建项目）
mvn clean install -P java-sdk-only

# 从本地仓库使用
java -cp "~/.m2/repository/com/tsinghua/datamodelgov-sdk-java/1.0.0/datamodelgov-sdk-java-1.0.0.jar" YourApp
```

## 🔧 配置

### **基本配置**
```java
import com.tsinghua.datamodelgov.sdk.DataModelClient;

// 创建客户端
DataModelClient client = new DataModelClient("http://localhost:8080");

// 设置认证（可选）
client.setAuthToken("your-auth-token");

// 设置超时时间（可选）
client.setTimeout(30000); // 30秒
```

### **高级配置**
```java
import com.tsinghua.datamodelgov.sdk.DataModelClient;
import com.tsinghua.datamodelgov.sdk.ClientConfig;

// 使用配置对象
ClientConfig config = new ClientConfig()
    .setBaseUrl("http://localhost:8080")
    .setAuthToken("your-token")
    .setTimeout(30000)
    .setRetryCount(3)
    .setLogLevel(LogLevel.INFO);

DataModelClient client = new DataModelClient(config);
```

## 🚀 快速开始

### **创建数据模型**
```java
import com.tsinghua.datamodelgov.sdk.Model;

Model model = new Model();
model.setName("用户模型");
model.setDescription("用户数据模型");
model.addField("name", "string");
model.addField("age", "int");

Model created = client.createModel(model);
System.out.println("模型ID: " + created.getId());
```

### **查询数据模型**
```java
// 查询所有模型
Model[] models = client.getModels();

// 按名称查询
Model[] userModels = client.getModels("用户模型");

// 按ID查询
Model model = client.getModel("model_123");
```

### **数据分析**
```java
import com.tsinghua.datamodelgov.sdk.AnalysisResult;

String[] data = {"张三", "25", "李四", "30"};
AnalysisResult result = client.analyzeData("model_123", data);

System.out.println("分析结果: " + result.getSummary());
System.out.println("记录数: " + result.getTotalRecords());
```

## 📋 API参考

### **DataModelClient**

#### **构造方法**
- `DataModelClient(String baseUrl)` - 创建客户端
- `DataModelClient(ClientConfig config)` - 使用配置创建客户端

#### **数据模型操作**
- `Model createModel(Model model)` - 创建数据模型
- `Model getModel(String modelId)` - 获取单个模型
- `Model[] getModels()` - 获取所有模型
- `Model[] getModels(String name)` - 按名称查询模型
- `Model updateModel(String modelId, Model model)` - 更新数据模型
- `void deleteModel(String modelId)` - 删除数据模型

#### **数据分析操作**
- `AnalysisResult analyzeData(String modelId, String[] data)` - 分析数据
- `AnalysisResult analyzeData(String modelId, InputStream data)` - 分析流数据
- `AnalysisStatus getAnalysisStatus(String analysisId)` - 获取分析状态

#### **配置方法**
- `void setAuthToken(String token)` - 设置认证令牌
- `void setTimeout(int timeout)` - 设置超时时间
- `void setRetryCount(int count)` - 设置重试次数

### **Model类**
```java
public class Model {
    private String id;           // 模型ID
    private String name;         // 模型名称
    private String description;  // 模型描述
    private Map<String, String> fields;  // 字段定义
    private Date createdAt;      // 创建时间
    private Date updatedAt;      // 更新时间
    
    // Getter和Setter方法
}
```

### **AnalysisResult类**
```java
public class AnalysisResult {
    private String analysisId;    // 分析ID
    private String modelId;       // 模型ID
    private String summary;       // 分析摘要
    private int totalRecords;      // 总记录数
    private Date analysisTime;    // 分析时间
    private Map<String, Object> details;  // 详细结果
    
    // Getter和Setter方法
}
```

## 🔐 认证配置

### **Token认证**
```java
client.setAuthToken("your-jwt-token");
```

### **API Key认证**
```java
client.setApiKey("your-api-key");
```

### **自定义认证**
```java
client.setAuthProvider(new AuthProvider() {
    @Override
    public String getAuthToken() {
        // 自定义认证逻辑
        return getCustomToken();
    }
});
```

## 🛠️ 环境要求

- **Java**: JDK 8+
- **Maven**: 3.6+（如果使用Maven）
- **网络**: 需要访问DataModelGov服务

## 📝 最佳实践

### **1. 连接池配置**
```java
ClientConfig config = new ClientConfig()
    .setMaxConnections(100)
    .setConnectionTimeout(5000)
    .setSocketTimeout(30000);
```

### **2. 错误处理**
```java
try {
    Model model = client.getModel("invalid-id");
} catch (ModelNotFoundException e) {
    System.err.println("模型不存在: " + e.getMessage());
} catch (DataModelGovException e) {
    System.err.println("SDK错误: " + e.getMessage());
}
```

### **3. 资源管理**
```java
// 使用try-with-resources自动关闭连接
try (DataModelClient client = new DataModelClient("http://localhost:8080")) {
    // 使用客户端
    Model[] models = client.getModels();
}
```

## 🔍 故障排除

### **常见问题**

#### **1. 连接超时**
```java
// 增加超时时间
client.setTimeout(60000); // 60秒
```

#### **2. 认证失败**
```java
// 检查token是否有效
if (!client.isTokenValid()) {
    client.refreshToken();
}
```

#### **3. 模型不存在**
```java
// 先检查模型是否存在
if (client.modelExists("model_123")) {
    Model model = client.getModel("model_123");
}
```

### **日志配置**
```java
// 启用详细日志
ClientConfig config = new ClientConfig()
    .setLogLevel(LogLevel.DEBUG);

DataModelClient client = new DataModelClient(config);
```

## 📚 更多资源

- **完整API文档**: 查看项目源码中的API文档
- **示例代码**: 查看examples目录下的示例
- **问题反馈**: 在项目仓库中提交Issue

---

**开始使用DataModelGov Java SDK，轻松管理您的数据模型！** 🚀
