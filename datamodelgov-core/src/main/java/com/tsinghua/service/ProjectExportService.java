package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.QueryClient;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.query.IginXColumn;
import cn.edu.tsinghua.iginx.session_v2.query.IginXHeader;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.query.SimpleQuery;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.dto.ProjectExportRequest;
import com.tsinghua.entity.AlgorithmMetaEntity;
import com.tsinghua.entity.DataArchiveEntity;
import com.tsinghua.entity.ModelMetaEntity;
import com.tsinghua.entity.ProjectEntity;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import javax.servlet.http.HttpServletResponse;
import java.io.BufferedOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.stream.Collectors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

/**
 * 项目导出服务
 * 支持用户自定义选择要导出的资源类型（模型文件、算法文件、数据CSV文件）
 * 将选中资源封装为压缩包供下载，支持单一导出或组合打包导出
 */
@Slf4j
@Service
public class ProjectExportService {

    @Autowired
    private ProjectService projectService;

    @Autowired
    private AlgorithmFileService algorithmFileService;

    @Autowired
    private ModelFileService modelFileService;

    @Autowired
    private DataArchiveService dataArchiveService;

    @Autowired
    private SimulationArchiveService simulationArchiveService;

    @Autowired
    private SimulationExecutionService simulationExecutionService;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private Session iginxSession;

    @Autowired
    private ObjectMapper objectMapper;

    /**
     * 导出项目资源为ZIP压缩包
     */
    public void exportAllProject(ProjectExportRequest request, HttpServletResponse response) throws Exception {
        request.setIncludeAlgorithms(true);
        request.setIncludeModels(true);
        request.setIncludeDataCsv(true);
        request.setIncludeSimulationArchives(true);
        exportProject(request, response);
    }

    public void exportResource(String projectName, String resourceType, HttpServletResponse response) throws Exception {
        ProjectExportRequest request = new ProjectExportRequest();
        request.setProjectName(projectName);
        request.setIncludeAlgorithms(false);
        request.setIncludeModels(false);
        request.setIncludeDataCsv(false);
        request.setIncludeSimulationArchives(false);

        String normalizedType = resourceType == null ? "" : resourceType.trim().toLowerCase(Locale.ROOT);
        switch (normalizedType) {
            case "algorithm":
            case "algorithms":
                request.setIncludeAlgorithms(true);
                break;
            case "model":
            case "models":
                request.setIncludeModels(true);
                break;
            case "data":
            case "datas":
                request.setIncludeDataCsv(true);
                break;
            case "simulation":
            case "simulations":
                request.setIncludeSimulationArchives(true);
                break;
            default:
                throw new IllegalArgumentException("不支持的资源类型: " + resourceType);
        }

        request.setResourceType(normalizedType);
        exportProject(request, response);
    }

    public void exportProject(ProjectExportRequest request, HttpServletResponse response) throws Exception {
        String projectName = request.getProjectName();

        // 1. 验证项目存在且当前用户有权限
        ProjectEntity project = projectService.findByName(projectName);
        if (project == null) {
            throw new IllegalArgumentException("项目不存在: " + projectName);
        }

        if (!AuthUtil.isAdmin() && !AuthUtil.getCurrentUsername().equals(project.getOwner())) {
            throw new SecurityException("无权导出该项目，只有项目所有者或管理员可以导出");
        }

        // 2. 设置响应头
        String resourceType = request.getResourceType();
        String typeSuffix = (resourceType != null && !resourceType.isEmpty()) ? "_" + resourceType : "";
        String zipFileName = projectName + typeSuffix + "_export_" + System.currentTimeMillis() + ".zip";
        response.setContentType("application/zip");
        response.setCharacterEncoding("UTF-8");
        response.setHeader("Content-Disposition",
                "attachment; filename=\"" + zipFileName + "\"");
        response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");

        // 3. 创建ZIP输出流
        try (ZipOutputStream zos = new ZipOutputStream(new BufferedOutputStream(response.getOutputStream()))) {
            // 4. 写入清单文件
            writeManifest(zos, project, request);

            // 5. 写入项目元数据
            writeProjectMeta(zos, project);

            // 6. 按用户选择导出各类资源
            int exportedCount = 0;

            if (Boolean.TRUE.equals(request.getIncludeAlgorithms())) {
                exportedCount += exportAlgorithms(zos, project);
            }

            if (Boolean.TRUE.equals(request.getIncludeModels())) {
                exportedCount += exportModels(zos, project);
            }

            if (Boolean.TRUE.equals(request.getIncludeDataCsv())) {
                exportedCount += exportDataCsv(zos, project);
            }

            if (Boolean.TRUE.equals(request.getIncludeSimulationArchives())) {
                exportedCount += exportSimulationArchives(zos, project);
            }

            if (exportedCount == 0) {
                log.warn("项目 {} 导出时未选择任何资源类型", projectName);
            }

            zos.flush();
            zos.finish();
            log.info("项目 {} 导出完成，共导出 {} 项资源", projectName, exportedCount);

        } catch (Exception e) {
            log.error("项目导出失败: {}", projectName, e);
            throw e;
        }
    }

