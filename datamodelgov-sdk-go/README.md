# DataModelGov Go SDK

Go语言的DataModelGov SDK，提供数据模型管理和数据分析功能。

## 📦 安装

### **使用go get**
```bash
# 需要先构建Go SDK
cd datamodelgov-sdk-go
go mod init datamodelgov-sdk-go
go build
```

### **手动安装**
```bash
# 克隆当前项目
git clone <项目仓库地址>

# 进入Go SDK目录
cd DataModelGov/datamodelgov-sdk-go

# 构建SDK
go build
```

### **在项目中使用**
```go
module your-project

go 1.19

require (
    // 使用本地路径引用
    ./datamodelgov-sdk-go v1.0.0
)
```

## 🔧 配置

### **基本配置**
```go
package main

import (
    "github.com/tsinghua/datamodelgov-go-sdk"
)

func main() {
    // 创建客户端
    client := datamodelgov.NewClient("http://localhost:8080")
    
    // 设置认证（可选）
    client.SetAuthToken("your-auth-token")
    
    // 设置超时时间（可选）
    client.SetTimeout(30 * time.Second)
}
```

### **高级配置**
```go
package main

import (
    "time"
    // 使用本地包路径
    "./datamodelgov-sdk-go"
    "./datamodelgov-sdk-go/config"
)

func main() {
    // 使用配置对象
    cfg := &config.ClientConfig{
        BaseURL:     "http://localhost:8080",
        AuthToken:   "your-token",
        Timeout:     30 * time.Second,
        RetryCount:  3,
        LogLevel:    config.LogLevelInfo,
    }
    
    client := datamodelgov.NewClientWithConfig(cfg)
}
```

## 🚀 快速开始

### **创建数据模型**
```go
package main

import (
    "fmt"
    // 使用本地包路径
    "./datamodelgov-sdk-go"
)

func main() {
    client := datamodelgov.NewClient("http://localhost:8080")
    
    model := &datamodelgov.Model{
        Name:        "用户模型",
        Description: "用户数据模型",
        Fields: map[string]string{
            "name": "string",
            "age":  "int",
        },
    }
    
    created, err := client.CreateModel(model)
    if err != nil {
        panic(err)
    }
    
    fmt.Printf("模型ID: %s\n", created.ID)
}
```

### **查询数据模型**
```go
// 查询所有模型
models, err := client.GetModels()
if err != nil {
    panic(err)
}

// 按名称查询
userModels, err := client.GetModelsByName("用户模型")
if err != nil {
    panic(err)
}

// 按ID查询
model, err := client.GetModel("model_123")
if err != nil {
    panic(err)
}
```

### **数据分析**
```go
data := []string{"张三", "25", "李四", "30"}

result, err := client.AnalyzeData("model_123", data)
if err != nil {
    panic(err)
}

fmt.Printf("分析结果: %s\n", result.Summary)
fmt.Printf("记录数: %d\n", result.TotalRecords)
```

## 📋 API参考

### **Client结构体**

#### **构造函数**
- `NewClient(baseURL string) *Client` - 创建客户端
- `NewClientWithConfig(config *config.ClientConfig) *Client` - 使用配置创建客户端

#### **数据模型操作**
- `CreateModel(model *Model) (*Model, error)` - 创建数据模型
- `GetModel(modelID string) (*Model, error)` - 获取单个模型
- `GetModels() ([]*Model, error)` - 获取所有模型
- `GetModelsByName(name string) ([]*Model, error)` - 按名称查询模型
- `UpdateModel(modelID string, model *Model) (*Model, error)` - 更新数据模型
- `DeleteModel(modelID string) error` - 删除数据模型

#### **数据分析操作**
- `AnalyzeData(modelID string, data []string) (*AnalysisResult, error)` - 分析数据
- `AnalyzeDataStream(modelID string, data io.Reader) (*AnalysisResult, error)` - 分析流数据
- `GetAnalysisStatus(analysisID string) (*AnalysisStatus, error)` - 获取分析状态

