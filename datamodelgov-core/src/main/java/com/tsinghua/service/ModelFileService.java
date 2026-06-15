package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.QueryDataSet;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.query.SimpleQuery;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import cn.edu.tsinghua.iginx.thrift.DataType;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.entity.ModelMetaEntity;
import com.tsinghua.dto.UploadResult;
import com.tsinghua.util.ConvertUtil;
import com.tsinghua.util.ProjectContext;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import java.io.ByteArrayOutputStream;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
public class ModelFileService {

    private static final int CHUNK_SIZE = 65536; // 64KB
    private static final String STORAGE_PREFIX_BASE = "models_system";
    private static final String META_PREFIX = "relational_system.models_meta";

    @Autowired
    private DataPermissionService dataPermissionService;

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private ProjectService projectService;

    /**
     * 上传模型文件
     * 直接将二进制分块数据写入 IGinX，无需 Base64 编码
     */
    public UploadResult uploadModel(MultipartFile file, String name, String version) throws Exception {
        String projectName = ProjectContext.getCurrentProject("unknown");
        String storagePath = buildStoragePath(projectName, name, version);

        if (dataPermissionService.existTablePrefix(storagePath)) {
            throw new IllegalArgumentException("模型资产已存在");
        }

        byte[] fileBytes = file.getBytes();
        int totalChunks = (int) Math.ceil((double) fileBytes.length / CHUNK_SIZE);

        // 准备数据点列表
        List<Point> points = new ArrayList<>();

        for (int i = 0; i < totalChunks; i++) {
            int start = i * CHUNK_SIZE;
            int end = Math.min(fileBytes.length, start + CHUNK_SIZE);
            byte[] chunk = Arrays.copyOfRange(fileBytes, start, end);

            // 构建数据点 - 直接存储二进制数据
            Point point = Point.builder()
                    .measurement(storagePath)    // 存储路径
                    .key(i)         // 块序号作为时间戳
                    .binaryValue(chunk)          // 直接存储二进制块 (Java 17+ 兼容)
                    .build();

            points.add(point);

            // 进度提示
            if ((i + 1) % 100 == 0 || i == totalChunks - 1) {
                log.info("模型 {} 版本 {}: 处理进度 {}/{}", name, version, i + 1, totalChunks);
            }
        }

        // 批量写入数据点
        log.info("开始写入模型文件: {} 版本 {}, 共 {} 个数据块...", name, version, totalChunks);
        iginxClient.getWriteClient().writePoints(points);

        // 计算文件校验信息
        String fileMd5 = calculateMD5(fileBytes);

        log.info("模型文件上传成功。名称: {}, 版本: {}, 块数: {}, MD5: {}",
                name, version, totalChunks, fileMd5);

        // 2. 保存模型元数据 (行式对齐存储)
        ModelMetaEntity modelMetaDto = new ModelMetaEntity();
        modelMetaDto.setName(name);
        modelMetaDto.setVersion(version);
        modelMetaDto.setFileName(file.getOriginalFilename());
        modelMetaDto.setFileSize(file.getSize());
        modelMetaDto.setChunkCount(totalChunks);
        modelMetaDto.setStoragePath(storagePath);
        modelMetaDto.setFileMd5(fileMd5);
        modelMetaDto.setProjectName(projectName);
        modelMetaDto.setAuthor(com.tsinghua.auth.util.AuthUtil.getCurrentUsername());
        saveModelMetadata(modelMetaDto);

        dataPermissionService.saveTablePrefix(storagePath);
        log.info("模型文件上传成功。storagePath: {}", storagePath);

        // 添加到项目的models字段
        if (projectName != null && !projectName.isEmpty()) {
            try {
                projectService.addToProject(projectName, storagePath, "models");
            } catch (Exception e) {
                log.error("添加模型路径到项目失败", e);
            }
        }

        return new UploadResult(name, version, file.getOriginalFilename(),
                file.getSize(), totalChunks, storagePath, fileMd5);
    }

