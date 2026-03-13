package com.tsinghua.controller;

import com.tsinghua.model.Result;
import com.tsinghua.service.ApiGenerationService;
import com.tsinghua.util.ThriftCodeGenerator;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * API代码生成控制器
 */
@Slf4j
@Api(tags = "API代码生成")
@RestController
@RequestMapping("/api/generation")
public class ApiGenerationController {

    @Autowired
    private ApiGenerationService apiGenerationService;

    @ApiOperation("生成Java代码")
    @PostMapping("/java")
    public Result<?> generateJavaCode() {
        log.info("开始生成Java代码");
        return apiGenerationService.generateJavaCode();
    }

    @ApiOperation("生成Go代码")
    @PostMapping("/go")
    public Result<?> generateGoCode() {
        log.info("开始生成Go代码");
        return apiGenerationService.generateGoCode();
    }

    @ApiOperation("生成Python代码")
    @PostMapping("/python")
    public Result<?> generatePythonCode() {
        log.info("开始生成Python代码");
        return apiGenerationService.generatePythonCode();
    }

    @ApiOperation("生成RESTful API代码")
    @PostMapping("/restful")
    public Result<?> generateRestfulApiCode() {
        log.info("开始生成RESTful API代码");
        return apiGenerationService.generateRestfulApiCode();
    }

    @ApiOperation("生成所有语言代码")
    @PostMapping("/all")
    public Result<Map<String, String>> generateAllCode() {
        log.info("开始生成所有语言代码");
        return apiGenerationService.generateAllCode();
    }

    @ApiOperation("获取代码生成状态")
    @GetMapping("/status")
    public Result<?> getGenerationStatus() {
        // 检查Thrift编译器状态
        if (ThriftCodeGenerator.isThriftAvailable()) {
            String version = ThriftCodeGenerator.getThriftVersion();
            return Result.success("代码生成服务运行正常，Thrift版本: " + version, version);
        } else {
            return Result.error("Thrift编译器不可用，请检查安装和PATH配置");
        }
    }

    @ApiOperation("验证Thrift文件语法")
    @GetMapping("/validate")
    public Result<?> validateThriftFile() {
        try {
            ThriftCodeGenerator.ValidationResult result = ThriftCodeGenerator.validateThriftFile(
                "datamodelgov-server/src/main/resources/thrift/api.thrift"
            );
            
            if (result.isValid()) {
                return Result.success("Thrift文件语法正确: " + result.getMessage(), result.getMessage());
            } else {
                return Result.error("Thrift文件语法错误: " + result.getMessage());
            }
        } catch (Exception e) {
            log.error("验证Thrift文件失败", e);
            return Result.error("验证Thrift文件失败: " + e.getMessage());
        }
    }
}
