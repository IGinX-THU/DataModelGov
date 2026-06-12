package com.tsinghua.controller;

import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.AlgorithmMetaEntity;
import com.tsinghua.model.Result;
import com.tsinghua.dto.UploadResult;
import com.tsinghua.dto.ExtractAlgorithmFileRequest;
import com.tsinghua.dto.AlgorithmArchiveQueryRequest;
import com.tsinghua.service.AlgorithmFileService;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.annotation.OperationLog;
import com.tsinghua.util.ProjectContext;
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
import java.util.List;
import java.util.Map;

@Api(tags = "算法资产管理")
@RestController
@RequestMapping("/api/algorithm")
public class AlgorithmFileController {

    @Autowired
    private AlgorithmFileService algorithmFileService;

    @ApiOperation("上传算法")
    @PostMapping(value = "/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @RequirePermission(Permission.CREATE)
    @OperationLog(value = "上传算法", type = OperationLog.OperationType.CREATE, recordParams = false)
    public Result<?> handleFileUpload(
            @RequestPart("file") MultipartFile file,
            @RequestParam("name") String name,
            @RequestParam("version") String version) throws Exception {

        if (file.isEmpty()) {
            return Result.error("上传文件不能为空。");
        }

        UploadResult result = algorithmFileService.uploadAlgorithm(file, name, version);
        return Result.success(result);
    }

    @ApiOperation("下载算法")
    @PostMapping("/download")
    @RequirePermission(Permission.READ)
    @OperationLog(value = "下载算法", type = OperationLog.OperationType.EXPORT, recordResult = false)
    public void handleFileDownload(
            @RequestParam String name,
            @RequestParam String version,
            @RequestParam(value = "fileName", required = false) String fileName,
            HttpServletResponse response) throws Exception {

        byte[] fileData = algorithmFileService.downloadAlgorithm(name, version);
        AlgorithmMetaEntity queryMeta = algorithmFileService.queryMeta(name, version);
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

    @ApiOperation("算法元数据详情")
    @GetMapping( "/metas")
    @RequirePermission(Permission.READ)
    public Result<AlgorithmMetaEntity> queryMeta(
            @RequestParam("name") String name,
            @RequestParam("version") String version) throws Exception {
        AlgorithmMetaEntity result = algorithmFileService.queryMeta(name, version);
        return Result.success(result);
    }

    @ApiOperation("保存算法元数据")
    @PostMapping("/metas")
    @RequirePermission(Permission.UPDATE)
    @OperationLog(value = "保存算法元数据", type = OperationLog.OperationType.UPDATE)
    public Result<Void> saveMeta(@RequestBody AlgorithmMetaEntity algorithmMetaDto) throws Exception {
        algorithmFileService.saveAlgorithmMetadata(algorithmMetaDto);
        return Result.success("元数据保存成功");
    }

    @ApiOperation("算法元数据历史")
    @GetMapping( "/history")
    @RequirePermission(Permission.READ)
    public Result<List<AlgorithmMetaEntity>> queryMetaList(
            @RequestParam("name") String name) {
        return Result.success(algorithmFileService.queryMetaList(name));
    }

    @ApiOperation("移除算法资产")
    @DeleteMapping( "/delete")
    @RequirePermission(Permission.DELETE)
    @OperationLog(value = "移除算法资产", type = OperationLog.OperationType.DELETE)
    public Result<Void> handleDelete(
            @RequestParam("name") String name,
            @RequestParam(value = "version", required = false) String version) throws Exception {
        algorithmFileService.deleteAlgorithm(name, version);
        return Result.success("操作成功");
    }

    @ApiOperation("算法资产树")
    @GetMapping("/tree")
    @RequirePermission(Permission.READ)
    public Result<?> queryAlgorithmTree(
            @RequestParam(value = "projectName", required = false) String projectName) {
        String effectiveProjectName = projectName;
        if (effectiveProjectName == null || effectiveProjectName.trim().isEmpty()) {
            effectiveProjectName = ProjectContext.getCurrentProject();
        }
        List<String> tree = algorithmFileService.queryAlgorithmTree(effectiveProjectName);
        return Result.success(tree);
    }

    @ApiOperation("分页查询算法档案")
    @PostMapping("/archive/query")
    @RequirePermission(Permission.READ)
    public Result<List<AlgorithmMetaEntity>> queryAlgorithmArchives(@RequestBody AlgorithmArchiveQueryRequest request) {
        if (!AuthUtil.isAdmin()) {
            request.setAuthor(AuthUtil.getCurrentUsername());
        }
        List<AlgorithmMetaEntity> result = algorithmFileService.queryAlgorithmArchives(
            request.getName(),
            request.getProjectName(),
            request.getAuthor(),
            request.getPageNum(),
            request.getPageSize()
        );
        return Result.success(result);
    }

    @ApiOperation("查询算法档案总数")
    @PostMapping("/archive/count")
    @RequirePermission(Permission.READ)
    public Result<Object> countAlgorithmArchives(@RequestBody AlgorithmArchiveQueryRequest request) {
        if (!AuthUtil.isAdmin()) {
            request.setAuthor(AuthUtil.getCurrentUsername());
        }
        List<AlgorithmMetaEntity> allArchives = algorithmFileService.queryAlgorithmArchives(
            request.getName(),
            request.getProjectName(),
            request.getAuthor(),
            null,
            null
        );
        return Result.success(allArchives.size());
    }

    @ApiOperation("提取算法文件用于解析")
    @PostMapping("/extractAlgorithmFile")
    @RequirePermission(Permission.READ)
    public Result<?> extractAlgorithmFileForParsing(@RequestBody ExtractAlgorithmFileRequest request) throws Exception {
        
        String algorithmName = request.getName();
        String version = request.getVersion();
        
        if (algorithmName == null || version == null) {
            return Result.error("参数name和version不能为空");
        }
        
        // 创建临时目录
        Path tempDir = Files.createTempDirectory("algorithm_parsing_");
        
        try {
            // 调用修改后的extractAlgorithmFile方法
            List<Map<String, Object>> fileList = algorithmFileService.extractAlgorithmFile(algorithmName, version, tempDir);
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

}