    /**
     * 下载模型文件 (优化版)
     * 1. 先查询元数据验证模型信息
     * 2. 按chunkCount精确获取文件块
     * 3. 校验MD5确保文件完整性
     */
    public byte[] downloadModel(String name, String version) throws Exception {
        log.info("开始下载模型: {} v{}", name, version);

        // 1. 先查询元数据验证模型信息
        ModelMetaEntity modelMeta = queryMeta(name, version);
        if (modelMeta == null) {
            throw new Exception("未找到指定的模型元数据: " + name + " v" + version);
        }

        // 验证元数据完整性
        if (modelMeta.getChunkCount() == null || modelMeta.getChunkCount() <= 0) {
            throw new Exception("模型元数据不完整: chunkCount无效");
        }

        if (modelMeta.getFileMd5() == null || modelMeta.getFileMd5().isEmpty()) {
            throw new Exception("模型元数据不完整: fileMd5无效");
        }

        log.info("元数据验证通过 - 文件名: {}, 块数: {}, 存储路径: {}, MD5: {}",
                modelMeta.getFileName(), modelMeta.getChunkCount(), modelMeta.getStoragePath(), modelMeta.getFileMd5());

        // 2. 按chunkCount精确获取文件块
        String storagePath = buildStoragePath(modelMeta.getProjectName(), name, version);
        TreeMap<Integer, byte[]> chunkMap = new TreeMap<>();

        // 构建查询 - 只查询指定数量的块
        SimpleQuery query = SimpleQuery.builder()
                .addMeasurement(storagePath)
                .endKey(Long.MAX_VALUE)
                .build();

        IginXTable table = iginxClient.getQueryClient().query(query);

        if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) {
            throw new Exception("未找到指定的模型文件数据: " + name + " v" + version);
        }

        // 按块序号组织数据
        for (IginXRecord record : table.getRecords()) {
            Long timestamp = record.getKey();
            Map<String, Object> valuesMap = record.getValues();
            Object value = valuesMap.get(storagePath);

            if (value instanceof byte[]) {
                byte[] chunkData = (byte[]) value;
                // 使用时间戳作为块序号（与上传时保持一致）
                int chunkIndex = timestamp.intValue();
                chunkMap.put(chunkIndex, chunkData);
            } else if (value != null) {
                log.warn("路径 {} 的值类型为 {}，尝试转换为字节数组",
                        storagePath, value.getClass().getSimpleName());
                byte[] chunkData = value.toString().getBytes(StandardCharsets.UTF_8);
                int chunkIndex = timestamp.intValue();
                chunkMap.put(chunkIndex, chunkData);
            }
        }

        // 3. 按序合并所有块
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        for (int i = 0; i < modelMeta.getChunkCount(); i++) {
            byte[] chunk = chunkMap.get(i);
            if (chunk == null) {
                log.error("缺少第 {} 个文件块", i);
                throw new Exception("文件数据不完整，缺少第 " + i + " 个文件块");
            }
            baos.write(chunk);
        }

        byte[] fileBytes = baos.toByteArray();

        // 4. 校验MD5确保文件完整性
        String actualMd5 = calculateMD5(fileBytes);
        if (!actualMd5.equals(modelMeta.getFileMd5())) {
            log.error("MD5校验失败! 期望: {}, 实际: {}", modelMeta.getFileMd5(), actualMd5);
            throw new Exception(String.format("文件完整性校验失败! MD5不匹配 - 期望: %s, 实际: %s",
                    modelMeta.getFileMd5(), actualMd5));
        }

        log.info("模型文件下载成功 - 名称: {}, 版本: {}, 文件名: {}, 大小: {} bytes, 块数: {}, MD5: {}",
                name, version, modelMeta.getFileName(), fileBytes.length, chunkMap.size(), actualMd5);

