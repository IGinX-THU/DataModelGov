package com.tsinghua.controller;

import com.tsinghua.dto.AssociationRulesQueryRequest;
import com.tsinghua.dto.RelationalQueryRequest;
import com.tsinghua.entity.AssociationRulesEntity;
import com.tsinghua.dto.Result;
import com.tsinghua.dto.TableDto;
import com.tsinghua.service.AssociationRulesService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.validation.annotation.Validated;
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
    public Result<Void> saveRules(@RequestBody AssociationRulesEntity associationRulesEntity) throws Exception {
        associationRulesService.saveRules(associationRulesEntity);
        return Result.success("关联规则保存成功");
    }

    @ApiOperation("分页查询关联规则")
    @PostMapping("/rules/query")
    public Result<List<AssociationRulesEntity>> queryRules(@RequestBody AssociationRulesQueryRequest request) {
        List<AssociationRulesEntity> result = associationRulesService.queryRules(request);
        return Result.success(result);
    }

    @ApiOperation("查询关联规则总数")
    @PostMapping("/rules/count")
    public Result<Object> countRules(@RequestBody AssociationRulesQueryRequest request) {
        Object count = associationRulesService.countRules(request);
        return Result.success(count);
    }

    @ApiOperation("关联规则详情")
    @GetMapping("/rules/detail")
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
    public Result<Void> deleteRule(
            @RequestParam("createTime") Long createTime) throws Exception {
        associationRulesService.deleteRule(createTime);
        return Result.success("操作成功");
    }

}
