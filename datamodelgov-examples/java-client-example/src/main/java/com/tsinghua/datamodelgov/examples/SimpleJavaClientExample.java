package com.tsinghua.datamodelgov.examples;

import com.tsinghua.thrift.api.ApiService;
import com.tsinghua.thrift.api.ModelMeta;
import com.tsinghua.thrift.api.Result;
import com.tsinghua.thrift.api.DataQueryRequest;
import com.tsinghua.thrift.api.AssociationRulesQueryRequest;
import com.tsinghua.thrift.api.StorageEngineInfo;
import org.apache.thrift.transport.TSocket;
import org.apache.thrift.transport.TTransport;
import org.apache.thrift.protocol.TBinaryProtocol;
import org.apache.thrift.protocol.TProtocol;

/**
 * DataModelGov Java 客户端简单示例
 * 演示如何使用Thrift生成的SDK类进行实际API调用
 * 不依赖Jackson，使用Thrift原生功能
 */
public class SimpleJavaClientExample {

    public static void main(String[] args) {
        System.out.println("=== DataModelGov Java SDK 客户端示例 ===\n");
        
        TTransport transport = null;
        TProtocol protocol = null;
        ApiService.Client client = null;
        
        try {
            // 1. 创建Thrift客户端连接
            System.out.println("1. 连接到DataModelGov服务端");
            transport = new TSocket("localhost", 9090);
            protocol = new TBinaryProtocol(transport);
            client = new ApiService.Client(protocol);
            transport.open();
            System.out.println("✅ 连接成功");
            System.out.println();
            
            // 2. 创建数据模型元数据
            System.out.println("2. 创建数据模型元数据");
            ModelMeta modelMeta = new ModelMeta();
            modelMeta.setName("用户模型");
            modelMeta.setVersion("1.0.0");
            modelMeta.setAuthor("data_scientist_001");
            modelMeta.setScene("用户行为分析");
            modelMeta.setInputs("{\"age\": \"int\", \"income\": \"double\"}");
            modelMeta.setOutputs("{\"risk_score\": \"double\", \"category\": \"string\"}");
            modelMeta.setTimestamp(System.currentTimeMillis());
            
            System.out.println("模型元数据创建成功");
            System.out.println("名称: " + modelMeta.getName());
            System.out.println("版本: " + modelMeta.getVersion());
            System.out.println("作者: " + modelMeta.getAuthor());
            System.out.println();
            
            // 3. 调用保存模型元数据API
            System.out.println("3. 调用saveModelMeta API");
            Result saveResult = client.saveModelMeta(modelMeta);
            System.out.println("保存结果: " + (saveResult != null ? saveResult.toString() : "null"));
            System.out.println();
            
            // 4. 调用查询模型元数据API
            System.out.println("4. 调用getModelMeta API");
            Result retrievedResult = client.getModelMeta("用户模型", "1.0.0");
            if (retrievedResult != null && retrievedResult.isSuccess()) {
                System.out.println("查询成功:");
                System.out.println("  成功状态: " + retrievedResult.isSuccess());
                System.out.println("  消息: " + (retrievedResult.getMessage() != null ? retrievedResult.getMessage() : "null"));
                System.out.println("  数据: " + (retrievedResult.isSetData() ? retrievedResult.getData() : "null"));
            } else {
                System.out.println("查询失败: 模型不存在或查询出错");
            }
            System.out.println();
            
            // 5. 演示数据查询API
            System.out.println("5. 创建数据查询请求");
            DataQueryRequest queryRequest = new DataQueryRequest();
            queryRequest.setPaths(new java.util.ArrayList<>());
            queryRequest.getPaths().add("root.device.temperature");
            queryRequest.setStartTime(System.currentTimeMillis() - 86400000); // 24小时前
            queryRequest.setEndTime(System.currentTimeMillis());
            
            System.out.println("查询参数:");
            System.out.println("  路径: " + queryRequest.getPaths());
            System.out.println("  开始时间: " + queryRequest.getStartTime());
            System.out.println("  结束时间: " + queryRequest.getEndTime());
            
            // 6. 调用数据查询API
            System.out.println("6. 调用queryData API");
            Result queryResult = client.queryData(queryRequest);
            System.out.println("查询结果: " + (queryResult != null ? queryResult.getData() : "null"));
            System.out.println();
            
            // 7. 演示其他数据对象创建
            System.out.println("7. 演示其他数据对象");
            AssociationRulesQueryRequest rulesQuery = new AssociationRulesQueryRequest();
            rulesQuery.setPageNum(1);
            rulesQuery.setPageSize(10);
            rulesQuery.setName("用户行为规则");
            
            StorageEngineInfo storageInfo = new StorageEngineInfo();
            storageInfo.setId(1L);
            storageInfo.setIp("127.0.0.1");
            storageInfo.setPort(6667);
            storageInfo.setType(1); // IoTDB
            storageInfo.setSchemaPrefix("root");
            storageInfo.setDataPrefix("data");
            
            System.out.println("关联规则查询: " + rulesQuery.toString());
            System.out.println("存储引擎信息: " + storageInfo.toString());
            System.out.println();
            
            // 8. 演示SDK类的字段枚举
            System.out.println("8. SDK类字段枚举");
            System.out.println("ModelMeta字段:");
            for (ModelMeta._Fields field : ModelMeta._Fields.values()) {
                System.out.println("  - " + field.getFieldName() + " (thriftId: " + field.getThriftFieldId() + ")");
            }
            System.out.println();
            
            System.out.println("9. 其他API调用示例");
            System.out.println("// 保存关联规则: client.saveAssociationRule(associationRule)");
            System.out.println("// 查询关联规则: client.queryAssociationRules(queryRequest)");
            System.out.println("// 注册数据源: client.registerDataSource(storageRequest)");
            System.out.println("// 查询数据源: client.getDataSourceList()");
            System.out.println();
            
            System.out.println("✅ 所有SDK调用演示完成");
            
        } catch (Exception e) {
            System.err.println("❌ 操作失败: " + e.getMessage());
            e.printStackTrace();
        } finally {
            // 10. 确保连接关闭
            if (transport != null) {
                try {
                    if (transport.isOpen()) {
                        transport.close();
                        System.out.println("✅ 连接已关闭");
                    }
                } catch (Exception e) {
                    System.err.println("⚠️ 关闭连接时出错: " + e.getMessage());
                }
            }
        }
        
        System.out.println("=== 示例完成 ===");
    }
}
