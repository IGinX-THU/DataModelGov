package com.tsinghua.controller;

import com.tsinghua.dto.DataSourceRequest;
import com.tsinghua.dto.StorageEngineInfoDto;
import com.tsinghua.service.DataSourceService;
import com.tsinghua.dto.Result;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * 数据源管理接口
 */
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
    public Result<Void> register(@Validated @RequestBody DataSourceRequest request) {
        boolean success = dataSourceService.registerDataSource(request);
        return success ? Result.success("数据源注册成功") : Result.error("注册失败，请检查配置");
    }

    /**
     * 移除异构数据源 (Remove Heterogeneous Data Source)
     */
    @ApiOperation("移除异构数据源")
    @PostMapping("/remove")
    public Result<Void> remove(@Validated @RequestBody StorageEngineInfoDto removedStorageEngineInfo) {
        boolean success = dataSourceService.removeDataSource(removedStorageEngineInfo);
        return success ? Result.success("数据源移除成功") : Result.error("移除失败，数据源可能被关联规则占用");
    }

    /**
     * 数据资源列表
     */
    @ApiOperation("数据资源列表")
    @GetMapping("/list")
    public Result<List<StorageEngineInfoDto>> list() throws Exception {
        return Result.success(dataSourceService.dataSourceList());
    }
}
