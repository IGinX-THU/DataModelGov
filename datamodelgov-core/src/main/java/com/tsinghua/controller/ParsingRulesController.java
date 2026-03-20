package com.tsinghua.controller;

import com.tsinghua.dto.ParsingRulesQueryRequest;
import com.tsinghua.entity.ParsingRulesEntity;
import com.tsinghua.model.Result;
import com.tsinghua.service.ParsingRulesService;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.annotation.OperationLog;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Api(tags = "解析规则配置")
@RestController
@RequestMapping("/api/parsing")
public class ParsingRulesController {

    @Autowired
    private ParsingRulesService parsingRulesService;

    @ApiOperation("创建解析规则")
    @PostMapping("/rules/save")
    @RequirePermission(Permission.PARSING_RULES_CREATE)
    @OperationLog(value = "创建解析规则", type = OperationLog.OperationType.CREATE)
    public Result<Void> saveRules(@RequestBody ParsingRulesEntity parsingRulesEntity) {
        try {
            parsingRulesService.saveRules(parsingRulesEntity);
            return Result.success("解析规则保存成功");
        } catch (Exception e) {
            return Result.paramError(e.getMessage());
        }
    }

    @ApiOperation("分页查询解析规则")
    @PostMapping("/rules/query")
    @RequirePermission(Permission.PARSING_RULES_READ)
    public Result<List<ParsingRulesEntity>> queryRules(@RequestBody ParsingRulesQueryRequest request) {
        List<ParsingRulesEntity> result = parsingRulesService.queryRules(request);
        return Result.success(result);
    }

    @ApiOperation("查询解析规则总数")
    @PostMapping("/rules/count")
    @RequirePermission(Permission.PARSING_RULES_READ)
    public Result<Object> countRules(@RequestBody ParsingRulesQueryRequest request) {
        Object count = parsingRulesService.countRules(request);
        return Result.success(count);
    }

    @ApiOperation("解析规则详情")
    @GetMapping("/rules/detail")
    @RequirePermission(Permission.PARSING_RULES_READ)
    public Result<?> queryRule(
            @RequestParam("createTime") Long createTime) {
        ParsingRulesEntity result = parsingRulesService.queryRule(createTime);
        if (result == null) {
            return Result.error("未找到指定的解析规则");
        }
        return Result.success(result);
    }

    @ApiOperation("删除解析规则")
    @DeleteMapping("/rules/delete")
    @RequirePermission(Permission.PARSING_RULES_DELETE)
    @OperationLog(value = "删除解析规则", type = OperationLog.OperationType.DELETE)
    public Result<Void> deleteRule(
            @RequestParam("createTime") Long createTime) throws Exception {
        parsingRulesService.deleteRule(createTime);
        return Result.success("操作成功");
    }

}
