# DataModelGov Python SDK

Python语言的DataModelGov SDK，提供数据模型管理和数据分析功能。

## 📦 安装

### **使用pip**
```bash
# 需要先构建Python SDK
cd datamodelgov-sdk-python
pip install -e .
```

### **使用conda**
```bash
# 从本地包安装
cd datamodelgov-sdk-python
conda develop .
```

### **从源码安装**
```bash
# 克隆当前项目
git clone <项目仓库地址>

# 进入Python SDK目录
cd DataModelGov/datamodelgov-sdk-python

# 安装
pip install -e .
```

### **开发环境安装**
```bash
# 安装开发依赖
pip install -e .[dev]

# 安装测试依赖
pip install -e .[test]
```

## 🔧 配置

### **基本配置**
```python
from datamodelgov import DataModelClient

# 创建客户端
client = DataModelClient("http://localhost:8080")

# 设置认证（可选）
client.set_auth_token("your-auth-token")

# 设置超时时间（可选）
client.set_timeout(30)  # 30秒
```

### **高级配置**
```python
from datamodelgov import DataModelClient, ClientConfig

# 使用配置对象
config = ClientConfig(
    base_url="http://localhost:8080",
    auth_token="your-token",
    timeout=30,
    retry_count=3,
    log_level="INFO"
)

client = DataModelClient(config)
```

### **环境变量配置**
```bash
export DATAMODELGOV_BASE_URL="http://localhost:8080"
export DATAMODELGOV_AUTH_TOKEN="your-token"
export DATAMODELGOV_TIMEOUT="30"
export DATAMODELGOV_LOG_LEVEL="INFO"
```

```python
# 从环境变量创建客户端
client = DataModelClient.from_env()
```

## 🚀 快速开始

### **创建数据模型**
```python
from datamodelgov import DataModelClient, Model

client = DataModelClient("http://localhost:8080")

model = Model(
    name="用户模型",
    description="用户数据模型",
    fields={
        "name": "string",
        "age": "int"
    }
)

created = client.create_model(model)
print(f"模型ID: {created.id}")
```

### **查询数据模型**
```python
# 查询所有模型
models = client.get_models()

# 按名称查询
user_models = client.get_models(name="用户模型")

# 按ID查询
model = client.get_model("model_123")
```

### **数据分析**
```python
from datamodelgov import DataModelClient

client = DataModelClient("http://localhost:8080")

data = ["张三", "25", "李四", "30"]
result = client.analyze_data("model_123", data)

print(f"分析结果: {result.summary}")
print(f"记录数: {result.total_records}")
```

## 📋 API参考

### **DataModelClient类**

#### **构造方法**
- `DataModelClient(base_url: str)` - 创建客户端
- `DataModelClient(config: ClientConfig)` - 使用配置创建客户端
- `DataModelClient.from_env()` - 从环境变量创建客户端

#### **数据模型操作**
- `create_model(model: Model) -> Model` - 创建数据模型
- `get_model(model_id: str) -> Model` - 获取单个模型
- `get_models(name: str = None) -> List[Model]` - 获取模型列表
- `update_model(model_id: str, model: Model) -> Model` - 更新数据模型
- `delete_model(model_id: str) -> None` - 删除数据模型
- `model_exists(model_id: str) -> bool` - 检查模型是否存在

#### **数据分析操作**
- `analyze_data(model_id: str, data: List[str]) -> AnalysisResult` - 分析数据
- `analyze_data_stream(model_id: str, data: IO) -> AnalysisResult` - 分析流数据
- `get_analysis_status(analysis_id: str) -> AnalysisStatus` - 获取分析状态

#### **配置方法**
- `set_auth_token(token: str)` - 设置认证令牌
- `set_timeout(timeout: int)` - 设置超时时间
- `set_retry_count(count: int)` - 设置重试次数

### **Model类**
```python
@dataclass
class Model:
    id: str                    # 模型ID
    name: str                  # 模型名称
    description: str          # 模型描述
    fields: Dict[str, str]     # 字段定义
    created_at: datetime       # 创建时间
    updated_at: datetime       # 更新时间
```

