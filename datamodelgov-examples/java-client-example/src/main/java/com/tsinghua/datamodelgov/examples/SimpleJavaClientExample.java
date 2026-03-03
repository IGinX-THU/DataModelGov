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
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * DataModelGov Java 客户端简单示例
 * 演示如何使用Thrift生成的SDK类进行实际API调用
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
            Result result = client.queryData(queryRequest);
            // 6. 演示JSON序列化
            System.out.println("6. JSON序列化演示");
            ObjectMapper mapper = new ObjectMapper();
            String modelJson = mapper.writeValueAsString(result);
            String queryJson = mapper.writeValueAsString(queryRequest);
            System.out.println("result JSON: " + modelJson);
            System.out.println("QueryRequest JSON: " + queryJson);
            System.out.println();
            
            // 7. 演示其他API调用（注释掉，避免服务端不支持时出错）
            System.out.println("7. 其他API调用示例");
            System.out.println("// 保存关联规则: client.saveAssociationRule(associationRule)");
            System.out.println("// 查询关联规则: client.queryAssociationRules(queryRequest)");
            System.out.println("// 数据查询: client.dataQuery(queryRequest)");
            System.out.println("// 注册数据源: client.registerDataSource(storageRequest)");
            System.out.println("// 查询数据源: client.getDataSourceList()");
            System.out.println();
            
            System.out.println("✅ 所有SDK调用演示完成");
            
        } catch (Exception e) {
            System.err.println("❌ 操作失败: " + e.getMessage());
            e.printStackTrace();
        } finally {
            // 8. 确保连接关闭
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
