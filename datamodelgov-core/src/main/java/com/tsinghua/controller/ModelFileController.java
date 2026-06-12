package com.tsinghua.controller;

import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.ModelMetaEntity;
import com.tsinghua.model.Result;
import com.tsinghua.dto.UploadResult;
import com.tsinghua.dto.ExtractModelFileRequest;
import com.tsinghua.dto.ModelArchiveQueryRequest;
import com.tsinghua.service.ModelFileService;
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

        String encodedFilename = URLEncoder.encode(fileName, StandardCharsets.UTF_8.name())
                .replace("+", "%20");

        response.setContentType(MediaType.APPLICATION_OCTET_STREAM_VALUE);
        response.setHeader(HttpHeaders.CONTENT_DISPOSITION,
                "attachment; filename=\"" + encodedFilename + "\"; filename*=UTF-8''" + encodedFilename);
        response.setContentLength(fileData.length);

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
    public Result<?> queryMetaList(
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

    @ApiOperation("模型资产树")
    @GetMapping("/tree")
    @RequirePermission(Permission.MODEL_READ)
    public Result<?> queryModelTree(
            @RequestParam(value = "projectName", required = false) String projectName) {
        String effectiveProjectName = projectName;
        if (effectiveProjectName == null || effectiveProjectName.trim().isEmpty()) {
            effectiveProjectName = ProjectContext.getCurrentProject();
        }
        List<String> tree = modelFileService.queryModelTree(effectiveProjectName);
        return Result.success(tree);
    }

    @ApiOperation("分页查询模型档案")
    @PostMapping("/archive/query")
    @RequirePermission(Permission.MODEL_READ)
    public Result<List<ModelMetaEntity>> queryModelArchives(@RequestBody ModelArchiveQueryRequest request) {
        if (!AuthUtil.isAdmin()) {
            request.setAuthor(AuthUtil.getCurrentUsername());
        }
        List<ModelMetaEntity> result = modelFileService.queryModelArchives(
            request.getName(),
            request.getProjectName(),
            request.getAuthor(),
            request.getPageNum(),
            request.getPageSize()
        );
        return Result.success(result);
    }

    @ApiOperation("查询模型档案总数")
    @PostMapping("/archive/count")
    @RequirePermission(Permission.MODEL_READ)
    public Result<Object> countModelArchives(@RequestBody ModelArchiveQueryRequest request) {
        if (!AuthUtil.isAdmin()) {
            request.setAuthor(AuthUtil.getCurrentUsername());
        }
        List<ModelMetaEntity> allArchives = modelFileService.queryModelArchives(
            request.getName(),
            request.getProjectName(),
            request.getAuthor(),
            null,
            null
        );
        return Result.success(allArchives.size());
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

        Path tempDir = Files.createTempDirectory("model_parsing_");
        try {
            List<Map<String, Object>> fileList = modelFileService.extractModelFile(modelName, version, tempDir);
            return Result.success(fileList);
        } finally {
            cleanupTempDir(tempDir);
        }
    }

    private void cleanupTempDir(Path tempDir) {
        try {
            Files.walk(tempDir)
                    .sorted(java.util.Comparator.reverseOrder())
                    .forEach(path -> {
                        try { Files.deleteIfExists(path); } catch (Exception ignored) {}
                    });
            Files.deleteIfExists(tempDir);
        } catch (Exception ignored) {}
    }

}
