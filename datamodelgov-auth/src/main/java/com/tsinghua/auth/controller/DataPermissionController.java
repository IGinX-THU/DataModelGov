package com.tsinghua.auth.controller;

import com.tsinghua.auth.dto.DataPermissionQueryRequest;
import com.tsinghua.auth.dto.DataPermissionUpdateRequest;
import com.tsinghua.auth.entity.DataPermissionEntity;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.model.Result;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.validation.Valid;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Api(tags = "数据权限")
@RestController
@RequestMapping("/api/data-permission")
public class DataPermissionController {

    @Autowired
    private DataPermissionService dataPermissionService;

    @ApiOperation("当前用户拥有的数据表权限列表（全量，兼容旧前端）")
    @GetMapping("/owner-tables")
    public Result<List<DataPermissionEntity>> listOwnerTables() {
        return Result.success(dataPermissionService.getOwnerTables());
    }

    @ApiOperation("当前用户拥有的数据表权限分页查询")
    @PostMapping("/query")
    public Result<List<DataPermissionEntity>> query(@RequestBody DataPermissionQueryRequest request) {
        return Result.success(dataPermissionService.queryOwnerTables(request));
    }

    @ApiOperation("当前用户拥有的数据表权限总数（与 query 筛选条件一致）")
    @PostMapping("/count")
    public Result<Map<String, Object>> count(@RequestBody DataPermissionQueryRequest request) {
        long count = dataPermissionService.countOwnerTables(request);
        Map<String, Object> body = new HashMap<>();
        body.put("count", count);
        return Result.success(body);
    }

    @ApiOperation("更新当前用户某条权限的公开与可见用户")
    @PostMapping("/update")
    public Result<Void> update(@Valid @RequestBody DataPermissionUpdateRequest request) {
        try {
            dataPermissionService.updateOwnerPermission(request);
            return Result.success("更新成功");
        } catch (IllegalArgumentException | IllegalStateException e) {
            return Result.error(e.getMessage());
        }
    }
}
