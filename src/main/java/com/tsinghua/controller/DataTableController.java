package com.tsinghua.controller;

import com.tsinghua.dto.*;
import com.tsinghua.service.DataSourceService;
import com.tsinghua.service.DataTableService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import io.swagger.annotations.ApiParam;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import javax.servlet.http.HttpServletResponse;
import javax.validation.Valid;
import java.util.List;

/**
 * 数据查询与管理接口
 */
@Api(tags = "数据查询与管理")
@RestController
@RequestMapping("/api/data")
public class DataTableController {

    @Autowired
    private DataTableService dataTableService;

    /**
     * 数据查询
     */
    @ApiOperation("数据查询")
    @PostMapping("/query")
    public Result<TableDto> queryData(@Validated @RequestBody DataQueryRequest request) {
        return Result.success(dataTableService.dataQuery(request));
    }

    /**
     * 导入数据
     */
    @ApiOperation("导入数据")
    @PostMapping(value = "/import", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public Result<Void> importData(// 使用 @RequestPart 接收JSON格式的配置参数
                                   @RequestPart("config") @Valid DataImportRequest config,
                                   @ApiParam(value = "数据文件", required = true) @RequestPart("file") MultipartFile file) {
        return dataTableService.importData(file, config);
    }

    /**
     * 导出数据
     */
    @ApiOperation("导出数据")
    @PostMapping("/export")
    public void exportData(@Validated @RequestBody DataQueryRequest request, HttpServletResponse response) {
        dataTableService.exportData(request, response);
    }

}
