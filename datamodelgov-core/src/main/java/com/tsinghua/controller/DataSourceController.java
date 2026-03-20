package com.tsinghua.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsinghua.dto.ColumnDto;
import com.tsinghua.dto.StorageEngineInfoDto;
import com.tsinghua.dto.request.*;
import com.tsinghua.service.DataSourceService;
import com.tsinghua.model.Result;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.annotation.OperationLog;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * 数据源管理接口
 */
@Slf4j
@Api(tags = "数据资源管理")
@RestController
@RequestMapping("/api/datasource")
public class DataSourceController {

    @Autowired
    private DataSourceService dataSourceService;

    /**
     * 注册异构数据源 (Register Heterogeneous Data Source)
     */
    @ApiOperation("注册异构数据源")
    @PostMapping("/register")
    @RequirePermission(Permission.DATASOURCE_CREATE)
    @OperationLog(value = "注册异构数据源", type = OperationLog.OperationType.CREATE)
    public Result<Void> register(@RequestBody String jsonBody) throws Exception {
        log.info("jsonBody:{}", jsonBody);
        ObjectMapper mapper = new ObjectMapper();
        // 配置忽略未知属性
        mapper.configure(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
        JsonNode rootNode = mapper.readTree(jsonBody);
        
        // 获取 storageEngineType
        JsonNode storageEngineTypeNode = rootNode.get("storageEngineType");
        if (storageEngineTypeNode == null || !storageEngineTypeNode.isInt()) {
            return Result.error("storageEngineType is required and must be an integer");
        }
        
        int storageEngineType = storageEngineTypeNode.asInt();
        
        // 根据 storageEngineType 反序列化到具体的类
        BaseStorageEngineRequest request;
        switch (storageEngineType) {
            case 1:
                request = mapper.treeToValue(rootNode, Iotdb12StorageRequest.class);
                break;
            case 2:
                request = mapper.treeToValue(rootNode, InfluxdbStorageRequest.class);
                break;
            case 3:
                request = mapper.treeToValue(rootNode, FilesystemStorageRequest.class);
                break;
            case 4:
                request = mapper.treeToValue(rootNode, RelationalStorageRequest.class);
                break;
            case 5:
                request = mapper.treeToValue(rootNode, MongodbStorageRequest.class);
                break;
            case 6:
                request = mapper.treeToValue(rootNode, RedisStorageRequest.class);
                break;
            default:
                return Result.error("Unknown storage engine type: " + storageEngineType);
        }
        
        // 调试：打印接收到的请求信息
        log.info("Received request type: " + request.getClass().getSimpleName());
        log.info("Storage engine type: " + request.getStorageEngineType());
        log.info("IP: " + request.getIp());
        log.info("Port: " + request.getPort());
        
        boolean success = dataSourceService.registerDataSource(request);
        return success ? Result.success("数据源注册成功") : Result.error("注册失败，请检查配置");
    }

    /**
     * 移除异构数据源 (Remove Heterogeneous Data Source)
     */
    @ApiOperation("移除异构数据源")
    @PostMapping("/remove")
    @RequirePermission(Permission.DATASOURCE_DELETE)
    @OperationLog(value = "移除异构数据源", type = OperationLog.OperationType.DELETE)
    public Result<Void> remove(@Validated @RequestBody StorageEngineInfoDto removedStorageEngineInfo) throws Exception {
        boolean success = dataSourceService.removeDataSource(removedStorageEngineInfo);
        return success ? Result.success("数据源移除成功") : Result.error("移除失败，数据源可能被关联规则占用");
    }

    /**
     * 数据资源列表
     */
    @ApiOperation("数据资源列表")
    @GetMapping("/list")
    @RequirePermission(Permission.DATASOURCE_READ)
    @OperationLog(value = "查询数据资源列表", type = OperationLog.OperationType.QUERY, recordResult = false)
    public Result<List<StorageEngineInfoDto>> list() throws Exception {
        return Result.success(dataSourceService.dataSourceList());
    }

    /**
     * 数据资源树
     */
    @ApiOperation("数据资源树")
    @GetMapping("/tree")
    @RequirePermission(Permission.DATASOURCE_READ)
    @OperationLog(value = "查询数据资源树", type = OperationLog.OperationType.QUERY, recordResult = false)
    public Result<List<ColumnDto>> tree() throws Exception {
        return Result.success(dataSourceService.dataSourceTree());
    }

}
