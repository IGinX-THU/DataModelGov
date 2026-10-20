package com.tsinghua.controller;

import com.tsinghua.model.Result;
import com.tsinghua.program.catalog.BusinessGroup;
import com.tsinghua.program.catalog.ProgramCatalogService;
import com.tsinghua.program.catalog.ProgramFeature;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@Api(tags = "公开功能注册表")
@Slf4j
@RestController
@RequestMapping("/api/program-catalog")
public class ProgramCatalogController {

    @Autowired
    private ProgramCatalogService catalogService;

    @ApiOperation("20 项公开功能清单(可按工作台/模块过滤)")
    @GetMapping
    public Result<List<ProgramFeature>> list(
            @RequestParam(value = "workbench", required = false) String workbench,
            @RequestParam(value = "module", required = false) String module) {
        return Result.success(catalogService.list(workbench, module));
    }

    @ApiOperation("功能详情")
    @GetMapping("/detail")
    public Result<ProgramFeature> detail(@RequestParam("id") String id) {
        ProgramFeature feature = catalogService.get(id);
        if (feature == null) {
            return Result.error("功能标识不存在:" + id);
        }
        return Result.success(feature);
    }

    @ApiOperation("业务组(图组)与操作流程步骤")
    @GetMapping("/groups")
    public Result<List<BusinessGroup>> groups() {
        return Result.success(catalogService.listGroups());
    }
}
