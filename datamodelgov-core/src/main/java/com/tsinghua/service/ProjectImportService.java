package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.AlgorithmMetaEntity;
import com.tsinghua.entity.DataArchiveEntity;
import com.tsinghua.entity.ModelMetaEntity;
import com.tsinghua.entity.ProjectEntity;
import com.tsinghua.entity.SimulationArchiveEntity;
import com.tsinghua.entity.SimulationExecutionEntity;
import com.tsinghua.util.ProjectContext;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * 项目导入服务
 * 从导出的ZIP压缩包中恢复项目资源（模型文件、算法文件、数据CSV文件）
 */
@Slf4j
@Service
public class ProjectImportService {

    @Autowired
    private ProjectService projectService;

    @Autowired
    private AlgorithmFileService algorithmFileService;

    @Autowired
    private ModelFileService modelFileService;

    @Autowired
    private DataTableService dataTableService;

    @Autowired
    private DataArchiveService dataArchiveService;

    @Autowired
    private SimulationArchiveService simulationArchiveService;

    @Autowired
    private SimulationExecutionService simulationExecutionService;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private ObjectMapper objectMapper;

    private static final int CHUNK_SIZE = 65536; // 64KB，与上传一致

    /**
     * 从ZIP压缩包导入项目资源
     *
     * @param file       上传的ZIP文件
     * @param projectName 目标项目名称（如果为空则使用导出时的项目名）
     * @return 导入结果摘要
     */
    public Map<String, Object> importProject(MultipartFile file, String projectName) throws Exception {
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("导入文件不能为空");
        }

        Map<String, Object> result = new LinkedHashMap<>();
        int algorithmCount = 0;
        int modelCount = 0;
        int dataCount = 0;
        int simulationCount = 0;

