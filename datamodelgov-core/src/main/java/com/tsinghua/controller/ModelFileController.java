package com.tsinghua.controller;

import com.tsinghua.entity.ModelMetaEntity;
import com.tsinghua.model.Result;
import com.tsinghua.dto.UploadResult;
import com.tsinghua.dto.ExtractModelFileRequest;
import com.tsinghua.dto.AutoParseRequest;
import com.tsinghua.service.ModelFileService;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.annotation.OperationLog;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import javax.servlet.http.HttpServletResponse;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.Map;

@Api(tags = "模型资产管理")
@RestController
@RequestMapping("/api/model")
public class ModelFileController {

    @Autowired
    private ModelFileService modelFileService;

    @ApiOperation("上传模型")
    @PostMapping(value = "/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @RequirePermission(Permission.MODEL_CREATE)
    @OperationLog(value = "上传模型", type = OperationLog.OperationType.CREATE, recordParams = false)
    public Result<?> handleFileUpload(
            @RequestPart("file") MultipartFile file,
            @RequestParam("name") String name,
            @RequestParam("version") String version) throws Exception {

        if (file.isEmpty()) {
            return Result.error("上传文件不能为空。");
        }

        UploadResult result = modelFileService.uploadModel(file, name, version);
        return Result.success(result);
    }

    @ApiOperation("下载模型")
    @PostMapping("/download")
    @RequirePermission(Permission.MODEL_READ)
    @OperationLog(value = "下载模型", type = OperationLog.OperationType.EXPORT, recordResult = false)
    public void handleFileDownload(
            @RequestParam String name,
            @RequestParam String version,
            @RequestParam(value = "fileName", required = false) String fileName,
            HttpServletResponse response) throws Exception {

        byte[] fileData = modelFileService.downloadModel(name, version);
        ModelMetaEntity queryMeta = modelFileService.queryMeta(name, version);
        fileName = queryMeta.getFileName();

        // 设置响应头
        String encodedFilename = URLEncoder.encode(fileName, StandardCharsets.UTF_8.name())
                .replace("+", "%20");

        response.setContentType(MediaType.APPLICATION_OCTET_STREAM_VALUE);
        response.setHeader(HttpHeaders.CONTENT_DISPOSITION,
                "attachment; filename=\"" + encodedFilename + "\"; filename*=UTF-8''" + encodedFilename);
        response.setContentLength(fileData.length);

        // 写入响应流
        response.getOutputStream().write(fileData);
        response.flushBuffer();
    }

    @ApiOperation("模型元数据详情")
    @GetMapping( "/metas")
    @RequirePermission(Permission.MODEL_READ)
    public Result<ModelMetaEntity> queryMeta(
            @RequestParam("name") String name,
            @RequestParam("version") String version) throws Exception {
        ModelMetaEntity result = modelFileService.queryMeta(name, version);
        return Result.success(result);
    }

    @ApiOperation("保存模型元数据")
    @PostMapping("/metas")
    @RequirePermission(Permission.MODEL_UPDATE)
    @OperationLog(value = "保存模型元数据", type = OperationLog.OperationType.UPDATE)
    public Result<Void> saveMeta(@RequestBody ModelMetaEntity modelMetaDto) throws Exception {
        modelFileService.saveModelMetadata(modelMetaDto);
        return Result.success("元数据保存成功");
    }

    @ApiOperation("模型元数据历史")
    @GetMapping( "/history")
    @RequirePermission(Permission.MODEL_READ)
    public Result<List<ModelMetaEntity>> queryMetaList(
            @RequestParam("name") String name) {
        return Result.success(modelFileService.queryMetaList(name));
    }

    @ApiOperation("移除模型资产")
    @DeleteMapping( "/delete")
    @RequirePermission(Permission.MODEL_DELETE)
    @OperationLog(value = "移除模型资产", type = OperationLog.OperationType.DELETE)
    public Result<Void> handleDelete(
            @RequestParam("name") String name,
            @RequestParam(value = "version", required = false) String version) throws Exception {
        modelFileService.deleteModel(name, version);
        return Result.success("操作成功");
    }

    @ApiOperation("提取模型文件用于解析")
    @PostMapping("/extractModelFile")
    @RequirePermission(Permission.MODEL_READ)
    public Result<?> extractModelFileForParsing(@RequestBody ExtractModelFileRequest request) throws Exception {
        
        String modelName = request.getName();
        String version = request.getVersion();
        
        if (modelName == null || version == null) {
            return Result.error("参数name和version不能为空");
        }
        
        // 创建临时目录
        Path tempDir = Files.createTempDirectory("model_parsing_");
        
        try {
            // 调用修改后的extractModelFile方法
            List<Map<String, Object>> fileList = modelFileService.extractModelFile(modelName, version, tempDir);
            return Result.success(fileList);
        } finally {
            // 清理临时目录
            try {
                Files.walk(tempDir)
                        .sorted(java.util.Comparator.reverseOrder())
                        .forEach(path -> {
                            try {
                                Files.deleteIfExists(path);
                            } catch (Exception deleteException) {
                                // 忽略删除异常
                            }
                        });
                Files.deleteIfExists(tempDir);
            } catch (Exception deleteException) {
                // 忽略删除异常
            }
        }
    }

    @ApiOperation("自动解析源码提取API信息")
    @PostMapping("/autoParse")
    @RequirePermission(Permission.MODEL_READ)
    public Result<?> autoParseSourceCode(@RequestBody AutoParseRequest request) throws Exception {
        
        String modelName = request.getName();
        String version = request.getVersion();
        String filePath = request.getFilePath();
        
        if (modelName == null || version == null || filePath == null) {
            return Result.error("参数name、version和filePath不能为空");
        }
        
        // 创建临时目录，提取模型文件
        Path tempDir = Files.createTempDirectory("model_autoparse_");
        try {
            List<Map<String, Object>> fileList = modelFileService.extractModelFile(modelName, version, tempDir);
            
            // 查找目标文件
            String fileContent = null;
            String fileName = null;
            for (Map<String, Object> fileInfo : fileList) {
                String path = (String) fileInfo.get("path");
                String name = (String) fileInfo.get("name");
                if (filePath.equals(path) || filePath.equals(name) || path.endsWith(filePath)) {
                    fileContent = (String) fileInfo.get("content");
                    fileName = name;
                    break;
                }
            }
            
            if (fileContent == null) {
                return Result.error("未找到文件: " + filePath + "，或该文件不是文本文件");
            }
            
            // 调用轻量级扫描器
            String parseType = request.getParseType() != null ? request.getParseType() : "regex";
            String regexPattern = request.getRegexPattern();
            int maxLines = request.getMaxLines() != null ? request.getMaxLines() : 50;
            
            Map<String, Object> parseResult = modelFileService.parseSourceCode(
                fileContent, fileName, regexPattern, parseType, maxLines);
            
            return Result.success(parseResult);
        } finally {
            // 清理临时目录
            try {
                Files.walk(tempDir)
                        .sorted(java.util.Comparator.reverseOrder())
                        .forEach(path -> {
                            try {
                                Files.deleteIfExists(path);
                            } catch (Exception deleteException) {
                                // 忽略删除异常
                            }
                        });
                Files.deleteIfExists(tempDir);
            } catch (Exception deleteException) {
                // 忽略删除异常
            }
        }
    }

}
