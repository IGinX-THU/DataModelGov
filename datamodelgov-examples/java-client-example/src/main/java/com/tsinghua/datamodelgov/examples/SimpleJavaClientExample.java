package com.tsinghua.datamodelgov.examples;

import com.tsinghua.datamodelgov.sdk.DataModelClient;
import com.tsinghua.datamodelgov.sdk.Model;
import com.tsinghua.datamodelgov.sdk.AnalysisResult;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * DataModelGov Java 客户端简单示例
 * 只演示SDK的使用，不依赖其他模块
 */
public class SimpleJavaClientExample {

    public static void main(String[] args) {
        System.out.println("=== DataModelGov Java SDK 客户端示例 ===\n");
        
        // 1. 创建客户端
        System.out.println("1. 创建客户端");
        DataModelClient client = new DataModelClient("http://localhost:8080");
        System.out.println("SDK调用: DataModelClient client = new DataModelClient(\"http://localhost:8080\")");
        System.out.println("客户端创建成功\n");
        
        try {
            // 2. 创建数据模型
            System.out.println("2. 创建数据模型");
            Model model = new Model();
            model.setName("用户模型");
            model.setDescription("用户数据模型示例");
            model.addField("name", "string");
            model.addField("age", "int");
            model.addField("email", "string");
            
            System.out.println("SDK调用: client.createModel(model)");
            Model createdModel = client.createModel(model);
            System.out.println("创建成功: " + createdModel.getId());
            System.out.println("模型名称: " + createdModel.getName());
            System.out.println("模型描述: " + createdModel.getDescription());
            System.out.println();
            
            // 3. 查询数据模型
            System.out.println("3. 查询数据模型");
            System.out.println("SDK调用: client.getModels()");
            Model[] models = client.getModels();
            System.out.println("查询到 " + models.length + " 个模型:");
            for (Model m : models) {
                System.out.println("  - " + m.getName() + " (" + m.getId() + ")");
            }
            System.out.println();
            
            // 4. 按名称查询模型
            System.out.println("4. 按名称查询模型");
            System.out.println("SDK调用: client.getModels(\"用户模型\")");
            Model[] userModels = client.getModels("用户模型");
            System.out.println("查询到 " + userModels.length + " 个用户模型");
            System.out.println();
            
            // 5. 获取单个模型
            System.out.println("5. 获取单个模型");
            System.out.println("SDK调用: client.getModel(\"" + createdModel.getId() + "\")");
            Model singleModel = client.getModel(createdModel.getId());
            System.out.println("模型详情:");
            System.out.println("  ID: " + singleModel.getId());
            System.out.println("  名称: " + singleModel.getName());
            System.out.println("  描述: " + singleModel.getDescription());
            System.out.println("  字段: " + singleModel.getFields());
            System.out.println();
            
            // 6. 更新数据模型
            System.out.println("6. 更新数据模型");
            Model updateModel = new Model();
            updateModel.setName("更新用户模型");
            updateModel.setDescription("更新后的用户数据模型");
            updateModel.addField("name", "string");
            updateModel.addField("age", "int");
            updateModel.addField("email", "string");
            updateModel.addField("phone", "string");
            
            System.out.println("SDK调用: client.updateModel(\"" + createdModel.getId() + "\", updateModel)");
            Model updatedModel = client.updateModel(createdModel.getId(), updateModel);
            System.out.println("更新成功: " + updatedModel.getName());
            System.out.println();
            
            // 7. 数据分析
            System.out.println("7. 数据分析");
            String[] data = {"张三", "25", "zhangsan@example.com", "13800138000",
                           "李四", "30", "lisi@example.com", "13800138001"};
            
            System.out.println("SDK调用: client.analyzeData(\"" + createdModel.getId() + "\", data)");
            AnalysisResult result = client.analyzeData(createdModel.getId(), data);
            System.out.println("分析结果:");
            System.out.println("  分析ID: " + result.getAnalysisId());
            System.out.println("  模型ID: " + result.getModelId());
            System.out.println("  摘要: " + result.getSummary());
            System.out.println("  总记录数: " + result.getTotalRecords());
            System.out.println("  分析时间: " + result.getAnalysisTime());
            System.out.println();
            
            // 8. 删除数据模型
            System.out.println("8. 删除数据模型");
            System.out.println("SDK调用: client.deleteModel(\"" + createdModel.getId() + "\")");
            client.deleteModel(createdModel.getId());
            System.out.println("删除成功");
            System.out.println();
            
            System.out.println("=== 所有SDK调用演示完成 ===");
            
        } catch (Exception e) {
            System.err.println("SDK调用失败: " + e.getMessage());
            e.printStackTrace();
        }
    }
    
    /**
     * 演示JSON序列化
     */
    private static void demonstrateJsonSerialization() {
        System.out.println("=== JSON序列化示例 ===");
        
        try {
            ObjectMapper mapper = new ObjectMapper();
            
            // 创建模型对象
            Model model = new Model();
            model.setName("测试模型");
            model.setDescription("JSON序列化测试");
            model.addField("test", "string");
            
            // 序列化为JSON
            String json = mapper.writeValueAsString(model);
            System.out.println("模型JSON:");
            System.out.println(json);
            
            // 从JSON反序列化
            Model parsedModel = mapper.readValue(json, Model.class);
            System.out.println("反序列化成功: " + parsedModel.getName());
            
        } catch (Exception e) {
            System.err.println("JSON处理失败: " + e.getMessage());
        }
    }
}
