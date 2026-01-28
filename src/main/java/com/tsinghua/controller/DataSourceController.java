package com.tsinghua.controller;

import com.tsinghua.dto.DataSourceDTO;
import com.tsinghua.service.DataSourceService;
import com.tsinghua.util.Result;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

/**
 * 数据源管理接口
 */
@RestController
@RequestMapping("/api/datasource")
public class DataSourceController {

    @Autowired
    private DataSourceService dataSourceService;

    /**
     * 注册数据源
     */
    @PostMapping("/register")
    public Result register(@Validated @RequestBody DataSourceDTO dto) {
        boolean success = dataSourceService.registerDataSource(dto);
        return success ? Result.success("数据源注册成功") : Result.error("注册失败，请检查配置");
    }

    /**
     * 移除数据源
     */
    @DeleteMapping("/remove/{alias}")
    public Result remove(@PathVariable String alias) {
        boolean success = dataSourceService.removeDataSource(alias);
        return success ? Result.success("数据源移除成功") : Result.error("移除失败，数据源可能被关联规则占用");
    }

    /**
     * 查询数据源列表
     */
    @GetMapping("/list")
    public Result list() {
        // 实际项目需查询IGinX获取数据源列表
        return Result.success("暂未实现，实际项目需对接IGinX查询");
    }
}