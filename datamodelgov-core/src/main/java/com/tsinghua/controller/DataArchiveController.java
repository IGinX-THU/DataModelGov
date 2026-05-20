package com.tsinghua.controller;

import com.tsinghua.dto.DataArchiveQueryRequest;
import com.tsinghua.entity.DataArchiveEntity;
import com.tsinghua.model.Result;
import com.tsinghua.service.DataArchiveService;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Api(tags = "数据档案管理")
@RestController
@RequestMapping("/api/dataArchive")
public class DataArchiveController {

    @Autowired
    private DataArchiveService dataArchiveService;

    @ApiOperation("分页查询数据档案")
    @PostMapping("/query")
    @RequirePermission(Permission.READ)
    public Result<List<DataArchiveEntity>> queryArchives(@RequestBody DataArchiveQueryRequest request) {
        List<DataArchiveEntity> result = dataArchiveService.queryArchives(
            request.getName(),
            request.getType(),
            request.getProjectName(),
            request.getOwner(),
            request.getPageNum(),
            request.getPageSize()
        );
        return Result.success(result);
    }

    @ApiOperation("查询档案详情")
    @GetMapping("/detail")
    @RequirePermission(Permission.READ)
    public Result<DataArchiveEntity> queryArchiveDetail(@RequestParam("name") String name) {
        DataArchiveEntity archive = dataArchiveService.findByName(name);
        return Result.success(archive);
    }

    @ApiOperation("查询总数")
    @PostMapping("/count")
    @RequirePermission(Permission.READ)
    public Result<Object> countArchives(@RequestBody DataArchiveQueryRequest request) {
        List<DataArchiveEntity> allArchives = dataArchiveService.queryArchives(
            request.getName(),
            request.getType(),
            request.getProjectName(),
            request.getOwner(),
            null,
            null
        );
        return Result.success(allArchives.size());
    }

    @ApiOperation("删除数据档案")
    @PostMapping("/delete")
    @RequirePermission(Permission.DELETE)
    public Result<Void> deleteArchive(@RequestBody DataArchiveQueryRequest request) throws Exception {
        dataArchiveService.deleteArchive(request.getId());
        return Result.success("删除成功");
    }

    @ApiOperation("更新数据档案描述")
    @PostMapping("/update")
    @RequirePermission(Permission.CREATE)
    public Result<Void> updateArchive(@RequestBody DataArchiveEntity archive) throws Exception {
        dataArchiveService.saveArchive(archive);
        return Result.success("更新成功");
    }
}
