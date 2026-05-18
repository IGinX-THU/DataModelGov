package com.tsinghua.controller;

import com.tsinghua.entity.AlgorithmMetaEntity;
import com.tsinghua.model.Result;
import com.tsinghua.dto.UploadResult;
import com.tsinghua.service.AlgorithmFileService;
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
import java.util.List;

@Api(tags = "算法资产管理")
@RestController
@RequestMapping("/api/algorithm")
public class AlgorithmFileController {

    @Autowired
    private AlgorithmFileService algorithmFileService;

    @ApiOperation("上传算法")
    @PostMapping(value = "/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @RequirePermission(Permission.MODEL_CREATE)
    @OperationLog(value = "上传算法", type = OperationLog.OperationType.CREATE, recordParams = false)
    public Result<?> handleFileUpload(
            @RequestPart("file") MultipartFile file,
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "algorithmType", defaultValue = "python") String algorithmType) throws Exception {

        if (file.isEmpty()) {
            return Result.error("上传文件不能为空。");
        }

        UploadResult result = algorithmFileService.uploadAlgorithm(file, name, version);
        
        // 更新算法类型
        AlgorithmMetaEntity meta = algorithmFileService.queryMeta(name, version);
        if (meta != null) {
            meta.setAlgorithmType(algorithmType);
            algorithmFileService.saveAlgorithmMetadata(meta);
        }
        
        return Result.success(result);
    }

    @ApiOperation("下载算法")
    @PostMapping("/download")
    @RequirePermission(Permission.MODEL_READ)
    @OperationLog(value = "下载算法", type = OperationLog.OperationType.EXPORT, recordResult = false)
    public void handleFileDownload(
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "fileName", required = false) String fileName,
            HttpServletResponse response) throws Exception {

        byte[] fileData = algorithmFileService.downloadAlgorithm(name, version);
        AlgorithmMetaEntity queryMeta = algorithmFileService.queryMeta(name, version);
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

    @ApiOperation("算法元数据详情")
    @GetMapping("/metas")
    @RequirePermission(Permission.MODEL_READ)
    public Result<AlgorithmMetaEntity> queryMeta(
            @RequestParam("name") String name,
            @RequestParam("version") String version) throws Exception {
        AlgorithmMetaEntity result = algorithmFileService.queryMeta(name, version);
        return Result.success(result);
    }

    @ApiOperation("保存算法元数据")
    @PostMapping("/metas")
    @RequirePermission(Permission.MODEL_UPDATE)
    @OperationLog(value = "保存算法元数据", type = OperationLog.OperationType.UPDATE)
    public Result<Void> saveMeta(@RequestBody AlgorithmMetaEntity algorithmMetaDto) throws Exception {
        algorithmFileService.saveAlgorithmMetadata(algorithmMetaDto);
        return Result.success("元数据保存成功");
    }

    @ApiOperation("算法元数据历史")
    @GetMapping("/history")
    @RequirePermission(Permission.MODEL_READ)
    public Result<List<AlgorithmMetaEntity>> queryMetaList(
            @RequestParam("name") String name) {
        try {
            List<AlgorithmMetaEntity> result = algorithmFileService.queryMetaList(name);
            return Result.success(result);
        } catch (Exception e) {
            return new Result<>(500, "查询失败: " + e.getMessage(), null);
        }
    }

    @ApiOperation("移除算法资产")
    @DeleteMapping("/delete")
    @RequirePermission(Permission.MODEL_DELETE)
    @OperationLog(value = "移除算法资产", type = OperationLog.OperationType.DELETE)
    public Result<Void> handleDelete(
            @RequestParam("name") String name,
            @RequestParam(value = "version", required = false) String version) {
        try {
            algorithmFileService.deleteAlgorithm(name, version);
            return Result.success("操作成功");
        } catch (Exception e) {
            return Result.error("删除失败: " + e.getMessage());
        }
    }
}