### **AnalysisResult类**
```python
@dataclass
class AnalysisResult:
    analysis_id: str                    # 分析ID
    model_id: str                       # 模型ID
    summary: str                        # 分析摘要
    total_records: int                  # 总记录数
    analysis_time: datetime              # 分析时间
    details: Dict[str, Any]            # 详细结果
```

## 🔐 认证配置

### **Token认证**
```python
client.set_auth_token("your-jwt-token")
```

### **API Key认证**
```python
client.set_api_key("your-api-key")
```

### **自定义认证**
```python
def auth_provider():
    # 自定义认证逻辑
    return get_custom_token()

client.set_auth_provider(auth_provider)
```

## 🛠️ 环境要求

- **Python**: Python 3.8+
- **依赖**: requests, pydantic, typing-extensions
- **网络**: 需要访问DataModelGov服务

### **依赖管理**
```bash
# 查看已安装的包
pip show datamodelgov-sdk-python

# 更新本地包
cd datamodelgov-sdk-python
pip install -e .

# 重新安装
pip install -e . --force-reinstall
```

## 📝 最佳实践

### **1. 连接池配置**
```python
config = ClientConfig(
    max_connections=100,
    connection_timeout=5,
    socket_timeout=30
)
client = DataModelClient(config)
```

### **2. 错误处理**
```python
from datamodelgov.exceptions import ModelNotFoundError, DataModelGovError

try:
    model = client.get_model("invalid-id")
except ModelNotFoundError:
    print("模型不存在")
except DataModelGovError as e:
    print(f"SDK错误: {e}")
```

### **3. 资源管理**
```python
# 使用上下文管理器
with DataModelClient("http://localhost:8080") as client:
    models = client.get_models()
    # 自动关闭连接
```

### **4. 异步支持**
```python
import asyncio
from datamodelgov import AsyncDataModelClient

async def main():
    client = AsyncDataModelClient("http://localhost:8080")
    
    # 异步操作
    models = await client.get_models()
    print(f"获取到 {len(models)} 个模型")
    
    await client.close()

asyncio.run(main())
```

### **5. 批量操作**
```python
# 批量创建模型
models = [
    Model(name=f"模型_{i}", description=f"测试模型_{i}")
    for i in range(10)
]

created_models = client.batch_create_models(models)
print(f"批量创建了 {len(created_models)} 个模型")
```

## 🔍 故障排除

### **常见问题**

#### **1. 连接超时**
```python
# 增加超时时间
client.set_timeout(60)  # 60秒
```

#### **2. 认证失败**
```python
# 检查token是否有效
if not client.is_token_valid():
    client.refresh_token()
```

#### **3. 模型不存在**
```python
# 先检查模型是否存在
if client.model_exists("model_123"):
    model = client.get_model("model_123")
```

### **日志配置**
```python
import logging

# 启用详细日志
logging.basicConfig(level=logging.DEBUG)

# 或使用SDK内置日志
client.set_log_level("DEBUG")
```

### **性能调优**
```python
# 启用连接复用
config = ClientConfig(
    enable_connection_pool=True,
    max_idle_connections=20,
    idle_timeout=90
)
```

## 🧪 测试

### **运行测试**
```bash
# 运行所有测试
pytest

# 运行特定测试
pytest tests/test_client.py

# 运行测试并生成覆盖率报告
pytest --cov=datamodelgov tests/
```

### **测试配置**
```python
# 测试环境配置
import os
os.environ['DATAMODELGOV_BASE_URL'] = 'http://localhost:8080'
os.environ['DATAMODELGOV_AUTH_TOKEN'] = 'test-token'

# 使用测试客户端
from datamodelgov.testing import TestClient
client = TestClient()
```

## 📚 更多资源

- **完整API文档**: 查看项目源码中的API文档
- **示例代码**: 查看examples目录下的示例
- **问题反馈**: 在项目仓库中提交Issue

---

**开始使用DataModelGov Python SDK，轻松管理您的数据模型！** 🚀
