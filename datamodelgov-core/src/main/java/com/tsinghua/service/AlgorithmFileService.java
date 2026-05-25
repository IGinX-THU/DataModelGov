package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Column;
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
import com.tsinghua.dto.ColumnDto;
import com.tsinghua.entity.AlgorithmMetaEntity;
import com.tsinghua.dto.UploadResult;
import com.tsinghua.util.ConvertUtil;
import com.tsinghua.util.ProjectContext;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
public class AlgorithmFileService {

    private static final int CHUNK_SIZE = 65536; // 64KB
    private static final String STORAGE_PREFIX_BASE = "algorithms_system";
    private static final String META_PREFIX = "relational_system.algorithms_meta";

    @Autowired
    private DataPermissionService dataPermissionService;

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private ProjectService projectService;

    /**
     * 上传算法文件
     * 直接将二进制分块数据写入 IGinX，无需 Base64 编码
     */
    public UploadResult uploadAlgorithm(MultipartFile file, String name, String version) throws Exception {
        String projectName = ProjectContext.getCurrentProject("unknown");
        String storagePath = buildStoragePath(name, version);

        if (dataPermissionService.existTablePrefix(storagePath)) {
            throw new IllegalArgumentException("算法资产已存在");
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
                log.info("算法 {} 版本 {}: 处理进度 {}/{}", name, version, i + 1, totalChunks);
            }
        }

        // 批量写入数据点
        log.info("开始写入算法文件: {} 版本 {}, 共 {} 个数据块...", name, version, totalChunks);
        iginxClient.getWriteClient().writePoints(points);

        // 计算文件校验信息
        String fileMd5 = calculateMD5(fileBytes);

        log.info("算法文件上传成功。名称: {}, 版本: {}, 块数: {}, MD5: {}",
                name, version, totalChunks, fileMd5);

        // 2. 保存算法元数据 (行式对齐存储)
        AlgorithmMetaEntity algorithmMetaDto = new AlgorithmMetaEntity();
        algorithmMetaDto.setName(name);
        algorithmMetaDto.setVersion(version);
        algorithmMetaDto.setFileName(file.getOriginalFilename());
        algorithmMetaDto.setFileSize(file.getSize());
        algorithmMetaDto.setChunkCount(totalChunks);
        algorithmMetaDto.setStoragePath(storagePath);
        algorithmMetaDto.setFileMd5(fileMd5);
        algorithmMetaDto.setProjectName(projectName);
        algorithmMetaDto.setAuthor(com.tsinghua.auth.util.AuthUtil.getCurrentUsername());
        // 初始化新增字段为空
        algorithmMetaDto.setTableName("");
        algorithmMetaDto.setInputData("");
        algorithmMetaDto.setCalledModels("");
        algorithmMetaDto.setInputsBind("");
        algorithmMetaDto.setOutputsBind("");
        algorithmMetaDto.setCmd("");
        algorithmMetaDto.setInputCsvName("");
        algorithmMetaDto.setOutputCsvName("");
        saveAlgorithmMetadata(algorithmMetaDto);

        dataPermissionService.saveTablePrefix(storagePath);
        log.info("算法文件上传成功。storagePath: {}", storagePath);

        // 添加到项目的algorithms字段
        if (projectName != null && !projectName.isEmpty()) {
            try {
                projectService.addToProject(projectName, storagePath, "algorithms");
            } catch (Exception e) {
                log.error("添加算法路径到项目失败", e);
            }
        }

