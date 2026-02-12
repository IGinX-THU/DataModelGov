package com.tsinghua.controller;

import com.tsinghua.dto.*;
import com.tsinghua.service.DataSourceService;
import com.tsinghua.service.DataTableService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

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

}
