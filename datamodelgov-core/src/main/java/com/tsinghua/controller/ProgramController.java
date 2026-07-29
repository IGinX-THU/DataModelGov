package com.tsinghua.controller;

import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.annotation.OperationLog;
import com.tsinghua.entity.ProgramEntity;
import com.tsinghua.model.Result;
import com.tsinghua.dto.UploadResult;
import com.tsinghua.service.ProgramService;
import com.tsinghua.util.ProjectContext;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;

@Api(tags = "仿真程序资产管理")
@Slf4j
@RestController
@RequestMapping("/api/program")
public class ProgramController {

    @Autowired
    private ProgramService programService;

    @ApiOperation("上传仿真程序")
    @PostMapping(value = "/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @RequirePermission(Permission.CREATE)
    @OperationLog(value = "上传仿真程序", type = OperationLog.OperationType.CREATE, recordParams = false)
    public Result<?> handleFileUpload(
            @RequestPart("file") MultipartFile file,
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "description", required = false) String description) throws Exception {

        if (file.isEmpty()) {
            return Result.error("上传文件不能为空。");
        }

        UploadResult result = programService.uploadProgram(file, name, version, description);
        return Result.success(result);
    }

    @ApiOperation("仿真程序元数据详情")
    @GetMapping("/metas")
    @RequirePermission(Permission.READ)
    public Result<ProgramEntity> queryMeta(
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "projectName", required = false) String projectName) {
        ProgramEntity result = programService.queryMeta(name, version, projectName);
        return Result.success(result);
    }

    @ApiOperation("保存仿真程序元数据")
    @PostMapping("/metas")
    @RequirePermission(Permission.UPDATE)
    @OperationLog(value = "保存仿真程序元数据", type = OperationLog.OperationType.UPDATE)
    public Result<Void> saveMeta(@RequestBody ProgramEntity programMetaDto) throws Exception {
        programService.saveProgramMetadata(programMetaDto);
        return Result.success("元数据保存成功");
    }

    @ApiOperation("仿真程序元数据历史")
    @GetMapping("/history")
    @RequirePermission(Permission.READ)
    public Result<List<ProgramEntity>> queryMetaList(
            @RequestParam("name") String name,
            @RequestParam(value = "projectName", required = false) String projectName) {
        return Result.success(programService.queryMetaList(name, projectName));
    }

    @ApiOperation("移除仿真程序资产")
    @DeleteMapping("/delete")
    @RequirePermission(Permission.DELETE)
    @OperationLog(value = "移除仿真程序资产", type = OperationLog.OperationType.DELETE)
    public Result<Void> handleDelete(
            @RequestParam("name") String name,
            @RequestParam(value = "version", required = false) String version,
            @RequestParam(value = "projectName", required = false) String projectName) throws Exception {
        programService.deleteProgram(name, version, projectName);
        return Result.success("操作成功");
    }

    @ApiOperation("仿真程序资产树")
    @GetMapping("/tree")
    @RequirePermission(Permission.READ)
    public Result<?> queryProgramTree(
            @RequestParam(value = "projectName", required = false) String projectName) {
        String effectiveProjectName = projectName;
        if (effectiveProjectName == null || effectiveProjectName.trim().isEmpty()) {
            effectiveProjectName = ProjectContext.getCurrentProject();
        }
        List<String> tree = programService.queryProgramTree(effectiveProjectName);
        return Result.success(tree);
    }

    @ApiOperation("仿真程序列表（分页）")
    @GetMapping("/list")
    @RequirePermission(Permission.READ)
    public Result<List<ProgramEntity>> list(
            @RequestParam(value = "name", required = false) String name,
            @RequestParam(value = "projectName", required = false) String projectName,
            @RequestParam(value = "author", required = false) String author,
            @RequestParam(value = "pageNum", required = false, defaultValue = "1") Integer pageNum,
            @RequestParam(value = "pageSize", required = false, defaultValue = "10") Integer pageSize) {
        return Result.success(programService.queryProgramList(name, projectName, author, pageNum, pageSize));
    }

    @ApiOperation("仿真程序总数")
    @GetMapping("/count")
    @RequirePermission(Permission.READ)
    public Result<Long> count(
            @RequestParam(value = "name", required = false) String name,
            @RequestParam(value = "projectName", required = false) String projectName,
            @RequestParam(value = "author", required = false) String author) {
        return Result.success(programService.countProgramList(name, projectName, author));
    }

    @ApiOperation("运行仿真程序")
    @PostMapping("/run")
    @RequirePermission(Permission.UPDATE)
    public Result<Map<String, Object>> run(@RequestParam("name") String name,
                                           @RequestParam("version") String version,
                                           @RequestParam(value = "stopTime", required = false, defaultValue = "") String stopTime,
                                           @RequestParam(value = "fixedStep", required = false, defaultValue = "") String fixedStep,
                                           @RequestParam(value = "npCommand", required = false, defaultValue = "") String npCommand,
                                           @RequestParam(value = "loadPower", required = false, defaultValue = "") String loadPower,
                                           @RequestParam(value = "modelFile", required = false, defaultValue = "") String modelFile,
                                           @RequestParam(value = "projectName", required = false) String projectName) {
        return programService.run(name, version, stopTime, fixedStep, npCommand, loadPower, modelFile, projectName);
    }

    @ApiOperation("停止仿真程序")
    @PostMapping("/stop")
    @RequirePermission(Permission.UPDATE)
    public Result<Map<String, Object>> stop(@RequestParam("name") String name,
                                            @RequestParam("version") String version,
                                            @RequestParam(value = "projectName", required = false) String projectName) {
        return programService.stop(name, version, projectName);
    }

    @ApiOperation("运行结果")
    @GetMapping("/results")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> results(@RequestParam("name") String name,
                                                @RequestParam("version") String version,
                                                @RequestParam(value = "projectName", required = false) String projectName) {
        return programService.results(name, version, projectName);
    }

    @ApiOperation("更新配置")
    @PostMapping("/update-config")
    @RequirePermission(Permission.UPDATE)
    public Result<ProgramEntity> updateConfig(@RequestParam("name") String name,
                                              @RequestParam("version") String version,
                                              @RequestBody String configJson,
                                              @RequestParam(value = "projectName", required = false) String projectName) {
        return programService.updateConfig(name, version, configJson, projectName);
    }

    @ApiOperation("获取程序目录文件列表")
    @GetMapping("/files")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> getProgramFiles(
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "projectName", required = false) String projectName) {
        return Result.success(programService.getProgramFiles(name, version, projectName));
    }

    @ApiOperation("下载结果包")
    @GetMapping("/download-result")
    @RequirePermission(Permission.READ)
    public ResponseEntity<byte[]> downloadResult(
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            byte[] zipBytes = programService.downloadResultPackage(name, version, projectName);
            String ts = new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
            String filename = "Result_" + ts + ".zip";
            return ResponseEntity.ok()
                    .header("Content-Disposition", "attachment; filename=\"" + filename + "\"")
                    .contentType(MediaType.APPLICATION_OCTET_STREAM)
                    .body(zipBytes);
        } catch (Exception e) {
            log.error("下载结果包失败", e);
            return ResponseEntity.internalServerError().body(null);
        }
    }

    @ApiOperation("上传概览图")
    @PostMapping("/upload-overview")
    @RequirePermission(Permission.UPDATE)
    public Result<Void> uploadOverview(
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "projectName", required = false) String projectName,
            @RequestBody byte[] pngData) {
        try {
            programService.uploadOverview(name, version, projectName, pngData);
            return Result.success("概览图已上传");
        } catch (Exception e) {
            log.error("上传概览图失败", e);
            return Result.error(e.getMessage());
        }
    }

    @ApiOperation("导出信号数据")
    @GetMapping("/download-signal")
    @RequirePermission(Permission.READ)
    public ResponseEntity<byte[]> downloadSignal(
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam("format") String format,
            @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            byte[] data = programService.downloadSignalFile(name, version, format, projectName);
            String filename = "signals." + format.toLowerCase();
            String contentType = "mat".equalsIgnoreCase(format) ? MediaType.APPLICATION_OCTET_STREAM_VALUE : "text/csv";
            return ResponseEntity.ok()
                    .header("Content-Disposition", "attachment; filename=\"" + filename + "\"")
                    .header("Content-Type", contentType)
                    .body(data);
        } catch (Exception e) {
            log.error("导出信号数据失败", e);
            return ResponseEntity.internalServerError().body(null);
        }
    }
}
