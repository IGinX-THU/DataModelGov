#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
DataModelGov Python Thrift SDK 客户端示例
使用真正的Thrift SDK进行API调用
"""

import sys
import os
import time
import logging
from thrift.transport import TSocket
from thrift.transport import TTransport
from thrift.protocol import TBinaryProtocol

# 添加SDK路径
sys.path.append(os.path.join(os.path.dirname(__file__), '../../datamodelgov-sdk-python/src'))

try:
    from tsinghua.api import ApiService
    from tsinghua.api.ttypes import ModelMeta, DataQueryRequest, AssociationRulesQueryRequest, StorageEngineInfo
except ImportError as e:
    print(f"导入SDK失败: {e}")
    print("请确保Python SDK已正确安装")
    sys.exit(1)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def main():
    print("=== DataModelGov Python Thrift SDK 客户端示例 ===\n")
    
    # 1. 创建Thrift连接
    print("1. 连接到DataModelGov服务端")
    try:
        transport = TSocket.TSocket('localhost', 9090)
        protocol = TBinaryProtocol.TBinaryProtocol(transport)
        client = ApiService.Client(protocol)
        transport.open()
        print("✅ 连接成功: localhost:9090")
        print()
    except Exception as e:
        print(f"❌ 连接失败: {e}")
        return
    
    try:
        # 2. 创建数据模型元数据
        print("2. 创建数据模型元数据")
        model_meta = ModelMeta()
        model_meta.name = "用户模型"
        model_meta.version = "1.0.0"
        model_meta.author = "data_scientist_001"
        model_meta.scene = "用户行为分析"
        model_meta.inputs = '{"age": "int", "income": "double"}'
        model_meta.outputs = '{"risk_score": "double", "category": "string"}'
        model_meta.timestamp = int(time.time())
        
        print(f"模型名称: {model_meta.name}")
        print(f"模型版本: {model_meta.version}")
        print(f"模型作者: {model_meta.author}")
        print()
        
        # 3. 调用保存模型元数据API
        print("3. 调用saveModelMeta API")
        try:
            save_result = client.saveModelMeta(model_meta)
            print(f"保存结果: Success={save_result.success}, Message={save_result.message}")
        except Exception as e:
            print(f"保存失败: {e}")
        print()
        
        # 4. 调用查询模型元数据API
        print("4. 调用getModelMeta API")
        try:
            retrieved_result = client.getModelMeta("用户模型", "1.0.0")
            print(f"查询结果: Success={retrieved_result.success}, Message={retrieved_result.message}")
            if retrieved_result.data:
                print(f"数据: {retrieved_result.data}")
        except Exception as e:
            print(f"查询失败: {e}")
        print()
        
        # 5. 创建数据查询请求
        print("5. 创建数据查询请求")
        query_request = DataQueryRequest()
        query_request.paths = ["root.device.temperature", "root.device.humidity"]
        query_request.start_time = int(time.time()) - 86400  # 24小时前
        query_request.end_time = int(time.time())
        
        print(f"查询路径: {query_request.paths}")
        print(f"时间范围: {query_request.start_time} - {query_request.end_time}")
        print()
        
        # 6. 调用数据查询API
        print("6. 调用queryData API")
        try:
            query_result = client.queryData(query_request)
            print(f"查询结果: Success={query_result.success}, Message={query_result.message}")
            if query_result.data:
                print(f"数据: {query_result.data}")
        except Exception as e:
            print(f"查询失败: {e}")
        print()
        
        # 7. 演示其他数据对象
        print("7. 演示其他数据对象")
        
        # 创建关联规则查询请求
        rules_query = AssociationRulesQueryRequest()
        rules_query.page_num = 1
        rules_query.page_size = 10
        rules_query.name = "用户行为规则"
        
        # 创建存储引擎信息
        storage_info = StorageEngineInfo()
        storage_info.id = 1
        storage_info.ip = "127.0.0.1"
        storage_info.port = 8080
        storage_info.type = 1  # IoTDB
        storage_info.schema_prefix = "root"
        storage_info.data_prefix = "data"
        
        print(f"关联规则查询: PageNum={rules_query.page_num}, PageSize={rules_query.page_size}")
        print(f"存储引擎信息: IP={storage_info.ip}:{storage_info.port}, Type={storage_info.type}")
        print()
        
        # 8. 演示字段枚举
        print("8. SDK字段枚举")
        print("ModelMeta字段:")
        if hasattr(ModelMeta, 'THRIFT_SPEC'):
            for field_id in ModelMeta.THRIFT_SPEC:
                print(f"  - Field ID: {field_id}")
        print()
        
        print("✅ 所有Python SDK调用演示完成")
        
    except Exception as e:
        print(f"❌ 操作失败: {e}")
        logger.exception("详细错误信息")
    
    finally:
        # 9. 关闭连接
        if transport.isOpen():
            transport.close()
            print("✅ 连接已关闭")
    
    print("=== 示例完成 ===")

if __name__ == "__main__":
    main()