        return new UploadResult(name, version, file.getOriginalFilename(),
                file.getSize(), totalChunks, storagePath, fileMd5);
    }

    /**
     * 下载算法文件 (优化版)
     * 1. 先查询元数据验证算法信息
     * 2. 按chunkCount精确获取文件块
     * 3. 校验MD5确保文件完整性
     */
    public byte[] downloadAlgorithm(String name, String version) throws Exception {
        log.info("开始下载算法: {} v{}", name, version);

        // 1. 先查询元数据验证算法信息
        AlgorithmMetaEntity algorithmMeta = queryMeta(name, version);
        if (algorithmMeta == null) {
            throw new Exception("未找到指定的算法元数据: " + name + " v" + version);
        }

        // 验证元数据完整性
        if (algorithmMeta.getChunkCount() == null || algorithmMeta.getChunkCount() <= 0) {
            throw new Exception("算法元数据不完整: chunkCount无效");
        }

        if (algorithmMeta.getFileMd5() == null || algorithmMeta.getFileMd5().isEmpty()) {
            throw new Exception("算法元数据不完整: fileMd5无效");
        }

        log.info("元数据验证通过 - 文件名: {}, 块数: {}, 存储路径: {}, MD5: {}",
                algorithmMeta.getFileName(), algorithmMeta.getChunkCount(), algorithmMeta.getStoragePath(), algorithmMeta.getFileMd5());

        // 2. 按chunkCount精确获取文件块
        String storagePath = buildStoragePath(name, version);
        TreeMap<Integer, byte[]> chunkMap = new TreeMap<>();

        // 构建查询 - 只查询指定数量的块
        SimpleQuery query = SimpleQuery.builder()
                .addMeasurement(storagePath)
                .endKey(Long.MAX_VALUE)
                .build();

        IginXTable table = iginxClient.getQueryClient().query(query);

        if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) {
            throw new Exception("未找到指定的算法文件数据: " + name + " v" + version);
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
        for (int i = 0; i < algorithmMeta.getChunkCount(); i++) {
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
        if (!actualMd5.equals(algorithmMeta.getFileMd5())) {
            log.error("MD5校验失败! 期望: {}, 实际: {}", algorithmMeta.getFileMd5(), actualMd5);
            throw new Exception(String.format("文件完整性校验失败! MD5不匹配 - 期望: %s, 实际: %s",
                    algorithmMeta.getFileMd5(), actualMd5));
        }

        log.info("算法文件下载成功 - 名称: {}, 版本: {}, 文件名: {}, 大小: {} bytes, 块数: {}, MD5: {}",
                name, version, algorithmMeta.getFileName(), fileBytes.length, chunkMap.size(), actualMd5);

        return fileBytes;
    }

    /**
     * 提取算法文件（返回文件列表给前端）
     */
    public List<Map<String, Object>> extractAlgorithmFile(String algorithmName, String algorithmVersion, Path taskDir) throws Exception {
        if (!StringUtils.hasText(algorithmName) || !StringUtils.hasText(algorithmVersion)) {
            throw new RuntimeException("算法名称或版本为空");
        }

        log.info("开始下载算法: {} 版本 {}", algorithmName, algorithmVersion);

        // 获取算法元数据以获取正确的文件名
        AlgorithmMetaEntity algorithmMeta = queryMeta(algorithmName, algorithmVersion);
        if (algorithmMeta == null) {
            throw new RuntimeException("未找到算法元数据: " + algorithmName + " 版本 " + algorithmVersion);
        }

        byte[] algorithmData = downloadAlgorithm(algorithmName, algorithmVersion);
        String fileName = algorithmMeta.getFileName();
        if (fileName == null || fileName.trim().isEmpty()) {
            throw new RuntimeException("算法文件名为空: " + algorithmName + " 版本 " + algorithmVersion);
        }

        Path algorithmFile = taskDir.resolve(fileName);
        Files.write(algorithmFile, algorithmData);
        log.info("算法文件已下载到: {}", algorithmFile);

        // 如果是压缩包，解压到任务目录
        if (fileName.toLowerCase().endsWith(".zip") || fileName.toLowerCase().endsWith(".tar") ||
                fileName.toLowerCase().endsWith(".tar.gz") || fileName.toLowerCase().endsWith(".tgz")) {
            extractArchive(algorithmFile, taskDir);
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
        return fileName.endsWith(".py") || fileName.endsWith(".m") || 
               fileName.endsWith(".cpp") || fileName.endsWith(".c") || 
               fileName.endsWith(".h") || fileName.endsWith(".java") ||
               fileName.endsWith(".js") || fileName.endsWith(".ts") ||
               fileName.endsWith(".txt") || fileName.endsWith(".md");
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
     * 保存算法元数据 (行式对齐存储)
     * 每个字段作为独立的时序序列存储，使用相同的时间戳对齐
     */
    public void saveAlgorithmMetadata(AlgorithmMetaEntity algorithmMetaDto) throws Exception {
        List<Point> metaPoints = new ArrayList<>();
        AlgorithmMetaEntity queryMeta = queryMeta(algorithmMetaDto.getName(), algorithmMetaDto.getVersion());
        long timestamp;
        if (queryMeta != null && queryMeta.getTimestamp() != null) {
            timestamp = queryMeta.getTimestamp();
        } else {
            timestamp = System.currentTimeMillis();
        }
        String safeVersion = algorithmMetaDto.getVersion().replace('.', '_');
        String metaBasePath = META_PREFIX;

        // 创建各个字段的数据点
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "name", algorithmMetaDto.getName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "version", safeVersion, timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "fileName", algorithmMetaDto.getFileName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "fileSize", algorithmMetaDto.getFileSize(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "chunkCount", algorithmMetaDto.getChunkCount(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "storagePath", algorithmMetaDto.getStoragePath(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "fileMd5", algorithmMetaDto.getFileMd5(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "author", algorithmMetaDto.getAuthor(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "scene", algorithmMetaDto.getScene(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "inputs", algorithmMetaDto.getInputs(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "outputs", algorithmMetaDto.getOutputs(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "timestamp", timestamp, timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "projectName", algorithmMetaDto.getProjectName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "description", algorithmMetaDto.getDescription(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "tableName", algorithmMetaDto.getTableName() != null ? algorithmMetaDto.getTableName() : "", timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "inputData", algorithmMetaDto.getInputData() != null ? algorithmMetaDto.getInputData() : "", timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "calledModels", algorithmMetaDto.getCalledModels() != null ? algorithmMetaDto.getCalledModels() : "", timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "inputsBind", algorithmMetaDto.getInputsBind() != null ? algorithmMetaDto.getInputsBind() : "", timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "outputsBind", algorithmMetaDto.getOutputsBind() != null ? algorithmMetaDto.getOutputsBind() : "", timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "cmd", algorithmMetaDto.getCmd() != null ? algorithmMetaDto.getCmd() : "", timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "inputCsvName", algorithmMetaDto.getInputCsvName() != null ? algorithmMetaDto.getInputCsvName() : "", timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "outputCsvName", algorithmMetaDto.getOutputCsvName() != null ? algorithmMetaDto.getOutputCsvName() : "", timestamp));

        // 批量写入元数据
        iginxClient.getWriteClient().writePoints(metaPoints.stream().filter(Objects::nonNull).collect(Collectors.toList()));
        log.info("算法元数据已保存。名称: {}, 版本: {}, 时间戳: {}", algorithmMetaDto.getName(), algorithmMetaDto.getVersion(), timestamp);
    }

    public AlgorithmMetaEntity queryMeta(String name, String version) {
        try {
            String sql = "select * from %s where name = '%s' and version='%s';";
        String metaBasePath = META_PREFIX;
        String safeVersion = version.replace('.', '_');
        // iginxSession.openSession();
        QueryDataSet res =  iginxSession.executeQuery(String.format(sql, metaBasePath, name, safeVersion));
        List<String> head = res.getColumnList();
        Object[] row = res.nextRow();
        Map<String, Object> rs = new LinkedHashMap<>();
        for (int i=0; i<=head.size() -1; i++){
            rs.put(head.get(i), row[i]);
        }
        // iginxSession.closeSession();

            AlgorithmMetaEntity dto = new AlgorithmMetaEntity();
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
    private void setDtoField(AlgorithmMetaEntity dto, String fieldName, Object value) {
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
                case META_PREFIX+"."+"description":
                    if (value instanceof byte[]) {
                        dto.setDescription(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setDescription((String) value);
                    }
                    break;
                case META_PREFIX+"."+"tableName":
                    if (value instanceof byte[]) {
                        dto.setTableName(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setTableName((String) value);
                    }
                    break;
                case META_PREFIX+"."+"inputData":
                    if (value instanceof byte[]) {
                        dto.setInputData(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setInputData((String) value);
                    }
                    break;
                case META_PREFIX+"."+"calledModels":
                    if (value instanceof byte[]) {
                        dto.setCalledModels(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setCalledModels((String) value);
                    }
                    break;
                case META_PREFIX+"."+"inputsBind":
                    if (value instanceof byte[]) {
                        dto.setInputsBind(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setInputsBind((String) value);
                    }
                    break;
                case META_PREFIX+"."+"outputsBind":
                    if (value instanceof byte[]) {
                        dto.setOutputsBind(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setOutputsBind((String) value);
                    }
                    break;
                case META_PREFIX+"."+"cmd":
                    if (value instanceof byte[]) {
                        dto.setCmd(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setCmd((String) value);
                    }
                    break;
                case META_PREFIX+"."+"inputCsvName":
                    if (value instanceof byte[]) {
                        dto.setInputCsvName(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setInputCsvName((String) value);
                    }
                    break;
                case META_PREFIX+"."+"outputCsvName":
                    if (value instanceof byte[]) {
                        dto.setOutputCsvName(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setOutputCsvName((String) value);
                    }
                    break;
                default:
                    log.debug("忽略未知字段: {}", fieldName);
            }
        } catch (Exception e) {
            log.warn("设置字段 {} 失败: {}", fieldName, e.getMessage());
        }
    }

    public List<AlgorithmMetaEntity> queryMetaList(String name) {
        try {
            String sql = "select * from %s where name = '%s' ORDER BY timestamp ;";
            // iginxSession.openSession();
            SessionExecuteSqlResult res =  iginxSession.executeSql(String.format(sql, META_PREFIX, name));
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            // iginxSession.closeSession();

            return records.stream()
                    .map(rs -> {
                        AlgorithmMetaEntity dto = new AlgorithmMetaEntity();
                        // 根据控制台输出的列名进行映射
                        rs.forEach((k,v) -> setDtoField(dto, k, v));
                        return dto;
                    }).collect(Collectors.toList());
        } catch (Exception e) {
            log.error("查询失败", e);
            return null;
        }
    }

    /**
     * 移除算法资产
     */
    public void deleteAlgorithm(String name, String version) {
        try {
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(AlgorithmMetaEntity.class, META_PREFIX);
            if (StringUtils.hasText(version) && !"null".equals(version)) {
                String storagePath = buildStoragePath(name, version);
                iginxClient.getDeleteClient().deleteMeasurement(storagePath);
                AlgorithmMetaEntity queryMeta = queryMeta(name, version);
                if (queryMeta != null && queryMeta.getTimestamp() != null) {
                    long timestamp = queryMeta.getTimestamp();
                    iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp-1, timestamp+1);
                }
                dataPermissionService.deleteByTablePrefix(storagePath);
            } else {
                List<AlgorithmMetaEntity> queryMetas = queryMetaList(name);
                List<String> storagePaths = queryMetas.stream()
                        .map(meta ->
                                buildStoragePath(meta.getName(), meta.getVersion())
                        )
                        .collect(Collectors.toList());
                iginxClient.getDeleteClient().deleteMeasurements(storagePaths);
                queryMetas.stream()
                        .map(AlgorithmMetaEntity::getTimestamp)
                        .forEach(timestamp ->
                                iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp-1, timestamp+1)
                        );
                storagePaths.forEach(storagePath -> dataPermissionService.deleteByTablePrefix(storagePath));
            }
        } catch (Exception e) {
            log.error("移除算法资产失败", e);
        }
    }

    /**
     * 构建存储路径
     */
    private String buildStoragePath(String name, String version) {
        String projectName = ProjectContext.getCurrentProject("unknown");
        String safeVersion = version.replace('.', '_');
        return String.format("%s.%s.%s.%s", STORAGE_PREFIX_BASE, projectName, name, safeVersion);
    }

    /**
     * 查询算法资产树（按项目名过滤）
     */
    public List<String> queryAlgorithmTree(String projectName) {
        try {
            String prefix;
            if (StringUtils.hasText(projectName)) {
                prefix = STORAGE_PREFIX_BASE + "." + projectName;
            } else {
                prefix = STORAGE_PREFIX_BASE + "." + ProjectContext.getCurrentProject("unknown");
            }
            List<Column> columnList = iginxSession.showColumns();
            List<ColumnDto> tree = columnList.stream()
                    .filter(column -> column.getPath().startsWith(STORAGE_PREFIX_BASE))
                    .map(column -> new ColumnDto(column.getPath(), column.getDataType().getValue()))
                    .collect(Collectors.toList());
            List<String> paths = new ArrayList<>();
            if (!tree.isEmpty()) {
                for (ColumnDto columnDto : tree) {
                    if (columnDto.getPath().startsWith(prefix)) {
                        paths.add(columnDto.getPath());
                    }
                }
            }
            return paths;
        } catch (Exception e) {
            log.error("查询算法资产树失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 分页查询算法元数据（按项目名过滤）
     */
    public List<AlgorithmMetaEntity> queryAlgorithmArchives(String name, String projectName, String author, Integer pageNum, Integer pageSize) {
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
                AlgorithmMetaEntity dto = new AlgorithmMetaEntity();
                rs.forEach((k, v) -> setDtoField(dto, k, v));
                return dto;
            }).collect(Collectors.toList());
        } catch (Exception e) {
            log.error("查询算法档案列表失败", e);
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