    /**
     * 写入导出清单文件
     */
    private void writeManifest(ZipOutputStream zos, ProjectEntity project, ProjectExportRequest request) throws Exception {
        Map<String, Object> manifest = new LinkedHashMap<>();
        manifest.put("version", "1.0");
        manifest.put("exportTime", System.currentTimeMillis());
        manifest.put("projectName", project.getName());
        manifest.put("originalOwner", project.getOwner());
        manifest.put("exportUser", AuthUtil.getCurrentUsername());
        manifest.put("resourceType", request.getResourceType());
        manifest.put("includeAlgorithms", request.getIncludeAlgorithms());
        manifest.put("includeModels", request.getIncludeModels());
        manifest.put("includeDataCsv", request.getIncludeDataCsv());
        manifest.put("includeSimulationArchives", request.getIncludeSimulationArchives());

        String json = objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(manifest);
        writeZipEntry(zos, "manifest.json", json.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * 写入项目元数据
     */
    private void writeProjectMeta(ZipOutputStream zos, ProjectEntity project) throws Exception {
        String json = objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(project);
        writeZipEntry(zos, "project.json", json.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * 导出算法文件和元数据
     */
    private int exportAlgorithms(ZipOutputStream zos, ProjectEntity project) throws Exception {
        String algorithmsField = project.getAlgorithms();
        if (!StringUtils.hasText(algorithmsField)) {
            log.info("项目 {} 无关联算法", project.getName());
            return 0;
        }

        List<String> allAlgorithmPaths = Arrays.stream(algorithmsField.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .collect(Collectors.toList());

        int count = 0;
        for (String storagePath : allAlgorithmPaths) {
            try {
                // 从 storagePath 解析 name 和 version
                // 格式: algorithms_system.{projectName}.{name}.{version}
                String[] parts = storagePath.split("\\.");
                if (parts.length < 4) {
                    log.warn("算法存储路径格式不正确: {}", storagePath);
                    continue;
                }
                String name = parts[2];
                String version = parts[3].replace('_', '.');

                // 查询元数据
                AlgorithmMetaEntity meta = algorithmFileService.queryMeta(name, version);
                if (meta == null) {
                    log.warn("算法元数据不存在: {} v{}", name, version);
                    continue;
                }

                // 写入元数据
                String metaJson = objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(meta);
                writeZipEntry(zos, "algorithms/meta/" + name + "_" + version + ".json",
                        metaJson.getBytes(StandardCharsets.UTF_8));

                // 下载并写入算法二进制文件
                byte[] fileData = algorithmFileService.downloadAlgorithm(name, version);
                writeZipEntry(zos, "algorithms/files/" + meta.getFileName(), fileData);

                count++;
                log.info("已导出算法: {} v{}", name, version);
            } catch (Exception e) {
                log.error("导出算法失败: {}", storagePath, e);
            }
        }
        return count;
    }

    /**
     * 导出模型文件和元数据
     */
    private int exportModels(ZipOutputStream zos, ProjectEntity project) throws Exception {
        String modelsField = project.getModels();
        if (!StringUtils.hasText(modelsField)) {
            log.info("项目 {} 无关联模型", project.getName());
            return 0;
        }

        List<String> allModelPaths = Arrays.stream(modelsField.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .collect(Collectors.toList());

        int count = 0;
        for (String storagePath : allModelPaths) {
            try {
                // 格式: models_system.{projectName}.{name}.{version}
                String[] parts = storagePath.split("\\.");
                if (parts.length < 4) {
                    log.warn("模型存储路径格式不正确: {}", storagePath);
                    continue;
                }
                String name = parts[2];
                String version = parts[3].replace('_', '.');

                // 查询元数据
                ModelMetaEntity meta = modelFileService.queryMeta(name, version);
                if (meta == null) {
                    log.warn("模型元数据不存在: {} v{}", name, version);
                    continue;
                }

                // 写入元数据
                String metaJson = objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(meta);
                writeZipEntry(zos, "models/meta/" + name + "_" + version + ".json",
                        metaJson.getBytes(StandardCharsets.UTF_8));

                // 下载并写入模型二进制文件
                byte[] fileData = modelFileService.downloadModel(name, version);
                writeZipEntry(zos, "models/files/" + meta.getFileName(), fileData);

                count++;
                log.info("已导出模型: {} v{}", name, version);
            } catch (Exception e) {
                log.error("导出模型失败: {}", storagePath, e);
            }
        }
        return count;
    }

    /**
     * 导出数据CSV文件
     * project.datas中存储的是路径前缀（如project1.device1），
     * 需要先用showColumns()展开为实际的测量路径，再逐个查询导出
     */
    private int exportDataCsv(ZipOutputStream zos, ProjectEntity project) throws Exception {
        String datasField = project.getDatas();
        if (!StringUtils.hasText(datasField)) {
            log.info("项目 {} 无关联数据", project.getName());
            return 0;
        }

        List<String> dataPathPrefixes = Arrays.stream(datasField.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .collect(Collectors.toList());

        if (dataPathPrefixes.isEmpty()) {
            log.info("项目 {} 无匹配的数据路径", project.getName());
            return 0;
        }

        // 用showColumns()获取所有列，然后按前缀分组
        List<cn.edu.tsinghua.iginx.session.Column> allColumns = iginxSession.showColumns();
        Map<String, List<String>> prefixToMeasurements = new LinkedHashMap<>();
        for (String prefix : dataPathPrefixes) {
            List<String> measurements = allColumns.stream()
                    .filter(col -> col.getPath().startsWith(prefix + ".") || col.getPath().equals(prefix))
                    .filter(col -> !col.getPath().contains("relational_system"))
                    .filter(col -> !col.getPath().startsWith("algorithms_system"))
                    .filter(col -> !col.getPath().startsWith("models_system"))
                    .map(col -> col.getPath())
                    .collect(Collectors.toList());
            if (!measurements.isEmpty()) {
                prefixToMeasurements.put(prefix, measurements);
            }
        }

        int count = 0;
        QueryClient queryClient = iginxClient.getQueryClient();

        for (Map.Entry<String, List<String>> entry : prefixToMeasurements.entrySet()) {
            String prefix = entry.getKey();
            List<String> measurements = entry.getValue();

            // 导出该前缀对应的数据档案元数据
            DataArchiveEntity archive = findDataArchiveForExport(project.getName(), prefix);
            if (archive != null) {
                try {
                    String archiveJson = objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(archive);
                    String archiveDir = "data/" + prefix.replace(".", "_");
                    writeZipEntry(zos, archiveDir + "/archive.json",
                            archiveJson.getBytes(StandardCharsets.UTF_8));
                } catch (Exception e) {
                    log.warn("导出数据档案元数据失败: {}", prefix, e);
                }
            }

            // 按前缀查询所有测量路径的数据
            try {
                SimpleQuery query = SimpleQuery.builder()
                        .addMeasurements(new HashSet<>(measurements))
                        .startKey(0L)
                        .endKey(Long.MAX_VALUE)
                        .build();

                IginXTable table = queryClient.query(query);
                if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) {
                    log.warn("数据路径 {} 无数据", prefix);
                    continue;
                }

                // 转为CSV
                String csv = convertTableToCsv(table);
                String csvFileName = prefix.replace(".", "_") + ".csv";
                writeZipEntry(zos, "data/" + csvFileName, csv.getBytes(StandardCharsets.UTF_8));

                count++;
                log.info("已导出数据: {} ({} 个测量路径)", prefix, measurements.size());
            } catch (Exception e) {
                log.error("导出数据失败: {}", prefix, e);
            }
        }
        return count;
    }

    private DataArchiveEntity findDataArchiveForExport(String projectName, String dataPath) {
        try {
            List<DataArchiveEntity> archives = dataArchiveService.queryArchives(null, null, projectName, null, null, null);
            for (DataArchiveEntity archive : archives) {
                if (dataPath.equals(archive.getName())
                        || (archive.getConfig() != null && archive.getConfig().contains(dataPath))) {
                    return archive;
                }
            }
        } catch (Exception e) {
            log.warn("按项目查询数据档案失败: project={}, dataPath={}", projectName, dataPath, e);
        }
        return dataArchiveService.findByName(dataPath);
    }

    /**
     * 将IginXTable转为CSV字符串
     * 添加UTF-8 BOM以支持Excel正确打开，去掉每行末尾多余逗号
     */
    private String convertTableToCsv(IginXTable table) {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        try {
            // 写入UTF-8 BOM，确保Excel能正确识别编码
            baos.write(new byte[]{(byte) 0xEF, (byte) 0xBB, (byte) 0xBF});

            OutputStreamWriter writer = new OutputStreamWriter(baos, StandardCharsets.UTF_8);
            IginXHeader header = table.getHeader();

            // 写表头
            StringBuilder headerLine = new StringBuilder();
            if (header.hasTimestamp()) {
                headerLine.append("key,");
            }
            for (IginXColumn column : header.getColumns()) {
                headerLine.append(column.getName()).append(",");
            }
            // 去掉末尾逗号
            if (headerLine.length() > 0 && headerLine.charAt(headerLine.length() - 1) == ',') {
                headerLine.setLength(headerLine.length() - 1);
            }
            writer.write(headerLine.toString());
            writer.write("\n");

            // 写数据行
            for (IginXRecord record : table.getRecords()) {
                StringBuilder dataLine = new StringBuilder();
                if (header.hasTimestamp()) {
                    dataLine.append(record.getKey()).append(",");
                }
                for (IginXColumn column : header.getColumns()) {
                    Object value = record.getValue(column.getName());
                    if (value instanceof byte[]) {
                        dataLine.append(ConvertUtil.bytesToString((byte[]) value));
                    } else {
                        String strVal = String.valueOf(value);
                        // 如果值包含逗号、换行或引号，用双引号包裹并转义
                        if (strVal.contains(",") || strVal.contains("\n") || strVal.contains("\"")) {
                            strVal = "\"" + strVal.replace("\"", "\"\"") + "\"";
                        }
                        dataLine.append(strVal);
                    }
                    dataLine.append(",");
                }
                // 去掉末尾逗号
                if (dataLine.length() > 0 && dataLine.charAt(dataLine.length() - 1) == ',') {
                    dataLine.setLength(dataLine.length() - 1);
                }
                writer.write(dataLine.toString());
                writer.write("\n");
            }

            writer.flush();
        } catch (Exception e) {
            log.error("转换CSV失败", e);
        }
        return new String(baos.toByteArray(), StandardCharsets.UTF_8);
    }

    /**
     * 导出仿真档案及执行记录
     */
    private int exportSimulationArchives(ZipOutputStream zos, ProjectEntity project) throws Exception {
        String projectName = project.getName();
        int count = 0;

        // 查询该项目下的所有仿真档案
        List<com.tsinghua.entity.SimulationArchiveEntity> archives =
                simulationArchiveService.queryArchives(null, projectName, null, null, 1, 10000);

        if (archives == null || archives.isEmpty()) {
            log.info("项目 {} 无仿真档案", projectName);
            return 0;
        }

        for (com.tsinghua.entity.SimulationArchiveEntity archive : archives) {
            try {
                // 写入档案元数据
                String archiveJson = objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(archive);
                String archiveDir = "simulation/archives/" + archive.getCreateTime();
                writeZipEntry(zos, archiveDir + "/archive.json",
                        archiveJson.getBytes(StandardCharsets.UTF_8));

                // 查询该档案的执行记录
                List<com.tsinghua.entity.SimulationExecutionEntity> executions =
                        simulationExecutionService.queryExecutions(
                                archive.getName(), null, null, null, 1, 10000);

                if (executions != null && !executions.isEmpty()) {
                    for (com.tsinghua.entity.SimulationExecutionEntity execution : executions) {
                        // 只导出属于该档案的执行记录
                        if (execution.getArchiveId() != null
                                && execution.getArchiveId().equals(archive.getCreateTime())) {
                            String execJson = objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(execution);
                            writeZipEntry(zos, archiveDir + "/executions/" + execution.getTimestamp() + ".json",
                                    execJson.getBytes(StandardCharsets.UTF_8));

                            // 导出任务目录文件
                            Path taskDir = java.nio.file.Paths.get("project", projectName, "job", "simulation", String.valueOf(execution.getTimestamp()));
                            if (java.nio.file.Files.exists(taskDir)) {
                                exportDirectoryToZip(zos, taskDir, archiveDir + "/executions/" + execution.getTimestamp() + "_files");
                            } else {
                                // 尝试检查是否是旧的一级目录结构（兼容性）
                                Path oldTaskDir = java.nio.file.Paths.get("project", projectName, "job", "simulation");
                                if (java.nio.file.Files.exists(oldTaskDir)) {
                                    try (java.util.stream.Stream<Path> stream = java.nio.file.Files.list(oldTaskDir)) {
                                        stream.filter(path -> path.getFileName().toString().equals(String.valueOf(execution.getTimestamp())))
                                              .forEach(dir -> {
                                                  try {
                                                      exportDirectoryToZip(zos, dir, archiveDir + "/executions/" + execution.getTimestamp() + "_files");
                                                  } catch (IOException e) {
                                                      log.warn("导出任务目录失败: {}", dir, e);
                                                  }
                                              });
                                    } catch (IOException e) {
                                        log.warn("列出任务目录失败", e);
                                    }
                                }
                            }
                        }
                    }
                }

                count++;
                log.info("已导出仿真档案: {}", archive.getName());
            } catch (Exception e) {
                log.error("导出仿真档案失败: {}", archive.getName(), e);
            }
        }
        return count;
    }

    /**
     * 递归导出目录到ZIP
     */
    private void exportDirectoryToZip(ZipOutputStream zos, Path sourceDir, String zipPrefix) throws IOException {
        if (!Files.exists(sourceDir) || !Files.isDirectory(sourceDir)) {
            return;
        }

        try (java.util.stream.Stream<Path> stream = Files.walk(sourceDir)) {
            stream.filter(path -> !Files.isDirectory(path))
                  .forEach(path -> {
                      try {
                          String relativePath = sourceDir.relativize(path).toString().replace("\\", "/");
                          String entryName = zipPrefix + "/" + relativePath;
                          byte[] content = Files.readAllBytes(path);
                          writeZipEntry(zos, entryName, content);
                      } catch (IOException e) {
                          log.warn("导出文件失败: {}", path, e);
                      }
                  });
        }
    }

    /**
     * 向ZIP写入一个条目
     */
    private void writeZipEntry(ZipOutputStream zos, String entryName, byte[] data) throws IOException {
        ZipEntry entry = new ZipEntry(entryName);
        zos.putNextEntry(entry);
        zos.write(data);
        zos.closeEntry();
    }
}
