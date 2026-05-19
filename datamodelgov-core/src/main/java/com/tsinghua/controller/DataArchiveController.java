package com.tsinghua.controller;

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
import java.util.Map;

@Api(tags = "数据档案管理")
@RestController
@RequestMapping("/api/dataArchive")
public class DataArchiveController {

    @Autowired
    private DataArchiveService dataArchiveService;

    @ApiOperation("分页查询数据档案")
    @PostMapping("/query")
    @RequirePermission(Permission.READ)
    public Result<List<DataArchiveEntity>> queryArchives(@RequestBody Map<String, Object> request) {
        String name = request.get("name") != null ? request.get("name").toString() : null;
        String type = request.get("type") != null ? request.get("type").toString() : null;
        String projectName = request.get("projectName") != null ? request.get("projectName").toString() : null;
        String owner = request.get("owner") != null ? request.get("owner").toString() : null;
        Integer pageNum = request.get("pageNum") != null ? Integer.parseInt(request.get("pageNum").toString()) : null;
        Integer pageSize = request.get("pageSize") != null ? Integer.parseInt(request.get("pageSize").toString()) : null;

        List<DataArchiveEntity> result = dataArchiveService.queryArchives(name, type, projectName, owner, pageNum, pageSize);
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
    public Result<Object> countArchives(@RequestBody Map<String, Object> request) {
        String name = request.get("name") != null ? request.get("name").toString() : null;
        String type = request.get("type") != null ? request.get("type").toString() : null;
        String projectName = request.get("projectName") != null ? request.get("projectName").toString() : null;
        String owner = request.get("owner") != null ? request.get("owner").toString() : null;

        // 查询所有符合条件的记录
        List<DataArchiveEntity> allArchives = dataArchiveService.queryArchives(name, type, projectName, owner, null, null);
        return Result.success(allArchives.size());
    }

    @ApiOperation("删除数据档案")
    @PostMapping("/delete")
    @RequirePermission(Permission.DELETE)
    public Result<Void> deleteArchive(@RequestBody Map<String, Object> request) throws Exception {
        Long id = request.get("id") != null ? Long.parseLong(request.get("id").toString()) : null;
        dataArchiveService.deleteArchive(id);
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