        return fileBytes;
    }

    /**
     * 提取模型文件（返回文件列表给前端）
     */
    public List<Map<String, Object>> extractModelFile(String modelName, String modelVersion, Path taskDir) throws Exception {
        if (!StringUtils.hasText(modelName) || !StringUtils.hasText(modelVersion)) {
            throw new RuntimeException("模型名称或版本为空");
        }

        log.info("开始下载模型: {} 版本 {}", modelName, modelVersion);

        // 获取模型元数据以获取正确的文件名
        ModelMetaEntity modelMeta = queryMeta(modelName, modelVersion);
        if (modelMeta == null) {
            throw new RuntimeException("未找到模型元数据: " + modelName + " 版本 " + modelVersion);
        }

        byte[] modelData = downloadModel(modelName, modelVersion);
        String fileName = modelMeta.getFileName();
        if (fileName == null || fileName.trim().isEmpty()) {
            throw new RuntimeException("模型文件名为空: " + modelName + " 版本 " + modelVersion);
        }

        Path modelFile = taskDir.resolve(fileName);
        Files.write(modelFile, modelData);
        log.info("模型文件已下载到: {}", modelFile);

        // 如果是压缩包，解压到任务目录
        if (fileName.toLowerCase().endsWith(".zip") || fileName.toLowerCase().endsWith(".tar") ||
                fileName.toLowerCase().endsWith(".tar.gz") || fileName.toLowerCase().endsWith(".tgz")) {
            extractArchive(modelFile, taskDir);
            log.info("压缩包已解压到: {}", taskDir);
        }

        // 扫描任务目录，获取所有文件信息
        List<Map<String, Object>> fileList = new ArrayList<>();
        Files.walk(taskDir)
                .filter(Files::isRegularFile)
                .forEach(file -> {
                    try {
                        Map<String, Object> fileInfo = new HashMap<>();
                        fileInfo.put("name", file.getFileName().toString());
                        fileInfo.put("path", taskDir.relativize(file).toString());
                        fileInfo.put("size", Files.size(file));
                        fileInfo.put("lastModified", Files.getLastModifiedTime(file).toString());
                        fileInfo.put("category", getFileCategory(file.getFileName().toString()));
                        
                        // 如果是文本文件，读取内容（限制大小）
                        if (isTextFile(file) && Files.size(file) < 1024 * 1024) { // 小于1MB
                            String content = String.join("\n", Files.readAllLines(file, StandardCharsets.UTF_8));
                            fileInfo.put("content", content);
                        }
                        
                        fileList.add(fileInfo);
                        log.debug("找到文件: {} ({} bytes)", file.getFileName(), Files.size(file));
                    } catch (Exception e) {
                        log.warn("处理文件时出错: {}", file.getFileName(), e);
                    }
                });

        log.info("提取完成，共找到 {} 个文件", fileList.size());
        return fileList;
    }
    
    /**
     * 判断是否为文本文件
     */
    private boolean isTextFile(Path file) {
        String fileName = file.getFileName().toString().toLowerCase();
        // 脚本类
        if (fileName.endsWith(".py") || fileName.endsWith(".m")) return true;
        // C/C++源码
        if (fileName.endsWith(".cpp") || fileName.endsWith(".c") ||
            fileName.endsWith(".h") || fileName.endsWith(".hpp") ||
            fileName.endsWith(".cc") || fileName.endsWith(".cxx")) return true;
        // 通用文本
        if (fileName.endsWith(".java") || fileName.endsWith(".js") ||
            fileName.endsWith(".ts") || fileName.endsWith(".txt") ||
            fileName.endsWith(".md") || fileName.endsWith(".json") ||
            fileName.endsWith(".yaml") || fileName.endsWith(".yml") ||
            fileName.endsWith(".xml") || fileName.endsWith(".ini") ||
            fileName.endsWith(".cfg") || fileName.endsWith(".conf")) return true;
        return false;
    }

    /**
     * 判断文件类型分类
     */
    public String getFileCategory(String fileName) {
        String lower = fileName.toLowerCase();
        // 脚本类
        if (lower.endsWith(".py")) return "script_python";
        if (lower.endsWith(".m")) return "script_matlab";
        // C/C++源码
        if (lower.endsWith(".cpp") || lower.endsWith(".c") ||
            lower.endsWith(".h") || lower.endsWith(".hpp") ||
            lower.endsWith(".cc") || lower.endsWith(".cxx")) return "source_cpp";
        // 二进制类
        if (lower.endsWith(".dll")) return "binary_dll";
        if (lower.endsWith(".so")) return "binary_so";
        if (lower.endsWith(".pyd")) return "binary_pyd";
        // 仿真专有
        if (lower.endsWith(".ame")) return "simulation_amesim";
        if (lower.endsWith(".fmu")) return "simulation_fmu";
        // 压缩包
        if (lower.endsWith(".zip") || lower.endsWith(".tar") ||
            lower.endsWith(".tar.gz") || lower.endsWith(".tgz")) return "archive";
        return "unknown";
    }

    private void extractArchive(Path archiveFile, Path extractDir) {
        try {
            if (archiveFile.toString().toLowerCase().endsWith(".zip")) {
                // 使用Java内置的ZipInputStream解压ZIP文件
                try (java.util.zip.ZipInputStream zis = new java.util.zip.ZipInputStream(Files.newInputStream(archiveFile.toFile().toPath()))) {
                    java.util.zip.ZipEntry entry;
                    while ((entry = zis.getNextEntry()) != null) {
                        Path entryPath = extractDir.resolve(entry.getName());
                        if (entry.isDirectory()) {
                            Files.createDirectories(entryPath);
                        } else {
                            Files.createDirectories(entryPath.getParent());
                            Files.copy(zis, entryPath);
                        }
                        zis.closeEntry();
                    }
                }
            } else if (archiveFile.toString().toLowerCase().endsWith(".tar") ||
                    archiveFile.toString().toLowerCase().endsWith(".tar.gz") ||
                    archiveFile.toString().toLowerCase().endsWith(".tgz")) {
                // 对于tar文件，可以使用系统命令tar
                ProcessBuilder pb = new ProcessBuilder("tar", "-xf", archiveFile.toString(), "-C", extractDir.toString());
                pb.directory(extractDir.toFile());
                Process process = pb.start();
                int exitCode = process.waitFor();
                if (exitCode != 0) {
                    throw new RuntimeException("解压tar文件失败，退出码: " + exitCode);
                }
            }
        } catch (Exception e) {
            log.error("解压文件失败: {}", archiveFile, e);
            throw new RuntimeException("解压文件失败: " + e.getMessage(), e);
        }
    }

    /**
     * 保存模型元数据 (行式对齐存储)
     * 每个字段作为独立的时序序列存储，使用相同的时间戳对齐
     */
    public void saveModelMetadata(ModelMetaEntity modelMetaDto) throws Exception {
        List<Point> metaPoints = new ArrayList<>();
        ModelMetaEntity queryMeta = queryMeta(modelMetaDto.getName(), modelMetaDto.getVersion(), modelMetaDto.getProjectName());
        long timestamp;
        if (modelMetaDto.getTimestamp() != null) {
            timestamp = modelMetaDto.getTimestamp();
        } else if (queryMeta != null && queryMeta.getTimestamp() != null) {
            timestamp = queryMeta.getTimestamp();
        } else {
            timestamp = System.currentTimeMillis();
        }
        String safeVersion = modelMetaDto.getVersion().replace('.', '_');
        String metaBasePath = META_PREFIX;

        // 创建各个字段的数据点
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "name", modelMetaDto.getName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "version", safeVersion, timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "fileName", modelMetaDto.getFileName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "fileSize", modelMetaDto.getFileSize(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "chunkCount", modelMetaDto.getChunkCount(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "storagePath", modelMetaDto.getStoragePath(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "fileMd5", modelMetaDto.getFileMd5(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "author", modelMetaDto.getAuthor(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "scene", modelMetaDto.getScene(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "inputs", modelMetaDto.getInputs(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "outputs", modelMetaDto.getOutputs(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "apis", modelMetaDto.getApis(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "timestamp", timestamp, timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "projectName", modelMetaDto.getProjectName(), timestamp));

        // 批量写入元数据
        iginxClient.getWriteClient().writePoints(metaPoints.stream().filter(Objects::nonNull).collect(Collectors.toList()));
        log.info("模型元数据已保存。名称: {}, 版本: {}, 时间戳: {}", modelMetaDto.getName(), modelMetaDto.getVersion(), timestamp);
    }

    public ModelMetaEntity queryMeta(String name, String version) {
        return queryMeta(name, version, ProjectContext.getCurrentProject(null));
    }

    public ModelMetaEntity queryMeta(String name, String version, String projectName) {
        try {
            String sql;
            if (StringUtils.hasText(projectName)) {
                sql = "select * from %s where name = '%s' and version='%s' and projectName='%s';";
            } else {
                sql = "select * from %s where name = '%s' and version='%s';";
            }
        String metaBasePath = META_PREFIX;
        String safeVersion = version.replace('.', '_');
        // iginxSession.openSession();
        QueryDataSet res = StringUtils.hasText(projectName)
                ? iginxSession.executeQuery(String.format(sql, metaBasePath, name, safeVersion, projectName))
                : iginxSession.executeQuery(String.format(sql, metaBasePath, name, safeVersion));
        List<String> head = res.getColumnList();
        Object[] row = res.nextRow();
        Map<String, Object> rs = new LinkedHashMap<>();
        for (int i=0; i<=head.size() -1; i++){
            rs.put(head.get(i), row[i]);
        }
        // iginxSession.closeSession();

            ModelMetaEntity dto = new ModelMetaEntity();
        // 根据控制台输出的列名进行映射
        rs.forEach((k,v) -> setDtoField(dto, k, v));
        return dto;
        } catch (Exception e) {
            log.error("查询失败", e);
            return null;
        }
    }

    /**
     * 根据字段名设置DTO属性
     */
    private void setDtoField(ModelMetaEntity dto, String fieldName, Object value) {
        try {
            switch (fieldName) {
                case META_PREFIX+"."+"name":
                    if (value instanceof byte[]) {
                        dto.setName(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setName((String) value);
                    }
                    break;
                case META_PREFIX+"."+"version":
                    if (value instanceof byte[]) {
                        dto.setVersion(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setVersion((String) value);
                    }
                    break;
                case META_PREFIX+"."+"fileName":
                    if (value instanceof byte[]) {
                        dto.setFileName(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setFileName((String) value);
                    }
                    break;
                case META_PREFIX+"."+"fileSize":
                    if (value instanceof Long) {
                        dto.setFileSize((Long) value);
                    } else if (value instanceof Integer) {
                        dto.setFileSize(((Integer) value).longValue());
                    }
                    break;
                case META_PREFIX+"."+"chunkCount":
                    if (value instanceof Long) {
                        dto.setChunkCount(((Long) value).intValue());
                    } else if (value instanceof Integer) {
                        dto.setChunkCount((Integer) value);
                    }
                    break;
                case META_PREFIX+"."+"storagePath":
                    if (value instanceof byte[]) {
                        dto.setStoragePath(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setStoragePath((String) value);
                    }
                    break;
                case META_PREFIX+"."+"fileMd5":
                    if (value instanceof byte[]) {
                        dto.setFileMd5(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setFileMd5((String) value);
                    }
                    break;
                case META_PREFIX+"."+"author":
                    if (value instanceof byte[]) {
                        dto.setAuthor(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setAuthor((String) value);
                    }
                    break;
                case META_PREFIX+"."+"scene":
                    if (value instanceof byte[]) {
                        dto.setScene(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setScene((String) value);
                    }
                    break;
                case META_PREFIX+"."+"inputs":
                    if (value instanceof byte[]) {
                        dto.setInputs(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setInputs((String) value);
                    }
                    break;
                case META_PREFIX+"."+"outputs":
                    if (value instanceof byte[]) {
                        dto.setOutputs(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setOutputs((String) value);
                    }
                    break;
                case META_PREFIX+"."+"apis":
                    if (value instanceof byte[]) {
                        dto.setApis(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setApis((String) value);
                    }
                    break;
                case META_PREFIX+"."+"timestamp":
                    if (value instanceof Long) {
                        dto.setTimestamp((Long) value);
                    }
                    break;
                case META_PREFIX+"."+"projectName":
                    if (value instanceof byte[]) {
                        dto.setProjectName(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setProjectName((String) value);
                    }
                    break;
                default:
                    log.debug("忽略未知字段: {}", fieldName);
            }
        } catch (Exception e) {
            log.warn("设置字段 {} 失败: {}", fieldName, e.getMessage());
        }
    }

    public List<ModelMetaEntity> queryMetaList(String name, String projectName) {
        try {
            String sql;
            if (projectName != null && !projectName.trim().isEmpty()) {
                sql = "select * from %s where name = '%s' and projectName = '%s' ORDER BY timestamp ;";
                SessionExecuteSqlResult res =  iginxSession.executeSql(String.format(sql, META_PREFIX, name, projectName));
                List<Map<String, Object>> records = ConvertUtil.getRecords(res);

                return records.stream()
                        .map(rs -> {
                            ModelMetaEntity dto = new ModelMetaEntity();
                            rs.forEach((k,v) -> setDtoField(dto, k, v));
                            return dto;
                        }).collect(Collectors.toList());
            } else {
                sql = "select * from %s where name = '%s' ORDER BY timestamp ;";
                SessionExecuteSqlResult res =  iginxSession.executeSql(String.format(sql, META_PREFIX, name));
                List<Map<String, Object>> records = ConvertUtil.getRecords(res);

                return records.stream()
                        .map(rs -> {
                            ModelMetaEntity dto = new ModelMetaEntity();
                            rs.forEach((k,v) -> setDtoField(dto, k, v));
                            return dto;
                        }).collect(Collectors.toList());
            }
        } catch (Exception e) {
            log.error("查询失败", e);
            return null;
        }
    }

    /**
     * 移除模型资产
     */
    public void deleteModel(String name, String version) {
        try {
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(ModelMetaEntity.class, META_PREFIX);
            if (StringUtils.hasText(version) && !"null".equals(version)) {
                ModelMetaEntity queryMeta = queryMeta(name, version);
                String storagePath = buildStoragePath(queryMeta.getProjectName(), name, version);
                iginxClient.getDeleteClient().deleteMeasurement(storagePath);
                if (queryMeta != null && queryMeta.getTimestamp() != null) {
                    long timestamp = queryMeta.getTimestamp();
                    iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp-1, timestamp+1);
                }
                dataPermissionService.deleteByTablePrefix(storagePath);
            } else {
                String projectName = ProjectContext.getCurrentProject("unknown");
                List<ModelMetaEntity> queryMetas = queryMetaList(name, projectName);
                List<String> storagePaths = queryMetas.stream()
                        .map(meta ->
                                buildStoragePath(meta.getProjectName(),meta.getName(), meta.getVersion())
                        )
                        .collect(Collectors.toList());
                iginxClient.getDeleteClient().deleteMeasurements(storagePaths);
                queryMetas.stream()
                        .map(ModelMetaEntity::getTimestamp)
                        .forEach(timestamp ->
                                iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp-1, timestamp+1)
                        );
                storagePaths.forEach(storagePath -> dataPermissionService.deleteByTablePrefix(storagePath));
            }
        } catch (Exception e) {
            log.error("移除模型资产失败", e);
        }
    }

    /**
     * 构建存储路径（含项目名称）
     */
    private String buildStoragePath(String projectName, String name, String version) {
        projectName = StringUtils.hasText(projectName)? projectName : ProjectContext.getCurrentProject("unknown");
        String safeVersion = version.replace('.', '_');
        return String.format("%s.%s.%s.%s", STORAGE_PREFIX_BASE, projectName, name, safeVersion);
    }

    /**
     * 查询模型资产树（按项目名过滤）
     */
    public List<String> queryModelTree(String projectName) {
        try {
            String prefix;
            if (StringUtils.hasText(projectName)) {
                prefix = STORAGE_PREFIX_BASE + "." + projectName;
            } else {
                prefix = STORAGE_PREFIX_BASE;
            }
            String sql = String.format("SHOW TABLES LIKE '%s.*';", prefix);
            log.info("执行SQL: {}", sql);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql);
            List<String> paths = new ArrayList<>();
            if (res.getPaths() != null) {
                for (String path : res.getPaths()) {
                    if (path.startsWith(prefix)) {
                        paths.add(path);
                    }
                }
            }
            return paths;
        } catch (Exception e) {
            log.error("查询模型资产树失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 分页查询模型元数据（按项目名过滤）
     */
    public List<ModelMetaEntity> queryModelArchives(String name, String projectName, String author, Integer pageNum, Integer pageSize) {
        try {
            StringBuilder sql = new StringBuilder("SELECT * FROM " + META_PREFIX + " WHERE 1=1");
            if (name != null && !name.trim().isEmpty()) {
                sql.append(" AND name LIKE '^.*").append(name.trim()).append(".*'");
            }
            if (projectName != null && !projectName.trim().isEmpty()) {
                sql.append(" AND projectName LIKE '^.*").append(projectName.trim()).append(".*'");
            }
            if (author != null && !author.trim().isEmpty()) {
                sql.append(" AND author LIKE '^.*").append(author.trim()).append(".*'");
            }
            if (pageNum != null && pageSize != null) {
                sql.append(" LIMIT ").append(pageSize);
                sql.append(" OFFSET ").append((pageNum - 1) * pageSize);
            }
            sql.append(";");
            log.info("执行SQL: {}", sql);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            return records.stream().map(rs -> {
                ModelMetaEntity dto = new ModelMetaEntity();
                rs.forEach((k, v) -> setDtoField(dto, k, v));
                return dto;
            }).collect(Collectors.toList());
        } catch (Exception e) {
            log.error("查询模型档案列表失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 计算文件的 MD5 校验和
     */
    private String calculateMD5(byte[] bytes) {
        try {
            java.security.MessageDigest md = java.security.MessageDigest.getInstance("MD5");
            byte[] digest = md.digest(bytes);
            StringBuilder sb = new StringBuilder();
            for (byte b : digest) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (Exception e) {
            log.warn("计算 MD5 失败", e);
            return "";
        }
    }
}