        // 先将ZIP保存到临时文件
        Path tempZipPath = Files.createTempFile("project_import_", ".zip");
        try {
            file.transferTo(tempZipPath.toFile());

            try (ZipInputStream zis = new ZipInputStream(new BufferedInputStream(Files.newInputStream(tempZipPath)), StandardCharsets.UTF_8)) {
                ZipEntry entry;
                String manifestJson = null;
                String projectJson = null;
                Map<String, byte[]> algorithmMetaMap = new LinkedHashMap<>();
                Map<String, byte[]> algorithmFileMap = new LinkedHashMap<>();
                Map<String, byte[]> modelMetaMap = new LinkedHashMap<>();
                Map<String, byte[]> modelFileMap = new LinkedHashMap<>();
                Map<String, byte[]> dataCsvMap = new LinkedHashMap<>();
                Map<String, byte[]> dataArchiveMap = new LinkedHashMap<>();
                Map<String, byte[]> simulationArchiveMap = new LinkedHashMap<>();
                Map<String, byte[]> simulationExecutionMap = new LinkedHashMap<>();
                Map<String, byte[]> simulationTaskFilesMap = new LinkedHashMap<>();

                // 第一遍：读取所有ZIP条目到内存
                while ((entry = zis.getNextEntry()) != null) {
                    if (entry.isDirectory()) {
                        zis.closeEntry();
                        continue;
                    }

                    String entryName = entry.getName();
                    byte[] content = readZipEntry(zis);
                    zis.closeEntry();

                    if ("manifest.json".equals(entryName)) {
                        manifestJson = new String(content, StandardCharsets.UTF_8);
                    } else if ("project.json".equals(entryName)) {
                        projectJson = new String(content, StandardCharsets.UTF_8);
                    } else if (entryName.startsWith("algorithms/meta/")) {
                        algorithmMetaMap.put(entryName, content);
                    } else if (entryName.startsWith("algorithms/files/")) {
                        algorithmFileMap.put(entryName, content);
                    } else if (entryName.startsWith("models/meta/")) {
                        modelMetaMap.put(entryName, content);
                    } else if (entryName.startsWith("models/files/")) {
                        modelFileMap.put(entryName, content);
                    } else if (entryName.startsWith("data/") && entryName.endsWith(".csv")) {
                        dataCsvMap.put(entryName, content);
                    } else if (entryName.startsWith("data/") && entryName.endsWith("_archive.json")) {
                        dataArchiveMap.put(entryName, content);
                    } else if (entryName.startsWith("simulation/archives/") && entryName.endsWith("/archive.json")) {
                        simulationArchiveMap.put(entryName, content);
                    } else if (entryName.startsWith("simulation/archives/") && entryName.endsWith(".json") && entryName.contains("/executions/") && !entryName.contains("_files")) {
                        simulationExecutionMap.put(entryName, content);
                    } else if (entryName.startsWith("simulation/archives/") && entryName.contains("_files")) {
                        simulationTaskFilesMap.put(entryName, content);
                    } else {
                        log.debug("跳过未识别的ZIP条目: {}", entryName);
                    }
                }

                // 解析manifest
                if (manifestJson == null) {
                    throw new IllegalArgumentException("无效的导出文件：缺少manifest.json");
                }

                @SuppressWarnings("unchecked")
                Map<String, Object> manifest = objectMapper.readValue(manifestJson, Map.class);
                String originalProjectName = (String) manifest.get("projectName");
                String targetProjectName = StringUtils.hasText(projectName) ? projectName : originalProjectName;

                result.put("originalProjectName", originalProjectName);
                result.put("targetProjectName", targetProjectName);

                // 设置项目上下文
                ProjectContext.setCurrentProject(targetProjectName);

                // 解析并创建/验证项目
                if (projectJson != null) {
                    ProjectEntity projectEntity = objectMapper.readValue(projectJson, ProjectEntity.class);
                    algorithmCount += importProjectEntity(projectEntity, targetProjectName);
                } else {
                    // 确保项目存在
                    ProjectEntity existing = projectService.findByName(targetProjectName);
                    if (existing == null) {
                        throw new IllegalArgumentException("目标项目不存在: " + targetProjectName + "，请先创建项目");
                    }
                }

                // 导入算法
                if (!algorithmMetaMap.isEmpty()) {
                    algorithmCount = importAlgorithms(algorithmMetaMap, algorithmFileMap, targetProjectName);
                    result.put("algorithmCount", algorithmCount);
                }

                // 导入模型
                if (!modelMetaMap.isEmpty()) {
                    modelCount = importModels(modelMetaMap, modelFileMap, targetProjectName);
                    result.put("modelCount", modelCount);
                }

                // 导入数据CSV
                if (!dataCsvMap.isEmpty()) {
                    dataCount = importDataCsv(dataCsvMap, dataArchiveMap, targetProjectName);
                    result.put("dataCount", dataCount);
                }

                // 导入仿真档案及执行记录
                if (!simulationArchiveMap.isEmpty()) {
                    simulationCount = importSimulationArchives(simulationArchiveMap, simulationExecutionMap, simulationTaskFilesMap, targetProjectName);
                    result.put("simulationCount", simulationCount);
                }
            }

            log.info("项目导入完成: 算法={}, 模型={}, 数据={}, 仿真={}", algorithmCount, modelCount, dataCount, simulationCount);
            result.put("success", true);
            result.put("message", "项目导入成功");

        } finally {
            Files.deleteIfExists(tempZipPath);
        }

