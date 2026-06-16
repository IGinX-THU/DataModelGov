package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsinghua.auth.service.DataPermissionService;
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

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
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
    private DataPermissionService dataPermissionService;

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

    private static final int CHUNK_SIZE = 65536; // 64KB，与上传一致

    /**
     * 从ZIP压缩包导入项目资源
     *
     * @param file       上传的ZIP文件
     * @param projectName 目标项目名称（如果为空则使用导出时的项目名）
     * @return 导入结果摘要
     */
    public Map<String, Object> importProject(MultipartFile file, String projectName) throws Exception {
        return importProject(file, projectName, true);
    }

    public Map<String, Object> importProjectResource(MultipartFile file, String projectName) throws Exception {
        return importProjectResource(file, projectName, null);
    }

    public Map<String, Object> importProjectResource(MultipartFile file, String projectName, String resourceType) throws Exception {
        if (!StringUtils.hasText(projectName)) {
            throw new IllegalArgumentException("目标项目不能为空");
        }
        return importProject(file, projectName, false, resourceType);
    }

    private Map<String, Object> importProject(MultipartFile file, String projectName, boolean importProjectMetadata) throws Exception {
        return importProject(file, projectName, importProjectMetadata, null);
    }

    private Map<String, Object> importProject(MultipartFile file, String projectName, boolean importProjectMetadata, String expectedResourceType) throws Exception {
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("导入文件不能为空");
        }

        // 检查文件大小
        long fileSize = file.getSize();
        if (fileSize == 0) {
            throw new IllegalArgumentException("导入文件大小为0，文件可能未正确上传");
        }
        log.info("开始导入项目，文件大小: {} bytes", fileSize);

        Map<String, Object> result = new LinkedHashMap<>();
        int algorithmCount = 0;
        int modelCount = 0;
        int dataCount = 0;
        int simulationCount = 0;
        List<String> skippedAlgorithms = new ArrayList<>();
        List<String> skippedModels = new ArrayList<>();
        List<String> skippedData = new ArrayList<>();
        List<String> skippedSimulations = new ArrayList<>();

        // 先将ZIP保存到临时文件
        Path tempZipPath = Files.createTempFile("project_import_", ".zip");
        try {
            // 使用InputStream复制文件内容到临时文件
            try (InputStream is = file.getInputStream();
                 java.io.FileOutputStream fos = new java.io.FileOutputStream(tempZipPath.toFile())) {
                byte[] buffer = new byte[8192];
                int bytesRead;
                while ((bytesRead = is.read(buffer)) != -1) {
                    fos.write(buffer, 0, bytesRead);
                }
                fos.getFD().sync();
            }

            // 验证临时文件大小是否匹配
            long tempFileSize = Files.size(tempZipPath);
            if (tempFileSize != fileSize) {
                throw new IllegalArgumentException(String.format("文件传输不完整：期望 %d bytes，实际 %d bytes", fileSize, tempFileSize));
            }
            log.info("临时文件已保存并同步到磁盘，大小: {} bytes", tempFileSize);

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
                    } else if (entryName.startsWith("data/") && entryName.endsWith("/archive.json")) {
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
                String manifestResourceType = (String) manifest.get("resourceType");
                if (expectedResourceType != null && !expectedResourceType.isEmpty()) {
                    if (manifestResourceType == null || !manifestResourceType.equals(expectedResourceType)) {
                        throw new IllegalArgumentException("资源包类型不匹配：期望 " + expectedResourceType + "，实际 " + (manifestResourceType != null ? manifestResourceType : "未指定"));
                    }
                }
                String targetProjectName = StringUtils.hasText(projectName) ? projectName : originalProjectName;

                result.put("originalProjectName", originalProjectName);
                result.put("targetProjectName", targetProjectName);

                // 设置项目上下文
                ProjectContext.setCurrentProject(targetProjectName);

                // 解析并创建/验证项目
                if (importProjectMetadata && projectJson != null) {
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
                    algorithmCount = importAlgorithms(algorithmMetaMap, algorithmFileMap, originalProjectName, targetProjectName, skippedAlgorithms);
                    result.put("algorithmCount", algorithmCount);
                }

                // 导入模型
                if (!modelMetaMap.isEmpty()) {
                    modelCount = importModels(modelMetaMap, modelFileMap, originalProjectName, targetProjectName, skippedModels);
                    result.put("modelCount", modelCount);
                }

                // 导入数据CSV
                if (!dataCsvMap.isEmpty()) {
                    log.info("开始导入数据CSV，共 {} 个文件，数据档案共 {} 个", dataCsvMap.size(), dataArchiveMap.size());
                    dataCount = importDataCsv(dataCsvMap, dataArchiveMap, originalProjectName, targetProjectName, skippedData);
                    result.put("dataCount", dataCount);
                }

                // 导入仿真档案及执行记录
                if (!simulationArchiveMap.isEmpty()) {
                    simulationCount = importSimulationArchives(simulationArchiveMap, simulationExecutionMap, simulationTaskFilesMap, originalProjectName, targetProjectName, skippedSimulations);
                    result.put("simulationCount", simulationCount);
                }
            }

            log.info("项目导入完成: 算法={}, 模型={}, 数据={}, 仿真={}", algorithmCount, modelCount, dataCount, simulationCount);
            result.put("success", true);
            result.put("message", "项目导入成功");
            
            // 添加跳过的资源信息
            if (!skippedAlgorithms.isEmpty()) {
                result.put("skippedAlgorithms", skippedAlgorithms);
            }
            if (!skippedModels.isEmpty()) {
                result.put("skippedModels", skippedModels);
            }
            if (!skippedData.isEmpty()) {
                result.put("skippedData", skippedData);
            }
            if (!skippedSimulations.isEmpty()) {
                result.put("skippedSimulations", skippedSimulations);
            }

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
            throw new IllegalArgumentException("项目已存在: " + targetProjectName);
        }
    }

    /**
     * 导入算法文件和元数据
     */
    private int importAlgorithms(Map<String, byte[]> metaMap, Map<String, byte[]> fileMap, String originalProjectName, String projectName, List<String> skippedList) throws Exception {
        int count = 0;

        for (Map.Entry<String, byte[]> metaEntry : metaMap.entrySet()) {
            try {
                AlgorithmMetaEntity meta = objectMapper.readValue(metaEntry.getValue(), AlgorithmMetaEntity.class);
                String name = meta.getName();
                String version = meta.getVersion();
                String fileName = meta.getFileName();

                // 检查是否已存在相同算法，防止重复导入
                AlgorithmMetaEntity existing = algorithmFileService.queryMeta(name, version, projectName);
                if (existing != null) {
                    log.warn("算法 {} v{} 已存在于项目 {} 中，跳过导入", name, version, projectName);
                    skippedList.add(name + " " + version);
                    continue;
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

                // 分配数据权限
                dataPermissionService.saveTablePrefix(storagePath, false, AuthUtil.getCurrentUsername());

                // 保存元数据（更新项目名称为目标项目）
                rewriteAlgorithmMetaProject(meta, originalProjectName, projectName);
                meta.setProjectName(projectName);
                meta.setStoragePath(storagePath);
                meta.setChunkCount(totalChunks);
                meta.setFileSize((long) fileData.length);
                meta.setAuthor(AuthUtil.getCurrentUsername());
                meta.setTimestamp(nextImportTimestamp());
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
    private int importModels(Map<String, byte[]> metaMap, Map<String, byte[]> fileMap, String originalProjectName, String projectName, List<String> skippedList) throws Exception {
        int count = 0;

        for (Map.Entry<String, byte[]> metaEntry : metaMap.entrySet()) {
            try {
                ModelMetaEntity meta = objectMapper.readValue(metaEntry.getValue(), ModelMetaEntity.class);
                String name = meta.getName();
                String version = meta.getVersion();
                String fileName = meta.getFileName();

                // 检查是否已存在相同模型，防止重复导入
                ModelMetaEntity existing = modelFileService.queryMeta(name, version, projectName);
                if (existing != null) {
                    log.warn("模型 {} v{} 已存在于项目 {} 中，跳过导入", name, version, projectName);
                    skippedList.add(name + " " + version);
                    continue;
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

                // 分配数据权限
                dataPermissionService.saveTablePrefix(storagePath, false, AuthUtil.getCurrentUsername());

                // 保存元数据
                rewriteModelMetaProject(meta, originalProjectName, projectName);
                meta.setProjectName(projectName);
                meta.setStoragePath(storagePath);
                meta.setChunkCount(totalChunks);
                meta.setFileSize((long) fileData.length);
                meta.setAuthor(AuthUtil.getCurrentUsername());
                meta.setTimestamp(nextImportTimestamp());
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
    private int importDataCsv(Map<String, byte[]> csvMap, Map<String, byte[]> archiveMap, String originalProjectName, String projectName, List<String> skippedList) throws Exception {
        int count = 0;

        for (Map.Entry<String, byte[]> csvEntry : csvMap.entrySet()) {
            String entryName = csvEntry.getKey();
            byte[] csvData = csvEntry.getValue();

            try {
                // 从文件名还原数据路径: data/project1_device1.csv -> project1.device1
                String csvFileName = entryName.substring(entryName.lastIndexOf('/') + 1);
                String dataPath = csvFileName.replace(".csv", "").replace("_", ".");
                int firstDotIndex = dataPath.indexOf('.');
                if (firstDotIndex >= 0) {
                    dataPath = projectName + dataPath.substring(firstDotIndex);
                } else {
                    dataPath = projectName + "." + dataPath;
                }

                // 检查数据档案是否已存在，防止重复导入
                List<DataArchiveEntity> existingArchives = dataArchiveService.queryArchives(
                    dataPath, null, projectName, null, 1, 1);
                if (existingArchives != null && !existingArchives.isEmpty()) {
                    log.warn("数据路径 {} 的档案已存在于项目 {} 中，跳过导入", dataPath, projectName);
                    skippedList.add(dataPath);
                    continue;
                }

                // 保存CSV到临时文件
                Path tempCsvPath = Files.createTempFile("import_data_", ".csv");
                try {
                    // 去除UTF-8 BOM (EF BB BF)
                    byte[] csvDataWithoutBom = csvData;
                    if (csvData.length >= 3 && csvData[0] == (byte) 0xEF && csvData[1] == (byte) 0xBB && csvData[2] == (byte) 0xBF) {
                        csvDataWithoutBom = new byte[csvData.length - 3];
                        System.arraycopy(csvData, 3, csvDataWithoutBom, 0, csvData.length - 3);
                    }

                    // 处理CSV表头：去掉表前缀只保留字段名
                    String csvContent = new String(csvDataWithoutBom, StandardCharsets.UTF_8);
                    String[] lines = csvContent.split("\n");
                    if (lines.length > 0) {
                        String header = lines[0];
                        String[] columns = header.split(",");
                        StringBuilder newHeader = new StringBuilder();
                        for (int i = 0; i < columns.length; i++) {
                            String column = columns[i].trim();
                            // 去掉表前缀，只保留字段名（最后一个点之后的部分）
                            int lastDotIndex = column.lastIndexOf('.');
                            if (lastDotIndex > 0) {
                                column = column.substring(lastDotIndex + 1);
                            }
                            if (i > 0) {
                                newHeader.append(",");
                            }
                            newHeader.append(column);
                        }
                        lines[0] = newHeader.toString();
                        csvContent = String.join("\n", lines);
                    }
                    Files.write(tempCsvPath, csvContent.getBytes(StandardCharsets.UTF_8));

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
                    String archiveKey = entryName.replace(".csv", "/archive.json");
                    byte[] archiveData = archiveMap.get(archiveKey);
                    if (archiveData == null) {
                        archiveData = findDataArchiveByPath(archiveMap, dataPath, originalProjectName, projectName);
                    }
                    if (archiveData != null) {
                        try {
                            DataArchiveEntity archive = objectMapper.readValue(archiveData, DataArchiveEntity.class);
                            long archiveTimestamp = nextImportTimestamp();
                            archive.setId(archiveTimestamp);
                            archive.setName(dataPath);
                            archive.setProjectName(projectName);
                            archive.setOwner(AuthUtil.getCurrentUsername());
                            archive.setCreateTime(archiveTimestamp);
                            archive.setConfig(rewriteProjectReferences(archive.getConfig(), originalProjectName, projectName));
                            dataArchiveService.saveArchive(archive);
                            log.info("已导入数据档案: {}", archive.getName());
                        } catch (Exception e) {
                            log.warn("导入数据档案元数据失败: {}", archiveKey, e);
                        }
                    } else {
                        log.warn("未找到数据档案: {}", archiveKey);
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
    private int importSimulationArchives(Map<String, byte[]> archiveMap, Map<String, byte[]> executionMap, Map<String, byte[]> taskFilesMap, String originalProjectName, String projectName, List<String> skippedList) throws Exception {
        int count = 0;

        for (Map.Entry<String, byte[]> archiveEntry : archiveMap.entrySet()) {
            try {
                SimulationArchiveEntity archive = objectMapper.readValue(archiveEntry.getValue(), SimulationArchiveEntity.class);

                // 检查是否已存在相同名称的仿真档案，防止重复导入
                List<SimulationArchiveEntity> existingArchives = simulationArchiveService.queryArchives(
                    archive.getName(), projectName, null, null, 1, 1);
                if (existingArchives != null && !existingArchives.isEmpty()) {
                    log.warn("仿真档案 {} 已存在于项目 {} 中，跳过导入", archive.getName(), projectName);
                    skippedList.add(archive.getName());
                    continue;
                }

                // 更新项目名称为目标项目
                long archiveCreateTime = nextImportTimestamp();
                archive.setProjectName(projectName);
                archive.setOwner(AuthUtil.getCurrentUsername());
                archive.setCreateTime(archiveCreateTime);
                archive.setUpdateTime(archiveCreateTime);
                archive.setGraphJson(rewriteProjectReferences(archive.getGraphJson(), originalProjectName, projectName));
                archive.setOutputApiConfig(rewriteProjectReferences(archive.getOutputApiConfig(), originalProjectName, projectName));
                archive.setLastExecutionTime(null);
                archive.setExecutionCount(0L);
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
                            long executionTimestamp = nextImportTimestamp();
                            execution.setTimestamp(executionTimestamp);
                            // 保持原始的开始时间和结束时间
                            execution.setArchiveId(archiveCreateTime);
                            execution.setArchiveName(archive.getName());
                            execution.setInputMeasurements(rewriteProjectReferences(execution.getInputMeasurements(), originalProjectName, projectName));
                            execution.setOutputMeasurements(rewriteProjectReferences(execution.getOutputMeasurements(), originalProjectName, projectName));
                            execution.setOutputTable(rewriteProjectReferences(execution.getOutputTable(), originalProjectName, projectName));

                            // 修复result字段双重序列化问题：如果result是字符串，解析为JSON对象
                            Object result = execution.getResult();
                            if (result instanceof String) {
                                try {
                                    execution.setResult(objectMapper.readValue((String) result, Object.class));
                                    log.info("已修复result字段双重序列化问题");
                                } catch (Exception e) {
                                    log.warn("解析result字段失败，保持原样", e);
                                }
                            }

                            // 保存执行记录
                            simulationExecutionService.saveExecution(execution);

                            // 恢复任务目录文件
                            String execTimestamp = String.valueOf(executionTimestamp);
                            String taskFilesPrefix = archivePrefix + "/executions/" + execTimestamp + "_files";
                            Path taskDir = java.nio.file.Paths.get("project", projectName, "job", "simulation", execTimestamp);
                            if (!java.nio.file.Files.exists(taskDir)) {
                                java.nio.file.Files.createDirectories(taskDir);
                            }
                            for (Map.Entry<String, byte[]> fileEntry : taskFilesMap.entrySet()) {
                                if (fileEntry.getKey().startsWith(taskFilesPrefix)) {
                                    String relativePath = fileEntry.getKey().substring(taskFilesPrefix.length() + 1);
                                    // 保持原有的目录结构（包括nodeId子目录）
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

    private long nextImportTimestamp() {
        try {
            Thread.sleep(1);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return System.currentTimeMillis();
    }

    private byte[] findDataArchiveByPath(Map<String, byte[]> archiveMap, String targetDataPath, String originalProjectName, String targetProjectName) {
        String originalDataPath = targetDataPath;
        if (originalProjectName != null && targetProjectName != null && targetDataPath.startsWith(targetProjectName + ".")) {
            originalDataPath = originalProjectName + targetDataPath.substring(targetProjectName.length());
        }
        for (Map.Entry<String, byte[]> entry : archiveMap.entrySet()) {
            try {
                DataArchiveEntity archive = objectMapper.readValue(entry.getValue(), DataArchiveEntity.class);
                String rewrittenName = rewriteProjectReferences(archive.getName(), originalProjectName, targetProjectName);
                String rewrittenConfig = rewriteProjectReferences(archive.getConfig(), originalProjectName, targetProjectName);
                if (targetDataPath.equals(rewrittenName)
                        || originalDataPath.equals(archive.getName())
                        || (rewrittenConfig != null && rewrittenConfig.contains(targetDataPath))
                        || (archive.getConfig() != null && archive.getConfig().contains(originalDataPath))) {
                    return entry.getValue();
                }
            } catch (Exception e) {
                log.warn("解析数据档案用于匹配失败: {}", entry.getKey(), e);
            }
        }
        return null;
    }

    private String rewriteProjectReferences(String value, String originalProjectName, String targetProjectName) {
        if (value == null || originalProjectName == null || targetProjectName == null || originalProjectName.equals(targetProjectName)) {
            return value;
        }
        return value
                .replace("algorithms_system." + originalProjectName + ".", "algorithms_system." + targetProjectName + ".")
                .replace("models_system." + originalProjectName + ".", "models_system." + targetProjectName + ".")
                .replace("\"" + originalProjectName + ".", "\"" + targetProjectName + ".")
                .replace("'" + originalProjectName + ".", "'" + targetProjectName + ".")
                .replace(originalProjectName + ".", targetProjectName + ".");
    }

    private void rewriteAlgorithmMetaProject(AlgorithmMetaEntity meta, String originalProjectName, String targetProjectName) {
        meta.setTableName(rewriteProjectReferences(meta.getTableName(), originalProjectName, targetProjectName));
        meta.setInputData(rewriteProjectReferences(meta.getInputData(), originalProjectName, targetProjectName));
        meta.setCalledModels(rewriteProjectReferences(meta.getCalledModels(), originalProjectName, targetProjectName));
        meta.setInputsBind(rewriteProjectReferences(meta.getInputsBind(), originalProjectName, targetProjectName));
        meta.setOutputsBind(rewriteProjectReferences(meta.getOutputsBind(), originalProjectName, targetProjectName));
        meta.setOutputTable(rewriteProjectReferences(meta.getOutputTable(), originalProjectName, targetProjectName));
    }

    private void rewriteModelMetaProject(ModelMetaEntity meta, String originalProjectName, String targetProjectName) {
        meta.setInputs(rewriteProjectReferences(meta.getInputs(), originalProjectName, targetProjectName));
        meta.setOutputs(rewriteProjectReferences(meta.getOutputs(), originalProjectName, targetProjectName));
        meta.setApis(rewriteProjectReferences(meta.getApis(), originalProjectName, targetProjectName));
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