#### **配置方法**
- `SetAuthToken(token string)` - 设置认证令牌
- `SetTimeout(timeout time.Duration)` - 设置超时时间
- `SetRetryCount(count int)` - 设置重试次数

### **Model结构体**
```go
type Model struct {
    ID          string            `json:"id"`
    Name        string            `json:"name"`
    Description string            `json:"description"`
    Fields      map[string]string `json:"fields"`
    CreatedAt   time.Time         `json:"createdAt"`
    UpdatedAt   time.Time         `json:"updatedAt"`
}
```

### **AnalysisResult结构体**
```go
type AnalysisResult struct {
    AnalysisID   string                 `json:"analysisId"`
    ModelID      string                 `json:"modelId"`
    Summary      string                 `json:"summary"`
    TotalRecords int                    `json:"totalRecords"`
    AnalysisTime time.Time              `json:"analysisTime"`
    Details      map[string]interface{} `json:"details"`
}
```

## 🔐 认证配置

### **Token认证**
```go
client.SetAuthToken("your-jwt-token")
```

### **API Key认证**
```go
client.SetAPIKey("your-api-key")
```

### **自定义认证**
```go
client.SetAuthProvider(func() (string, error) {
    // 自定义认证逻辑
    return getCustomToken(), nil
})
```

## 🛠️ 环境要求

- **Go**: Go 1.19+
- **网络**: 需要访问DataModelGov服务

## 📝 最佳实践

### **1. 连接池配置**
```go
cfg := &config.ClientConfig{
    MaxConnections:    100,
    ConnectionTimeout: 5 * time.Second,
    SocketTimeout:     30 * time.Second,
}
client := datamodelgov.NewClientWithConfig(cfg)
```

### **2. 错误处理**
```go
model, err := client.GetModel("invalid-id")
if err != nil {
    switch err.(type) {
    case *datamodelgov.ModelNotFoundError:
        fmt.Println("模型不存在")
    case *datamodelgov.APIError:
        fmt.Printf("API错误: %s\n", err.Error())
    default:
        fmt.Printf("未知错误: %s\n", err.Error())
    }
}
```

### **3. 资源管理**
```go
// 使用defer关闭连接
client := datamodelgov.NewClient("http://localhost:8080")
defer client.Close()

// 使用连接
models, err := client.GetModels()
```

### **4. 并发安全**
```go
var wg sync.WaitGroup
semaphore := make(chan struct{}, 10) // 限制并发数

for i := 0; i < 100; i++ {
    wg.Add(1)
    go func(id int) {
        defer wg.Done()
        
        semaphore <- struct{}{} // 获取信号量
        defer func() { <-semaphore }() // 释放信号量
        
        model, err := client.GetModel(fmt.Sprintf("model_%d", id))
        if err != nil {
            fmt.Printf("获取模型失败: %s\n", err.Error())
            return
        }
        
        fmt.Printf("模型: %s\n", model.Name)
    }(i)
}

wg.Wait()
```

## 🔍 故障排除

### **常见问题**

#### **1. 连接超时**
```go
// 增加超时时间
client.SetTimeout(60 * time.Second)
```

#### **2. 认证失败**
```go
// 检查token是否有效
if !client.IsTokenValid() {
    err := client.RefreshToken()
    if err != nil {
        panic(err)
    }
}
```

#### **3. 模型不存在**
```go
// 先检查模型是否存在
if client.ModelExists("model_123") {
    model, err := client.GetModel("model_123")
    // 使用模型
}
```

### **日志配置**
```go
// 启用详细日志
cfg := &config.ClientConfig{
    LogLevel: config.LogLevelDebug,
}
client := datamodelgov.NewClientWithConfig(cfg)
```

### **性能调优**
```go
// 启用连接复用
cfg := &config.ClientConfig{
    EnableConnectionPool: true,
    MaxIdleConnections:   20,
    IdleTimeout:          90 * time.Second,
}
```

## 📚 更多资源

- **完整API文档**: 查看项目源码中的API文档
- **示例代码**: 查看examples目录下的示例
- **问题反馈**: 在项目仓库中提交Issue

---

**开始使用DataModelGov Go SDK，轻松管理您的数据模型！** 🚀
