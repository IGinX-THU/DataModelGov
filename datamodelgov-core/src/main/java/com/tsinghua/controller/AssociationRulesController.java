package com.tsinghua.controller;

import com.tsinghua.dto.AssociationRulesQueryRequest;
import com.tsinghua.entity.AssociationRulesEntity;
import com.tsinghua.model.Result;
import com.tsinghua.service.AssociationRulesService;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Api(tags = "关联规则配置")
@RestController
@RequestMapping("/api/association")
public class AssociationRulesController {

    @Autowired
    private AssociationRulesService associationRulesService;

    @ApiOperation("创建关联规则")
    @PostMapping("/rules/save")
    @RequirePermission(Permission.ASSOCIATION_RULES_SAVE)
    public Result<Void> saveRules(@RequestBody AssociationRulesEntity associationRulesEntity) throws Exception {
        associationRulesService.saveRules(associationRulesEntity);
        return Result.success("关联规则保存成功");
    }

    @ApiOperation("分页查询关联规则")
    @PostMapping("/rules/query")
    @RequirePermission(Permission.ASSOCIATION_RULES_QUERY)
    public Result<List<AssociationRulesEntity>> queryRules(@RequestBody AssociationRulesQueryRequest request) {
        List<AssociationRulesEntity> result = associationRulesService.queryRules(request);
        return Result.success(result);
    }

    @ApiOperation("查询关联规则总数")
    @PostMapping("/rules/count")
    @RequirePermission(Permission.ASSOCIATION_RULES_COUNT)
    public Result<Object> countRules(@RequestBody AssociationRulesQueryRequest request) {
        Object count = associationRulesService.countRules(request);
        return Result.success(count);
    }

    @ApiOperation("关联规则详情")
    @GetMapping("/rules/detail")
    @RequirePermission(Permission.ASSOCIATION_RULES_DETAIL)
    public Result<?> queryRule(
            @RequestParam("createTime") Long createTime) {
        AssociationRulesEntity result = associationRulesService.queryRule(createTime);
        if (result == null) {
            return Result.error("未找到指定的关联规则");
        }
        return Result.success(result);
    }

    @ApiOperation("删除关联规则")
    @DeleteMapping("/rules/delete")
    @RequirePermission(Permission.ASSOCIATION_RULES_DELETE)
    public Result<Void> deleteRule(
            @RequestParam("createTime") Long createTime) throws Exception {
        associationRulesService.deleteRule(createTime);
        return Result.success("操作成功");
    }

}
