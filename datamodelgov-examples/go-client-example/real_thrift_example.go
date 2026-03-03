package main

import (
	"fmt"
	"time"
	"context"
	"git.apache.org/thrift.git/lib/go/thrift"
	"github.com/tsinghua/datamodelgov-sdk-go/src/tsinghua/api"
)

func main() {
	fmt.Println("=== DataModelGov Go Thrift SDK 客户端示例 ===\n")
	
	// 1. 创建Thrift连接
	fmt.Println("1. 连接到DataModelGov服务端")
	transport, err := thrift.NewTSocket("localhost:9090")
	if err != nil {
		fmt.Printf("创建传输失败: %v\n", err)
		return
	}
	defer transport.Close()
	
	protocolFactory := thrift.NewTBinaryProtocolFactoryDefault()
	client := api.NewApiServiceClientFactory(transport, protocolFactory)
	
	// 打开连接
	if err := transport.Open(); err != nil {
		fmt.Printf("连接失败: %v\n", err)
		return
	}
	fmt.Println("✅ 连接成功: localhost:9090")
	fmt.Println()
	
	// 2. 创建数据模型元数据
	fmt.Println("2. 创建数据模型元数据")
	modelMeta := api.NewModelMeta()
	modelMeta.Name = "用户模型"
	modelMeta.Version = "1.0.0"
	modelMeta.Author = "data_scientist_001"
	modelMeta.Scene = "用户行为分析"
	modelMeta.Inputs = "{\"age\": \"int\", \"income\": \"double\"}"
	modelMeta.Outputs = "{\"risk_score\": \"double\", \"category\": \"string\"}"
	modelMeta.Timestamp = time.Now().Unix()
	
	fmt.Printf("模型名称: %s\n", modelMeta.Name)
	fmt.Printf("模型版本: %s\n", modelMeta.Version)
	fmt.Printf("模型作者: %s\n", modelMeta.Author)
	fmt.Println()
	
	// 3. 调用保存模型元数据API
	fmt.Println("3. 调用saveModelMeta API")
	ctx := context.Background()
	saveResult, err := client.SaveModelMeta(ctx, modelMeta)
	if err != nil {
		fmt.Printf("保存失败: %v\n", err)
	} else {
		fmt.Printf("保存结果: Success=%t, Message=%s\n", saveResult.Success, saveResult.Message)
	}
	fmt.Println()
	
	// 4. 调用查询模型元数据API
	fmt.Println("4. 调用getModelMeta API")
	retrievedResult, err := client.GetModelMeta(ctx, "用户模型", "1.0.0")
	if err != nil {
		fmt.Printf("查询失败: %v\n", err)
	} else {
		fmt.Printf("查询结果: Success=%t, Message=%s\n", retrievedResult.Success, retrievedResult.Message)
		if retrievedResult.Data != nil {
			fmt.Printf("数据: %s\n", *retrievedResult.Data)
		}
	}
	fmt.Println()
	
	// 5. 创建数据查询请求
	fmt.Println("5. 创建数据查询请求")
	queryRequest := api.NewDataQueryRequest()
	queryRequest.Paths = []string{"root.device.temperature", "root.device.humidity"}
	queryRequest.StartTime = time.Now().Unix() - 86400 // 24小时前
	queryRequest.EndTime = time.Now().Unix()
	
	fmt.Printf("查询路径: %v\n", queryRequest.Paths)
	fmt.Printf("时间范围: %d - %d\n", queryRequest.StartTime, queryRequest.EndTime)
	fmt.Println()
	
	// 6. 调用数据查询API
	fmt.Println("6. 调用queryData API")
	queryResult, err := client.QueryData(ctx, queryRequest)
	if err != nil {
		fmt.Printf("查询失败: %v\n", err)
	} else {
		fmt.Printf("查询结果: Success=%t, Message=%s\n", queryResult.Success, queryResult.Message)
		if queryResult.Data != nil {
			fmt.Printf("数据: %s\n", *queryResult.Data)
		}
	}
	fmt.Println()
	
	// 7. 演示其他数据对象
	fmt.Println("7. 演示其他数据对象")
	
	// 创建关联规则查询请求
	rulesQuery := api.NewAssociationRulesQueryRequest()
	rulesQuery.PageNum = 1
	rulesQuery.PageSize = 10
	rulesQuery.Name = "用户行为规则"
	
	// 创建存储引擎信息
	storageInfo := api.NewStorageEngineInfo()
	storageInfo.Id = 1
	storageInfo.Ip = "127.0.0.1"
	storageInfo.Port = 8080
	storageInfo.Type = 1 // IoTDB
	storageInfo.SchemaPrefix = "root"
	storageInfo.DataPrefix = "data"
	
	fmt.Printf("关联规则查询: PageNum=%d, PageSize=%d\n", rulesQuery.PageNum, rulesQuery.PageSize)
	fmt.Printf("存储引擎信息: IP=%s:%d, Type=%d\n", storageInfo.Ip, storageInfo.Port, storageInfo.Type)
	fmt.Println()
	
	// 8. 演示字段枚举
	fmt.Println("8. SDK字段枚举")
	fmt.Println("ModelMeta字段:")
	for _, field := range api.ModelMetaFields {
		fmt.Printf("  - %s (thriftId: %d)\n", field.String(), int16(field))
	}
	fmt.Println()
	
	fmt.Println("✅ 所有Go SDK调用演示完成")
	fmt.Println("=== 示例完成 ===")
}
