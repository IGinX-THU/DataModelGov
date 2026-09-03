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
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
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

    @ApiOperation("获取仿真程序配置（program-config.json）")
    @GetMapping("/config")
    @RequirePermission(Permission.READ)
    public Result<String> getConfig(
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "projectName", required = false) String projectName) {
        String config = programService.getProgramConfig(name, version, projectName);
        return Result.success("操作成功", config);
    }

    @ApiOperation("保存仿真程序配置（program-config.json）")
    @PutMapping("/config")
    @RequirePermission(Permission.UPDATE)
    @OperationLog(value = "保存仿真程序配置", type = OperationLog.OperationType.UPDATE)
    public Result<Void> saveConfig(
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "projectName", required = false) String projectName,
            @RequestBody String configJson) {
        java.util.List<String> errors = programService.saveProgramConfig(name, version, projectName, configJson);
        if (errors != null && !errors.isEmpty()) {
            return Result.error("配置校验失败: " + String.join("; ", errors));
        }
        return Result.success("配置保存成功");
    }

    @ApiOperation("列出可接入的预置程序")
    @GetMapping("/preset-programs")
    @RequirePermission(Permission.READ)
    public Result<List<Map<String, String>>> listPresetPrograms() {
        List<Map<String, String>> programs = new java.util.ArrayList<>();
        try {
            org.springframework.core.io.support.PathMatchingResourcePatternResolver resolver =
                    new org.springframework.core.io.support.PathMatchingResourcePatternResolver();
            org.springframework.core.io.Resource[] resources =
                    resolver.getResources("classpath:programs/*/*");
            java.util.Set<String> programNames = new java.util.LinkedHashSet<>();
            for (org.springframework.core.io.Resource res : resources) {
                String url = res.getURL().toString();
                int idx = url.lastIndexOf("/programs/");
                if (idx < 0) continue;
                String tail = url.substring(idx + "/programs/".length());
                int slash = tail.indexOf('/');
                if (slash < 0) continue;
                String programName = tail.substring(0, slash);
                String filename = tail.substring(slash + 1).toLowerCase();
                if (filename.endsWith(".zip") || filename.endsWith(".rar") || filename.endsWith(".7z") || filename.endsWith(".tar.gz") || filename.endsWith(".tgz") || filename.endsWith(".tar")) {
                    programNames.add(programName);
                }
            }
            for (String name : programNames) {
                Map<String, String> p = new java.util.LinkedHashMap<>();
                p.put("id", name);
                p.put("name", name);
                programs.add(p);
            }
        } catch (Exception e) {
            log.warn("扫描预置程序失败: {}", e.getMessage());
        }
        return Result.success("操作成功", programs);
    }

    @ApiOperation("上传预置程序（从 resources/programs/ 读取源码+配置+脚本存入 IGinX）")
    @PostMapping("/preset-programs/{id}/upload")
    @RequirePermission(Permission.CREATE)
    @OperationLog(value = "上传预置程序", type = OperationLog.OperationType.CREATE)
    public Result<Map<String, Object>> uploadPresetProgram(
            @PathVariable("id") String id,
            @RequestParam(value = "version", required = false, defaultValue = "1.0") String version,
            @RequestParam(value = "projectName", required = false) String projectName,
            @RequestParam(value = "name", required = false) String displayName) {
        try {
            Map<String, Object> result = programService.uploadPresetProgram(id, version, projectName, displayName);
            return Result.success("预置程序已上传", result);
        } catch (Exception e) {
            log.error("上传预置程序失败", e);
            return Result.error("上传失败: " + e.getMessage());
        }
    }

    @ApiOperation("列出可用的预置配置（扫描 programs/ 目录）")
    @GetMapping("/config-templates")    @RequirePermission(Permission.READ)
    public Result<List<Map<String, String>>> listConfigTemplates() {
        List<Map<String, String>> templates = new java.util.ArrayList<>();
        try {
            org.springframework.core.io.support.PathMatchingResourcePatternResolver resolver =
                    new org.springframework.core.io.support.PathMatchingResourcePatternResolver();
            org.springframework.core.io.Resource[] resources =
                    resolver.getResources("classpath:programs/*/config.json");
            for (org.springframework.core.io.Resource res : resources) {
                String url = res.getURL().toString();
                int idx = url.lastIndexOf("/programs/");
                if (idx < 0) continue;
                String tail = url.substring(idx + "/programs/".length());
                int slash = tail.indexOf('/');
                if (slash < 0) continue;
                String programName = tail.substring(0, slash);
                Map<String, String> tpl = new java.util.LinkedHashMap<>();
                tpl.put("id", programName);
                tpl.put("name", programName);
                templates.add(tpl);
            }
        } catch (Exception e) {
            log.warn("扫描预置配置失败: {}", e.getMessage());
        }
        return Result.success("操作成功", templates);
    }

    @ApiOperation("获取预置配置内容（config.json，不含脚本）")
    @GetMapping("/config-templates/{id}")
    @RequirePermission(Permission.READ)
    public Result<String> getConfigTemplate(@PathVariable("id") String id) {
        try {
            String content = readClasspathResource("programs/" + id + "/config.json");
            if (content == null) return Result.error("预置配置不存在");
            return Result.success("操作成功", content);
        } catch (Exception e) {
            log.warn("读取预置配置失败: {}", e.getMessage());
            return Result.error("读取失败: " + e.getMessage());
        }
    }

    @ApiOperation("获取预置程序的信号采集脚本（dmg_setup.m）")
    @GetMapping("/config-templates/{id}/setup-script")
    @RequirePermission(Permission.READ)
    public Result<String> getPresetSetupScript(@PathVariable("id") String id) {
        try {
            String content = readClasspathResource("programs/" + id + "/dmg_setup.m");
            if (content == null) return Result.error("脚本不存在");
            return Result.success("操作成功", content);
        } catch (Exception e) {
            log.warn("读取预置脚本失败: {}", e.getMessage());
            return Result.error("读取失败: " + e.getMessage());
        }
    }

    @ApiOperation("列出可用的页面模板")
    @GetMapping("/templates")
    @RequirePermission(Permission.READ)
    public Result<List<Map<String, String>>> listTemplates() {
        List<Map<String, String>> templates = new java.util.ArrayList<>();
        try {
            org.springframework.core.io.support.PathMatchingResourcePatternResolver resolver =
                    new org.springframework.core.io.support.PathMatchingResourcePatternResolver();
            org.springframework.core.io.Resource[] resources =
                    resolver.getResources("classpath:templates/*/template.json");
            for (org.springframework.core.io.Resource res : resources) {
                String url = res.getURL().toString();
                int idx = url.lastIndexOf("/templates/");
                if (idx < 0) continue;
                String tail = url.substring(idx + "/templates/".length());
                int slash = tail.indexOf('/');
                if (slash < 0) continue;
                String templateId = tail.substring(0, slash);
                Map<String, String> tpl = new java.util.LinkedHashMap<>();
                tpl.put("id", templateId);
                tpl.put("name", templateId);
                templates.add(tpl);
            }
        } catch (Exception e) {
            log.warn("扫描页面模板失败: {}", e.getMessage());
        }
        return Result.success("操作成功", templates);
    }

    @ApiOperation("获取页面模板内容（template.json）")
    @GetMapping("/templates/{id}")
    @RequirePermission(Permission.READ)
    public Result<String> getTemplate(@PathVariable("id") String id) {
        try {
            String content = readClasspathResource("templates/" + id + "/template.json");
            if (content == null) return Result.error("模板不存在");
            return Result.success("操作成功", content);
        } catch (Exception e) {
            log.warn("读取页面模板失败: {}", e.getMessage());
            return Result.error("读取失败: " + e.getMessage());
        }
    }

    @ApiOperation("获取仿真程序的信号采集脚本")
    @GetMapping("/setup-script")
    @RequirePermission(Permission.READ)
    public Result<String> getSetupScript(
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "projectName", required = false) String projectName) {
        String script = programService.getProgramSetupScript(name, version, projectName);
        return Result.success("操作成功", script);
    }

    @ApiOperation("保存仿真程序的信号采集脚本")
    @PutMapping(value = "/setup-script", consumes = {"text/plain", "application/json"})
    @RequirePermission(Permission.UPDATE)
    @OperationLog(value = "保存信号采集脚本", type = OperationLog.OperationType.UPDATE)
    public Result<Void> saveSetupScript(
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "projectName", required = false) String projectName,
            @RequestBody String setupScript) {
        java.util.List<String> errors = programService.saveProgramSetupScript(name, version, projectName, setupScript);
        if (errors != null && !errors.isEmpty()) {
            return Result.error("保存失败: " + String.join("; ", errors));
        }
        return Result.success("脚本保存成功");
    }

    /** 读取 classpath 资源为字符串 */
    private String readClasspathResource(String path) throws IOException {
        org.springframework.core.io.support.PathMatchingResourcePatternResolver resolver =
                new org.springframework.core.io.support.PathMatchingResourcePatternResolver();
        org.springframework.core.io.Resource res = resolver.getResource("classpath:" + path);
        if (!res.exists()) return null;
        try (java.io.InputStream is = res.getInputStream()) {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = is.read(buf)) > 0) out.write(buf, 0, n);
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        }
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
                                           @RequestParam(value = "modelFile", required = false, defaultValue = "") String modelFile,
                                           @RequestParam(value = "projectName", required = false) String projectName,
                                           @RequestParam Map<String, String> allParams) {
        // 从全部参数中剥离固定项，剩余的作为动态参数透传（由 ProgramConfig.parameters 定义）
        java.util.Map<String, String> params = new java.util.LinkedHashMap<>(allParams);
        for (String k : new String[]{"name", "version", "stopTime", "fixedStep", "modelFile", "projectName"}) {
            params.remove(k);
        }
        return programService.run(name, version, stopTime, fixedStep, modelFile, projectName, params);
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

    @ApiOperation("实时仿真数据（增量）")
    @GetMapping("/live-data")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> liveData(@RequestParam("name") String name,
                                                 @RequestParam("version") String version,
                                                 @RequestParam(value = "projectName", required = false) String projectName) {
        return programService.getLiveData(name, version, projectName);
    }

    @ApiOperation("实时仿真数据 SSE 流（服务器主动推送，避免轮询）")
    @GetMapping(value = "/live-stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    @RequirePermission(Permission.READ)
    public SseEmitter liveStream(@RequestParam("name") String name,
                                 @RequestParam("version") String version,
                                 @RequestParam(value = "projectName", required = false) String projectName) {
        return programService.subscribeLiveData(name, version, projectName);
    }

    @ApiOperation("暂停仿真")
    @PostMapping("/pause")
    @RequirePermission(Permission.UPDATE)
    public Result<Map<String, Object>> pause(@RequestParam("name") String name,
                                             @RequestParam("version") String version,
                                             @RequestParam(value = "projectName", required = false) String projectName) {
        return programService.pause(name, version, projectName);
    }

    @ApiOperation("恢复仿真")
    @PostMapping("/resume")
    @RequirePermission(Permission.UPDATE)
    public Result<Map<String, Object>> resume(@RequestParam("name") String name,
                                              @RequestParam("version") String version,
                                              @RequestParam(value = "projectName", required = false) String projectName) {
        return programService.resume(name, version, projectName);
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

    @ApiOperation("下载程序原始压缩包")
    @PostMapping("/download")
    @RequirePermission(Permission.READ)
    @OperationLog(value = "下载程序文件", type = OperationLog.OperationType.EXPORT, recordResult = false)
    public void handleFileDownload(
            @RequestParam("name") String name,
            @RequestParam("version") String version,
            @RequestParam(value = "projectName", required = false) String projectName,
            HttpServletResponse response) throws Exception {
        // 从 IGinX 读取上传时存储的原始字节（含 chunkCount 完整性 + MD5 校验），
        // 确保下载包与原始上传包一致，再上传时内容不会缺失。
        byte[] fileData = programService.downloadProgram(name, version, projectName);
        // 使用原始上传文件名（含扩展名），保证再上传时扩展名识别正确
        ProgramEntity entity = programService.queryMeta(name, version, projectName);
        String fileName = (entity != null && entity.getFileName() != null && !entity.getFileName().isEmpty())
                ? entity.getFileName() : (name + "_" + version + ".zip");
        String encodedFilename = URLEncoder.encode(fileName, StandardCharsets.UTF_8.name())
                .replace("+", "%20");
        response.setContentType(MediaType.APPLICATION_OCTET_STREAM_VALUE);
        response.setHeader(HttpHeaders.CONTENT_DISPOSITION,
                "attachment; filename=\"" + encodedFilename + "\"; filename*=UTF-8''" + encodedFilename);
        response.setContentLength(fileData.length);
        response.getOutputStream().write(fileData);
        response.flushBuffer();
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

    @ApiOperation("MATLAB 引擎状态")
    @GetMapping("/engine-status")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> engineStatus() {
        return programService.getEngineStatus();
    }

    @ApiOperation("重启 MATLAB 引擎")
    @PostMapping("/engine-restart")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> engineRestart() {
        return programService.restartEngine();
    }
}