        return result;
    }

    /**
     * 创建或验证项目实体
     */
    private int importProjectEntity(ProjectEntity projectEntity, String targetProjectName) throws Exception {
        ProjectEntity existing = projectService.findByName(targetProjectName);
        if (existing == null) {
            // 创建新项目
            projectEntity.setName(targetProjectName);
            projectEntity.setOwner(AuthUtil.getCurrentUsername());
            projectEntity.setAlgorithms("");
            projectEntity.setModels("");
            projectEntity.setDatas("");
            projectService.createProject(projectEntity);
            log.info("已创建项目: {}", targetProjectName);
            return 1;
        } else {
            log.info("项目已存在: {}", targetProjectName);
            return 0;
        }
    }

    /**
     * 导入算法文件和元数据
     */
    private int importAlgorithms(Map<String, byte[]> metaMap, Map<String, byte[]> fileMap, String projectName) throws Exception {
        int count = 0;

        for (Map.Entry<String, byte[]> metaEntry : metaMap.entrySet()) {
            try {
                AlgorithmMetaEntity meta = objectMapper.readValue(metaEntry.getValue(), AlgorithmMetaEntity.class);
                String name = meta.getName();
                String version = meta.getVersion();
                String fileName = meta.getFileName();

                // 检查是否已存在
                try {
                    AlgorithmMetaEntity existing = algorithmFileService.queryMeta(name, version);
                    if (existing != null) {
                        log.warn("算法已存在，跳过: {} v{}", name, version);
                        continue;
                    }
                } catch (Exception e) {
                    // 查询失败，继续导入
                }

                // 查找对应的二进制文件
                byte[] fileData = null;
                for (Map.Entry<String, byte[]> fileEntry : fileMap.entrySet()) {
                    String fileEntryName = fileEntry.getKey();
                    if (fileEntryName.endsWith("/" + fileName) || fileEntryName.endsWith("\\" + fileName)) {
                        fileData = fileEntry.getValue();
                        break;
                    }
                }

                if (fileData == null) {
                    log.error("算法 {} v{} 的二进制文件未找到: {}", name, version, fileName);
                    continue;
                }

                // 写入IginX（分块存储）
                String storagePath = buildAlgorithmStoragePath(projectName, name, version);
                int totalChunks = (int) Math.ceil((double) fileData.length / CHUNK_SIZE);
                List<Point> points = new ArrayList<>();

                for (int i = 0; i < totalChunks; i++) {
                    int start = i * CHUNK_SIZE;
                    int end = Math.min(fileData.length, start + CHUNK_SIZE);
                    byte[] chunk = Arrays.copyOfRange(fileData, start, end);

                    Point point = Point.builder()
                            .measurement(storagePath)
                            .key(i)
                            .binaryValue(chunk)
                            .build();
                    points.add(point);
                }

                iginxClient.getWriteClient().writePoints(points);

                // 保存元数据（更新项目名称为目标项目）
                meta.setProjectName(projectName);
                meta.setStoragePath(storagePath);
                meta.setChunkCount(totalChunks);
                meta.setFileSize((long) fileData.length);
                meta.setAuthor(AuthUtil.getCurrentUsername());
                algorithmFileService.saveAlgorithmMetadata(meta);

                // 添加到项目
                projectService.addToProject(projectName, storagePath, "algorithms");

                count++;
                log.info("已导入算法: {} v{}", name, version);
            } catch (Exception e) {
                log.error("导入算法失败: {}", metaEntry.getKey(), e);
            }
        }
        return count;
    }

    /**
     * 导入模型文件和元数据
     */
    private int importModels(Map<String, byte[]> metaMap, Map<String, byte[]> fileMap, String projectName) throws Exception {
        int count = 0;

        for (Map.Entry<String, byte[]> metaEntry : metaMap.entrySet()) {
            try {
                ModelMetaEntity meta = objectMapper.readValue(metaEntry.getValue(), ModelMetaEntity.class);
                String name = meta.getName();
                String version = meta.getVersion();
                String fileName = meta.getFileName();

                // 检查是否已存在
                try {
                    ModelMetaEntity existing = modelFileService.queryMeta(name, version);
                    if (existing != null) {
                        log.warn("模型已存在，跳过: {} v{}", name, version);
                        continue;
                    }
                } catch (Exception e) {
                    // 查询失败，继续导入
                }

                // 查找对应的二进制文件
                byte[] fileData = null;
                for (Map.Entry<String, byte[]> fileEntry : fileMap.entrySet()) {
                    String fileEntryName = fileEntry.getKey();
                    if (fileEntryName.endsWith("/" + fileName) || fileEntryName.endsWith("\\" + fileName)) {
                        fileData = fileEntry.getValue();
                        break;
                    }
                }

                if (fileData == null) {
                    log.error("模型 {} v{} 的二进制文件未找到: {}", name, version, fileName);
                    continue;
                }

                // 写入IginX（分块存储）
                String storagePath = buildModelStoragePath(projectName, name, version);
                int totalChunks = (int) Math.ceil((double) fileData.length / CHUNK_SIZE);
                List<Point> points = new ArrayList<>();

                for (int i = 0; i < totalChunks; i++) {
                    int start = i * CHUNK_SIZE;
                    int end = Math.min(fileData.length, start + CHUNK_SIZE);
                    byte[] chunk = Arrays.copyOfRange(fileData, start, end);

                    Point point = Point.builder()
                            .measurement(storagePath)
                            .key(i)
                            .binaryValue(chunk)
                            .build();
                    points.add(point);
                }

                iginxClient.getWriteClient().writePoints(points);

                // 保存元数据
                meta.setProjectName(projectName);
                meta.setStoragePath(storagePath);
                meta.setChunkCount(totalChunks);
                meta.setFileSize((long) fileData.length);
                meta.setAuthor(AuthUtil.getCurrentUsername());
                modelFileService.saveModelMetadata(meta);

                // 添加到项目
                projectService.addToProject(projectName, storagePath, "models");

                count++;
                log.info("已导入模型: {} v{}", name, version);
            } catch (Exception e) {
                log.error("导入模型失败: {}", metaEntry.getKey(), e);
            }
        }
        return count;
    }

    /**
     * 导入数据CSV文件
     */
    private int importDataCsv(Map<String, byte[]> csvMap, Map<String, byte[]> archiveMap, String projectName) throws Exception {
        int count = 0;

        for (Map.Entry<String, byte[]> csvEntry : csvMap.entrySet()) {
            String entryName = csvEntry.getKey();
            byte[] csvData = csvEntry.getValue();

            try {
                // 从文件名还原数据路径: data/project1_device1.csv -> project1.device1
                String csvFileName = entryName.substring(entryName.lastIndexOf('/') + 1);
                String dataPath = csvFileName.replace(".csv", "").replace("_", ".");

                // 保存CSV到临时文件
                Path tempCsvPath = Files.createTempFile("import_data_", ".csv");
                try {
                    Files.write(tempCsvPath, csvData);

                    // 使用DataTableService的导入方法
                    String uploadedFileName = System.currentTimeMillis() + ".csv";
                    dataTableService.importCsvFile(
                            tempCsvPath,
                            dataPath,
                            uploadedFileName,
                            null,
                            AuthUtil.getCurrentUsername()
                    );

                    // 添加到项目
                    projectService.addToProject(projectName, dataPath, "datas");

                    // 导入数据档案元数据（如果有）
                    String archiveKey = entryName.replace(".csv", "_archive.json");
                    byte[] archiveData = archiveMap.get(archiveKey);
                    if (archiveData != null) {
                        try {
                            DataArchiveEntity archive = objectMapper.readValue(archiveData, DataArchiveEntity.class);
                            archive.setProjectName(projectName);
                            archive.setOwner(AuthUtil.getCurrentUsername());
                            dataArchiveService.saveArchive(archive);
                        } catch (Exception e) {
                            log.warn("导入数据档案元数据失败: {}", archiveKey, e);
                        }
                    }

                    count++;
                    log.info("已导入数据: {} ({} bytes)", dataPath, csvData.length);
                } finally {
                    Files.deleteIfExists(tempCsvPath);
                }
            } catch (Exception e) {
                log.error("导入数据失败: {}", entryName, e);
            }
        }
        return count;
    }

    /**
     * 导入仿真档案及执行记录
     */
    private int importSimulationArchives(Map<String, byte[]> archiveMap, Map<String, byte[]> executionMap, Map<String, byte[]> taskFilesMap, String projectName) throws Exception {
        int count = 0;

        for (Map.Entry<String, byte[]> archiveEntry : archiveMap.entrySet()) {
            try {
                SimulationArchiveEntity archive = objectMapper.readValue(archiveEntry.getValue(), SimulationArchiveEntity.class);

                // 更新项目名称为目标项目
                archive.setProjectName(projectName);
                archive.setOwner(AuthUtil.getCurrentUsername());
                // 重置运行状态
                archive.setIsRunning(false);

                // 保存仿真档案
                simulationArchiveService.saveArchive(archive);

                // 查找并导入该档案的执行记录
                String archivePrefix = archiveEntry.getKey().replace("/archive.json", "");
                for (Map.Entry<String, byte[]> execEntry : executionMap.entrySet()) {
                    if (execEntry.getKey().startsWith(archivePrefix + "/executions/")) {
                        try {
                            SimulationExecutionEntity execution = objectMapper.readValue(execEntry.getValue(), SimulationExecutionEntity.class);
                            // 更新档案ID和名称
                            execution.setArchiveId(archive.getCreateTime());
                            execution.setArchiveName(archive.getName());
                            // 保存执行记录
                            simulationExecutionService.saveExecution(execution);

                            // 恢复任务目录文件
                            String execTimestamp = execEntry.getKey().substring(execEntry.getKey().lastIndexOf('/') + 1).replace(".json", "");
                            String taskFilesPrefix = archivePrefix + "/executions/" + execTimestamp + "_files";
                            Path taskDir = java.nio.file.Paths.get("project", projectName, "job", "simulation", execTimestamp);
                            if (!java.nio.file.Files.exists(taskDir)) {
                                java.nio.file.Files.createDirectories(taskDir);
                            }
                            for (Map.Entry<String, byte[]> fileEntry : taskFilesMap.entrySet()) {
                                if (fileEntry.getKey().startsWith(taskFilesPrefix)) {
                                    String relativePath = fileEntry.getKey().substring(taskFilesPrefix.length() + 1);
                                    Path targetFile = taskDir.resolve(relativePath.replace("/", java.io.File.separator));
                                    java.nio.file.Files.createDirectories(targetFile.getParent());
                                    java.nio.file.Files.write(targetFile, fileEntry.getValue());
                                }
                            }
                        } catch (Exception e) {
                            log.warn("导入仿真执行记录失败: {}", execEntry.getKey(), e);
                        }
                    }
                }

                count++;
                log.info("已导入仿真档案: {}", archive.getName());
            } catch (Exception e) {
                log.error("导入仿真档案失败: {}", archiveEntry.getKey(), e);
            }
        }
        return count;
    }

    /**
     * 构建算法存储路径（与AlgorithmFileService.buildStoragePath一致）
     */
    private String buildAlgorithmStoragePath(String projectName, String name, String version) {
        String safeVersion = version.replace('.', '_');
        return String.format("algorithms_system.%s.%s.%s", projectName, name, safeVersion);
    }

    /**
     * 构建模型存储路径（与ModelFileService.buildStoragePath一致）
     */
    private String buildModelStoragePath(String projectName, String name, String version) {
        String safeVersion = version.replace('.', '_');
        return String.format("models_system.%s.%s.%s", projectName, name, safeVersion);
    }

    /**
     * 读取ZIP条目内容
     */
    private byte[] readZipEntry(ZipInputStream zis) throws IOException {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        byte[] buffer = new byte[4096];
        int len;
        while ((len = zis.read(buffer)) > 0) {
            baos.write(buffer, 0, len);
        }
        return baos.toByteArray();
    }
}
