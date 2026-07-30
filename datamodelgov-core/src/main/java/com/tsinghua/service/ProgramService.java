package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.QueryDataSet;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.query.SimpleQuery;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.ProgramEntity;
import com.tsinghua.dto.UploadResult;
import com.tsinghua.model.Result;
import com.tsinghua.util.ConvertUtil;
import com.tsinghua.util.ProjectContext;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import java.io.*;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;
import java.util.zip.GZIPInputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import net.sf.sevenzipjbinding.*;
import net.sf.sevenzipjbinding.impl.RandomAccessFileInStream;
import net.sf.sevenzipjbinding.simple.ISimpleInArchive;
import net.sf.sevenzipjbinding.simple.ISimpleInArchiveItem;
import org.apache.commons.compress.archivers.sevenz.SevenZArchiveEntry;
import org.apache.commons.compress.archivers.sevenz.SevenZFile;
import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream;

@Slf4j
@Service
public class ProgramService {

    private static final int CHUNK_SIZE = 65536;
    private static final String STORAGE_PREFIX_BASE = "programs_system";
    private static final String META_PREFIX = "relational_system.programs_meta";

    private static final String TASK_BASE_DIR = "project";
    private final ObjectMapper mapper = new ObjectMapper();
    private final Map<String, ProgramEntity> runtimeStatus = new ConcurrentHashMap<>();
    private final Map<String, Process> processMap = new ConcurrentHashMap<>();
    private static final Set<String> SUPPORTED_ARCHIVE = new HashSet<>(Arrays.asList(".zip", ".rar", ".7z", ".tar", ".tar.gz", ".tgz"));
    private static final boolean SEVENZIP_AVAILABLE;

    static {
        boolean available = false;
        try {
            SevenZip.initSevenZipFromPlatformJAR();
            available = true;
        } catch (SevenZipNativeInitializationException e) {
            log.error("SevenZipJBinding 初始化失败", e);
        }
        SEVENZIP_AVAILABLE = available;
    }

    @Autowired
    private DataPermissionService dataPermissionService;

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private ProjectService projectService;

    private String safeProjectName(String projectName) {
        String proj = (projectName != null && !projectName.isEmpty()) ? projectName : ProjectContext.getCurrentProject("unknown");
        return proj.replaceAll("[^\\x00-\\x7F]+", "undefined");
    }

    private File getTaskBaseDir(String projectName) {
        String safeProj = safeProjectName(projectName);
        File dir = new File(TASK_BASE_DIR + "/" + safeProj + "/job/program-tasks");
        if (!dir.exists()) dir.mkdirs();
        return dir;
    }

    private File getProgramDir(String projectName, String name, String version) {
        String safeProj = safeProjectName(projectName);
        String safeVersion = version.replace('.', '_');
        File dir = new File(TASK_BASE_DIR + "/" + safeProj + "/program/" + name + "_" + safeVersion);
        return dir;
    }

    /**
     * 构建存储路径（含项目名称）
     */
    private String buildStoragePath(String projectName, String name, String version) {
        projectName = StringUtils.hasText(projectName) ? projectName : ProjectContext.getCurrentProject("unknown");
        String safeVersion = version.replace('.', '_');
        return String.format("%s.%s.%s.%s", STORAGE_PREFIX_BASE, projectName, name, safeVersion);
    }

    public ProgramEntity queryMeta(String name, String version) {
        return queryMeta(name, version, ProjectContext.getCurrentProject(null));
    }

    public ProgramEntity queryMeta(String name, String version, String projectName) {
        try {
            String sql;
            if (StringUtils.hasText(projectName)) {
                sql = "select * from %s where name = '%s' and version='%s' and projectName='%s';";
            } else {
                sql = "select * from %s where name = '%s' and version='%s';";
            }
            String metaBasePath = META_PREFIX;
            String safeVersion = version.replace('.', '_');
            QueryDataSet res = StringUtils.hasText(projectName)
                    ? iginxSession.executeQuery(String.format(sql, metaBasePath, name, safeVersion, projectName))
                    : iginxSession.executeQuery(String.format(sql, metaBasePath, name, safeVersion));
            List<String> head = res.getColumnList();
            Object[] row = res.nextRow();
            if (row == null) return null;
            Map<String, Object> rs = new LinkedHashMap<>();
            for (int i = 0; i <= head.size() - 1; i++) {
                rs.put(head.get(i), row[i]);
            }

            ProgramEntity dto = new ProgramEntity();
            rs.forEach((k, v) -> setDtoField(dto, k, v));
            return mergeRuntimeStatus(dto);
        } catch (Exception e) {
            log.error("查询失败", e);
            return null;
        }
    }

    /**
     * 根据字段名设置DTO属性
     */
    private void setDtoField(ProgramEntity dto, String fieldName, Object value) {
        try {
            switch (fieldName) {
                case META_PREFIX + "." + "name":
                    if (value instanceof byte[]) {
                        dto.setName(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setName((String) value);
                    }
                    break;
                case META_PREFIX + "." + "version":
                    if (value instanceof byte[]) {
                        dto.setVersion(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setVersion((String) value);
                    }
                    break;
                case META_PREFIX + "." + "description":
                    if (value instanceof byte[]) {
                        dto.setDescription(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setDescription((String) value);
                    }
                    break;
                case META_PREFIX + "." + "programDir":
                    if (value instanceof byte[]) {
                        dto.setProgramDir(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setProgramDir((String) value);
                    }
                    break;
                case META_PREFIX + "." + "configJson":
                    if (value instanceof byte[]) {
                        dto.setConfigJson(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setConfigJson((String) value);
                    }
                    break;
                case META_PREFIX + "." + "status":
                    if (value instanceof byte[]) {
                        dto.setStatus(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setStatus((String) value);
                    }
                    break;
                case META_PREFIX + "." + "lastError":
                    if (value instanceof byte[]) {
                        dto.setLastError(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setLastError((String) value);
                    }
                    break;
                case META_PREFIX + "." + "lastRunTime":
                    if (value instanceof Long) {
                        dto.setLastRunTime((Long) value);
                    }
                    break;
                case META_PREFIX + "." + "lastResultCsv":
                    if (value instanceof byte[]) {
                        dto.setLastResultCsv(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setLastResultCsv((String) value);
                    }
                    break;
                case META_PREFIX + "." + "lastLogPath":
                    if (value instanceof byte[]) {
                        dto.setLastLogPath(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setLastLogPath((String) value);
                    }
                    break;
                case META_PREFIX + "." + "lastResultDir":
                    if (value instanceof byte[]) {
                        dto.setLastResultDir(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setLastResultDir((String) value);
                    }
                    break;
                case META_PREFIX + "." + "fileName":
                    if (value instanceof byte[]) {
                        dto.setFileName(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setFileName((String) value);
                    }
                    break;
                case META_PREFIX + "." + "fileSize":
                    if (value instanceof Long) {
                        dto.setFileSize((Long) value);
                    } else if (value instanceof Integer) {
                        dto.setFileSize(((Integer) value).longValue());
                    }
                    break;
                case META_PREFIX + "." + "chunkCount":
                    if (value instanceof Long) {
                        dto.setChunkCount(((Long) value).intValue());
                    } else if (value instanceof Integer) {
                        dto.setChunkCount((Integer) value);
                    }
                    break;
                case META_PREFIX + "." + "fileMd5":
                    if (value instanceof byte[]) {
                        dto.setFileMd5(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setFileMd5((String) value);
                    }
                    break;
                case META_PREFIX + "." + "storagePath":
                    if (value instanceof byte[]) {
                        dto.setStoragePath(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setStoragePath((String) value);
                    }
                    break;
                case META_PREFIX + "." + "author":
                    if (value instanceof byte[]) {
                        dto.setAuthor(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setAuthor((String) value);
                    }
                    break;
                case META_PREFIX + "." + "projectName":
                    if (value instanceof byte[]) {
                        dto.setProjectName(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setProjectName((String) value);
                    }
                    break;
                case META_PREFIX + "." + "timestamp":
                    if (value instanceof Long) {
                        dto.setTimestamp((Long) value);
                    }
                    break;
                default:
                    log.debug("忽略未知字段: {}", fieldName);
            }
        } catch (Exception e) {
            log.warn("设置字段 {} 失败: {}", fieldName, e.getMessage());
        }
    }

    public List<ProgramEntity> queryMetaList(String name, String projectName) {
        try {
            String sql;
            if (projectName != null && !projectName.trim().isEmpty()) {
                sql = "select * from %s where name = '%s' and projectName = '%s' ORDER BY timestamp ;";
                SessionExecuteSqlResult res = iginxSession.executeSql(String.format(sql, META_PREFIX, name, projectName));
                List<Map<String, Object>> records = ConvertUtil.getRecords(res);

                return records.stream()
                        .map(rs -> {
                            ProgramEntity dto = new ProgramEntity();
                            rs.forEach((k, v) -> setDtoField(dto, k, v));
                            return dto;
                        }).collect(Collectors.toList());
            } else {
                sql = "select * from %s where name = '%s' ORDER BY timestamp ;";
                SessionExecuteSqlResult res = iginxSession.executeSql(String.format(sql, META_PREFIX, name));
                List<Map<String, Object>> records = ConvertUtil.getRecords(res);

                return records.stream()
                        .map(rs -> {
                            ProgramEntity dto = new ProgramEntity();
                            rs.forEach((k, v) -> setDtoField(dto, k, v));
                            return dto;
                        }).collect(Collectors.toList());
            }
        } catch (Exception e) {
            log.error("查询失败", e);
            return null;
        }
    }

    /**
     * 查询仿真程序资产树（按项目名过滤）
     */
    public List<String> queryProgramTree(String projectName) {
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
            log.error("查询仿真程序树失败", e);
            return new ArrayList<>();
        }
    }

    public List<ProgramEntity> queryProgramList(String name, String projectName, String author, Integer pageNum, Integer pageSize) {
        try {
            StringBuilder sql = new StringBuilder("SELECT * FROM " + META_PREFIX + " WHERE 1=1");
            if (name != null && !name.trim().isEmpty()) {
                sql.append(" AND name LIKE '^.*").append(name.trim()).append(".*'");
            }
            if (projectName != null && !projectName.trim().isEmpty()) {
                sql.append(" AND projectName LIKE '^.*").append(projectName.trim()).append(".*'");
            }
            if (author != null && !author.trim().isEmpty()) {
                sql.append(" AND author = '").append(author.trim()).append("'");
            } else if (!AuthUtil.isAdmin()) {
                sql.append(" AND author = '").append(AuthUtil.getCurrentUsername()).append("'");
            }
            if (pageNum != null && pageSize != null) {
                sql.append(" LIMIT ").append(pageSize);
                sql.append(" OFFSET ").append((pageNum - 1) * pageSize);
            }
            sql.append(";");
            log.info("执行SQL: {}", sql);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            if (records == null) return new ArrayList<>();
            List<ProgramEntity> list = new ArrayList<>();
            for (Map<String, Object> record : records) {
                ProgramEntity entity = new ProgramEntity();
                record.forEach((k, v) -> setDtoField(entity, k, v));
                list.add(mergeRuntimeStatus(entity));
            }
            return list;
        } catch (Exception e) {
            log.error("查询程序列表失败", e);
            return new ArrayList<>();
        }
    }

    public List<ProgramEntity> queryProgramList() {
        return queryProgramList(null, null, null, null, null);
    }

    public long countProgramList(String name, String projectName, String author) {
        try {
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM " + META_PREFIX + " WHERE 1=1");
            if (name != null && !name.trim().isEmpty()) {
                sql.append(" AND name LIKE '^.*").append(name.trim()).append(".*'");
            }
            if (projectName != null && !projectName.trim().isEmpty()) {
                sql.append(" AND projectName LIKE '^.*").append(projectName.trim()).append(".*'");
            }
            if (author != null && !author.trim().isEmpty()) {
                sql.append(" AND author = '").append(author.trim()).append("'");
            } else if (!AuthUtil.isAdmin()) {
                sql.append(" AND author = '").append(AuthUtil.getCurrentUsername()).append("'");
            }
            sql.append(";");
            log.info("执行SQL: {}", sql);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            if (records == null || records.isEmpty()) return 0;
            Object count = records.get(0).values().iterator().next();
            if (count instanceof Number) return ((Number) count).longValue();
            return 0;
        } catch (Exception e) {
            log.error("查询程序总数失败", e);
            return 0;
        }
    }

    private String runtimeKey(ProgramEntity entity) {
        return entity.getName() + "_" + entity.getVersion() + "_" + entity.getProjectName();
    }

    private ProgramEntity mergeRuntimeStatus(ProgramEntity entity) {
        if (entity == null) return null;
        ProgramEntity runtime = runtimeStatus.get(runtimeKey(entity));
        if (runtime == null) return entity;
        entity.setStatus(runtime.getStatus());
        entity.setLastError(runtime.getLastError());
        entity.setLastRunTime(runtime.getLastRunTime());
        entity.setLastResultCsv(runtime.getLastResultCsv());
        entity.setLastLogPath(runtime.getLastLogPath());
        return entity;
    }

    /**
     * 保存仿真程序元数据
     */
    public void saveProgramMetadata(ProgramEntity entity) throws Exception {
        ProgramEntity queryMeta = queryMeta(entity.getName(), entity.getVersion(), entity.getProjectName());
        long timestamp;
        if (entity.getTimestamp() != null) {
            timestamp = entity.getTimestamp();
        } else if (queryMeta != null && queryMeta.getTimestamp() != null) {
            timestamp = queryMeta.getTimestamp();
        } else {
            timestamp = System.currentTimeMillis();
        }
        entity.setTimestamp(timestamp);
        String safeVersion = entity.getVersion().replace('.', '_');

        List<Point> points = new ArrayList<>();
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "name", entity.getName(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "version", safeVersion, timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "description", entity.getDescription(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "configJson", entity.getConfigJson(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "status", entity.getStatus(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "lastError", entity.getLastError(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "lastRunTime", entity.getLastRunTime(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "lastResultCsv", entity.getLastResultCsv(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "lastLogPath", entity.getLastLogPath(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "lastResultDir", entity.getLastResultDir(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "fileName", entity.getFileName(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "fileSize", entity.getFileSize(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "chunkCount", entity.getChunkCount(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "fileMd5", entity.getFileMd5(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "storagePath", entity.getStoragePath(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "author", entity.getAuthor(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "projectName", entity.getProjectName(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "programDir", entity.getProgramDir(), timestamp));
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "timestamp", timestamp, timestamp));
        iginxClient.getWriteClient().writePoints(points.stream().filter(Objects::nonNull).collect(Collectors.toList()));
        log.info("仿真程序元数据已保存。名称: {}, 版本: {}, 时间戳: {}", entity.getName(), entity.getVersion(), timestamp);
    }

    /**
     * 上传仿真程序文件
     * 直接将二进制分块数据写入 IGinX，无需 Base64 编码
     */
    public UploadResult uploadProgram(MultipartFile file, String name, String version, String description) throws Exception {
        String originalName = file.getOriginalFilename();
        if (originalName == null) throw new IllegalArgumentException("文件名为空");
        String ext = getExtension(originalName);
        if (ext == null || !SUPPORTED_ARCHIVE.contains(ext)) {
            throw new IllegalArgumentException("仅支持以下压缩格式: zip, rar, 7z, tar, tar.gz, tgz");
        }
        String programName = (name != null && !name.isEmpty()) ? name : removeArchiveExtension(originalName);
        String programVersion = (version != null && !version.isEmpty()) ? version : "1.0";
        String projectName = ProjectContext.getCurrentProject("unknown");
        String storagePath = buildStoragePath(projectName, programName, programVersion);

        if (dataPermissionService.existTablePrefix(storagePath)) {
            throw new IllegalArgumentException("仿真程序资产已存在");
        }

        // 先解压到项目目录验证能否成功
        byte[] fileBytes = file.getBytes();
        File programDir = getProgramDir(projectName, programName, programVersion);
        if (programDir.exists()) {
            deleteDirectory(programDir);
        }
        programDir.mkdirs();
        File tempArchive = new File(programDir, originalName);
        Files.write(tempArchive.toPath(), fileBytes);
        try {
            extractArchive(tempArchive, programDir);
            log.info("仿真程序解压验证成功。目录: {}", programDir.getAbsolutePath());
        } catch (Exception e) {
            deleteDirectory(programDir);
            throw new IllegalArgumentException("程序包解压失败: " + e.getMessage(), e);
        } finally {
            if (tempArchive.exists()) tempArchive.delete();
        }

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
                log.info("仿真程序 {} 版本 {}: 处理进度 {}/{}", programName, programVersion, i + 1, totalChunks);
            }
        }

        // 批量写入数据点
        log.info("开始写入仿真程序文件: {} 版本 {}, 共 {} 个数据块...", programName, programVersion, totalChunks);
        iginxClient.getWriteClient().writePoints(points);

        // 计算文件校验信息
        String fileMd5 = calculateMD5(fileBytes);

        log.info("仿真程序文件上传成功。名称: {}, 版本: {}, 块数: {}, MD5: {}",
                programName, programVersion, totalChunks, fileMd5);

        // 2. 保存仿真程序元数据 (行式对齐存储)
        ProgramEntity programMetaDto = new ProgramEntity();
        programMetaDto.setName(programName);
        programMetaDto.setVersion(programVersion);
        programMetaDto.setDescription(description);
        programMetaDto.setFileName(originalName);
        programMetaDto.setFileSize(file.getSize());
        programMetaDto.setChunkCount(totalChunks);
        programMetaDto.setStoragePath(storagePath);
        programMetaDto.setFileMd5(fileMd5);
        programMetaDto.setProjectName(projectName);
        programMetaDto.setAuthor(AuthUtil.getCurrentUsername());
        programMetaDto.setStatus("READY");
        programMetaDto.setConfigJson(buildDefaultConfig(programName).toString());
        saveProgramMetadata(programMetaDto);

        dataPermissionService.saveTablePrefix(storagePath);
        log.info("仿真程序文件上传成功。storagePath: {}", storagePath);

        // 添加到项目的programs字段
        if (projectName != null && !projectName.isEmpty()) {
            try {
                projectService.addToProject(projectName, storagePath, "programs");
            } catch (Exception e) {
                log.error("添加仿真程序路径到项目失败", e);
            }
        }

        return new UploadResult(programName, programVersion, originalName,
                file.getSize(), totalChunks, storagePath, fileMd5);
    }

    private void extractArchive(File archive, File targetDir) throws IOException {
        String ext = getExtension(archive.getName());
        if (".zip".equals(ext) || ".jar".equals(ext)) {
            extractZip(archive, targetDir);
        } else if (".rar".equals(ext)) {
            extractRar(archive, targetDir);
        } else if (".7z".equals(ext)) {
            extractSevenZ(archive, targetDir);
        } else if (".tar".equals(ext)) {
            extractTar(archive, targetDir);
        } else if (".tar.gz".equals(ext) || ".tgz".equals(ext)) {
            extractTarGz(archive, targetDir);
        } else {
            throw new IOException("不支持的压缩格式: " + ext);
        }
    }

    private void extractZip(File src, File targetDir) throws IOException {
        try (ZipInputStream zis = new ZipInputStream(new FileInputStream(src))) {
            ZipEntry entry;
            while ((entry = zis.getNextEntry()) != null) {
                File f = new File(targetDir, entry.getName());
                if (entry.isDirectory()) {
                    f.mkdirs();
                } else {
                    f.getParentFile().mkdirs();
                    try (FileOutputStream fos = new FileOutputStream(f)) {
                        byte[] buf = new byte[8192];
                        int len;
                        while ((len = zis.read(buf)) > 0) fos.write(buf, 0, len);
                    }
                }
                zis.closeEntry();
            }
        }
    }

    private void extractRar(File src, File targetDir) throws IOException {
        if (!SEVENZIP_AVAILABLE) {
            throw new IOException("SevenZipJBinding 未初始化，无法解压 RAR 文件");
        }
        try (RandomAccessFile raf = new RandomAccessFile(src, "r")) {
            IInArchive inArchive = SevenZip.openInArchive(null, new RandomAccessFileInStream(raf));
            try {
                ISimpleInArchive simple = inArchive.getSimpleInterface();
                for (ISimpleInArchiveItem item : simple.getArchiveItems()) {
                    final File out = new File(targetDir, item.getPath());
                    if (item.isFolder()) {
                        out.mkdirs();
                    } else {
                        out.getParentFile().mkdirs();
                        try (FileOutputStream fos = new FileOutputStream(out)) {
                            ExtractOperationResult result = item.extractSlow(data -> {
                                try {
                                    fos.write(data);
                                } catch (IOException e) {
                                    throw new SevenZipException("写入文件失败: " + out.getName(), e);
                                }
                                return data.length;
                            });
                            if (result != ExtractOperationResult.OK) {
                                throw new IOException("解压条目失败 " + item.getPath() + ": " + result);
                            }
                        }
                    }
                }
            } finally {
                if (inArchive != null) {
                    try { inArchive.close(); } catch (IOException ignored) {}
                }
            }
        }
    }

    private void extractSevenZ(File src, File targetDir) throws IOException {
        try (SevenZFile sevenZFile = new SevenZFile(src)) {
            SevenZArchiveEntry entry;
            while ((entry = sevenZFile.getNextEntry()) != null) {
                File f = new File(targetDir, entry.getName());
                if (entry.isDirectory()) {
                    f.mkdirs();
                } else {
                    f.getParentFile().mkdirs();
                    try (InputStream is = sevenZFile.getInputStream(entry);
                         FileOutputStream fos = new FileOutputStream(f)) {
                        copy(is, fos);
                    }
                }
            }
        }
    }

    private void extractTar(File src, File targetDir) throws IOException {
        try (TarArchiveInputStream tis = new TarArchiveInputStream(new FileInputStream(src))) {
            TarArchiveEntry entry;
            while ((entry = tis.getNextTarEntry()) != null) {
                File f = new File(targetDir, entry.getName());
                if (entry.isDirectory()) {
                    f.mkdirs();
                } else {
                    f.getParentFile().mkdirs();
                    try (FileOutputStream fos = new FileOutputStream(f)) {
                        copy(tis, fos);
                    }
                }
            }
        }
    }

    private void extractTarGz(File src, File targetDir) throws IOException {
        try (TarArchiveInputStream tis = new TarArchiveInputStream(new GZIPInputStream(new FileInputStream(src)))) {
            TarArchiveEntry entry;
            while ((entry = tis.getNextTarEntry()) != null) {
                File f = new File(targetDir, entry.getName());
                if (entry.isDirectory()) {
                    f.mkdirs();
                } else {
                    f.getParentFile().mkdirs();
                    try (FileOutputStream fos = new FileOutputStream(f)) {
                        copy(tis, fos);
                    }
                }
            }
        }
    }

    private static void copy(InputStream in, OutputStream out) throws IOException {
        byte[] buf = new byte[8192];
        int len;
        while ((len = in.read(buf)) >= 0) {
            out.write(buf, 0, len);
        }
    }

    private static String getExtension(String filename) {
        String lower = filename.toLowerCase();
        if (lower.endsWith(".tar.gz")) return ".tar.gz";
        if (lower.endsWith(".tar.bz2")) return ".tar.bz2";
        if (lower.endsWith(".tar.xz")) return ".tar.xz";
        int dot = lower.lastIndexOf('.');
        return dot < 0 ? null : lower.substring(dot);
    }

    private static String removeArchiveExtension(String filename) {
        String lower = filename.toLowerCase();
        if (lower.endsWith(".tar.gz")) return filename.substring(0, filename.length() - 7);
        if (lower.endsWith(".tar.bz2")) return filename.substring(0, filename.length() - 8);
        if (lower.endsWith(".tar.xz")) return filename.substring(0, filename.length() - 7);
        int dot = filename.lastIndexOf('.');
        return dot < 0 ? filename : filename.substring(0, dot);
    }

    private ObjectNode buildDefaultConfig(String programName) {
        ObjectNode config = mapper.createObjectNode();
        config.put("programName", programName);
        ObjectNode runtime = config.putObject("runtime");
        runtime.put("preRunScript", "RunCtrlSysModelSHT");
        runtime.put("simulinkModel", "Dll_Control_AFO_V8_2_R2019b.slx");
        runtime.put("stopTime", 30);
        config.putArray("outputs");
        return config;
    }

    private void writeProgramConfig(File taskDir, ProgramEntity entity) throws IOException {
        ObjectNode config = (entity.getConfigJson() != null)
                ? (ObjectNode) mapper.readTree(entity.getConfigJson())
                : buildDefaultConfig(entity.getName());
        config.put("programDir", taskDir.getAbsolutePath());
        File cfg = new File(taskDir, "program-config.json");
        mapper.writerWithDefaultPrettyPrinter().writeValue(cfg, config);
    }

    /**
     * 移除仿真程序资产
     */
    public void deleteProgram(String name, String version, String projectName) {
        try {
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(ProgramEntity.class, META_PREFIX);
            if (StringUtils.hasText(version) && !"null".equals(version)) {
                ProgramEntity queryMeta = queryMeta(name, version, projectName);
                String actualProjectName = projectName != null ? projectName : (queryMeta != null ? queryMeta.getProjectName() : null);
                String storagePath = buildStoragePath(actualProjectName, name, version);
                iginxClient.getDeleteClient().deleteMeasurement(storagePath);
                if (queryMeta != null && queryMeta.getTimestamp() != null) {
                    long timestamp = queryMeta.getTimestamp();
                    iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp - 1, timestamp + 1);
                }
                dataPermissionService.deleteByTablePrefix(storagePath);
                // 从项目的programs字段移除
                if (actualProjectName != null) {
                    try {
                        projectService.removeFromProject(actualProjectName, storagePath, "programs");
                    } catch (Exception e) {
                        log.error("从项目移除程序路径失败", e);
                    }
                }
                // 删除磁盘上的程序解压目录
                File programDir = getProgramDir(actualProjectName, name, version);
                if (programDir.exists()) {
                    deleteDirectory(programDir);
                    log.info("已删除程序目录: {}", programDir.getAbsolutePath());
                }
            } else {
                String actualProjectName = StringUtils.hasText(projectName) ? projectName : ProjectContext.getCurrentProject("unknown");
                List<ProgramEntity> queryMetas = queryMetaList(name, actualProjectName);
                List<String> storagePaths = queryMetas.stream()
                        .map(meta ->
                                buildStoragePath(meta.getProjectName(), meta.getName(), meta.getVersion())
                        )
                        .collect(Collectors.toList());
                iginxClient.getDeleteClient().deleteMeasurements(storagePaths);
                queryMetas.stream()
                        .map(ProgramEntity::getTimestamp)
                        .forEach(timestamp ->
                                iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp - 1, timestamp + 1)
                        );
                storagePaths.forEach(storagePath -> dataPermissionService.deleteByTablePrefix(storagePath));
                // 从项目的programs字段移除并删除磁盘目录
                for (ProgramEntity meta : queryMetas) {
                    String sp = buildStoragePath(meta.getProjectName(), meta.getName(), meta.getVersion());
                    try {
                        projectService.removeFromProject(meta.getProjectName(), sp, "programs");
                    } catch (Exception e) {
                        log.error("从项目移除程序路径失败: {}", sp, e);
                    }
                    File programDir = getProgramDir(meta.getProjectName(), meta.getName(), meta.getVersion());
                    if (programDir.exists()) {
                        deleteDirectory(programDir);
                        log.info("已删除程序目录: {}", programDir.getAbsolutePath());
                    }
                }
            }
        } catch (Exception e) {
            log.error("移除仿真程序资产失败", e);
        }
    }

    /**
     * 移除仿真程序资产（兼容旧版本）
     */
    public void deleteProgram(String name, String version) {
        deleteProgram(name, version, null);
    }

    public Result<Map<String, Object>> run(String name, String version, String stopTime, String fixedStep, String npCommand, String loadPower, String modelFile, String projectName) {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) return Result.error("程序不存在");
        entity.setStatus("RUNNING");
        entity.setLastError("");
        entity.setLastRunTime(System.currentTimeMillis());
        try {
            saveProgramMetadata(entity);
        } catch (Exception e) {
            log.error("保存运行状态失败", e);
        }

        String key = runtimeKey(entity);
        runtimeStatus.put(key, entity);
        new Thread(() -> doRun(key, entity, stopTime, fixedStep, npCommand, loadPower, modelFile), "program-run-" + key).start();

        Map<String, Object> data = new HashMap<>();
        data.put("status", "RUNNING");
        return Result.success("运行已启动", data);
    }

    public Result<Map<String, Object>> stop(String name, String version, String projectName) {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) return Result.error("程序不存在");
        String key = runtimeKey(entity);
        Process process = processMap.remove(key);
        if (process != null && process.isAlive()) {
            process.destroyForcibly();
        }
        entity.setStatus("STOPPED");
        entity.setLastError(null);
        try {
            saveProgramMetadata(entity);
        } catch (Exception e) {
            log.error("保存停止状态失败", e);
        }
        runtimeStatus.remove(key);
        Map<String, Object> data = new HashMap<>();
        data.put("status", "STOPPED");
        return Result.success("已停止", data);
    }

    private void doRun(String key, ProgramEntity entity, String stopTimeParam, String fixedStepParam, String npCommandParam, String loadPowerParam, String modelFileParam) {
        String taskId = "task_" + System.currentTimeMillis();
        File taskDir = new File(getTaskBaseDir(entity.getProjectName()), taskId);
        try {
            taskDir.mkdirs();
            byte[] archiveBytes = downloadFromIginx(entity.getStoragePath(), entity.getChunkCount(), entity.getFileMd5());
            File archiveFile = new File(taskDir, entity.getFileName());
            Files.write(archiveFile.toPath(), archiveBytes);
            extractArchive(archiveFile, taskDir);
            writeProgramConfig(taskDir, entity);

            File configFile = new File(taskDir, "program-config.json");
            if (!configFile.exists()) {
                entity.setStatus("ERROR");
                entity.setLastError("缺少 program-config.json");
                saveProgramMetadata(entity);
                return;
            }
            JsonNode config = mapper.readTree(configFile);
            JsonNode runtime = config.get("runtime");
            String preRunScript = runtime.path("preRunScript").asText("RunCtrlSysModelSHT");
            String modelFile = StringUtils.hasText(modelFileParam) ? modelFileParam : runtime.path("simulinkModel").asText("");
            int stopTime = StringUtils.hasText(stopTimeParam) ? Integer.parseInt(stopTimeParam) : runtime.path("stopTime").asInt(30);

            String programDir = findProgramDir(taskDir, preRunScript);
            if (modelFile.isEmpty()) {
                File programDirFile = new File(programDir);
                File[] slxFiles = programDirFile.listFiles((d, n) ->
                        n.toLowerCase().endsWith(".slx") && !n.toLowerCase().endsWith(".slxc"));
                if (slxFiles != null && slxFiles.length > 0) {
                    modelFile = slxFiles[0].getName();
                    log.info("自动检测 Simulink 模型: {}", modelFile);
                }
            }
            String shortTaskDir = getShortPath(taskDir);
            String shortProgramDir = getShortPath(new File(programDir));
            log.info("MATLAB 运行目录: 原始={}, 短路径={}", taskDir.getAbsolutePath(), shortTaskDir);
            log.info("MATLAB 程序目录: 原始={}, 短路径={}", programDir, shortProgramDir);
            File wrapper = new File(taskDir, "run_wrapper.m");
            writeWrapper(wrapper, shortTaskDir, shortProgramDir, preRunScript, modelFile, stopTime, fixedStepParam, npCommandParam, loadPowerParam);
            File oldCsv = new File(taskDir, "signals.csv");
            if (oldCsv.exists()) oldCsv.delete();

            ProcessBuilder pb = new ProcessBuilder();
            pb.directory(taskDir);
            pb.command("cmd", "/c", "chcp 65001 && matlab -batch \"cd('"
                    + escape(shortTaskDir) + "'); run_wrapper; exit;\" -nosplash -nodesktop");
            pb.redirectErrorStream(true);
            File logFile = new File(taskDir, "run.log");
            pb.redirectOutput(logFile);

            Process process = pb.start();
            entity.setLastLogPath(logFile.getAbsolutePath());
            try { saveProgramMetadata(entity); } catch (Exception ignored) {}
            processMap.put(key, process);
            boolean finished = process.waitFor(1200, TimeUnit.SECONDS);
            processMap.remove(key);
            if (!finished) {
                process.destroyForcibly();
                entity.setStatus("ERROR");
                entity.setLastError("运行超时");
                saveProgramMetadata(entity);
                return;
            }
            int exitCode = process.exitValue();
            String fullLog = readLastLines(logFile, 200);
            log.info("程序运行结束，退出码: {}，日志:\n{}", exitCode, fullLog);
            if (exitCode != 0) {
                String err = readLastLines(logFile, 20);
                entity.setStatus("ERROR");
                entity.setLastError("MATLAB 退出码 " + exitCode + ": " + err);
                saveProgramMetadata(entity);
                return;
            }

            File csv = new File(taskDir, "signals.csv");
            if (!csv.exists()) {
                entity.setStatus("ERROR");
                entity.setLastError("未生成 signals.csv");
                saveProgramMetadata(entity);
                return;
            }
            entity.setStatus("SUCCESS");
            entity.setLastResultCsv(csv.getAbsolutePath());
            entity.setLastResultDir(taskDir.getAbsolutePath());
            log.info("程序运行成功，结果文件: {}", csv.getAbsolutePath());

            generateResultFiles(taskDir, entity, modelFile, stopTimeParam, fixedStepParam, npCommandParam, loadPowerParam, logFile);

            saveProgramMetadata(entity);
        } catch (Exception e) {
            log.error("运行程序失败", e);
            entity.setStatus("ERROR");
            entity.setLastError(e.getMessage());
            try {
                saveProgramMetadata(entity);
            } catch (Exception ex) {
                log.error("保存运行状态失败", ex);
            }
        } finally {
            runtimeStatus.remove(key);
        }
    }

    private String findProgramDir(File dir, String scriptName) throws IOException {
        String name = scriptName.toLowerCase().endsWith(".m") ? scriptName : scriptName + ".m";
        File base = dir.getAbsoluteFile();
        try (java.util.stream.Stream<Path> paths = Files.walk(base.toPath())) {
            Path found = paths.filter(p -> p.toFile().isFile() && p.getFileName().toString().equalsIgnoreCase(name))
                    .findFirst()
                    .orElse(null);
            return found != null ? found.getParent().toString() : base.getAbsolutePath();
        }
    }

    private void writeWrapper(File f, String taskDir, String programDir, String preRun, String modelFile, int stopTime,
                              String fixedStep, String npCommand, String loadPower) throws IOException {
        StringBuilder sb = new StringBuilder();
        sb.append("cd('").append(escape(programDir)).append("');\n");
        if (StringUtils.hasText(npCommand)) {
            sb.append("NpReferenceRpm = ").append(npCommand).append(";\n");
        }
        if (StringUtils.hasText(loadPower)) {
            sb.append("MkpReferenceNm = ").append(loadPower).append(";\n");
        }
        if (StringUtils.hasText(fixedStep)) {
            sb.append("Ts = ").append(fixedStep).append(";\n");
        }
        sb.append("try\n");
        sb.append("    ").append(preRun).append(";\n");
        sb.append("catch ME\n");
        sb.append("    fid = fopen('error.txt', 'w');\n");
        sb.append("    fprintf(fid, '%s\\n', ME.message);\n");
        sb.append("    fclose(fid);\n");
        sb.append("    rethrow(ME);\n");
        sb.append("end\n");
        if (modelFile != null && !modelFile.isEmpty()) {
            String modelName = modelFile.replaceAll("\\.(slx|mdl)$", "");
            sb.append("try\n");
            sb.append("    load_system('").append(escape(modelName)).append("');\n");
            sb.append("    set_param('").append(escape(modelName)).append("', 'StopTime', '").append(stopTime).append("');\n");
            // okSignals tracks successfully added To Workspace variables
            sb.append("    okSignals = {};\n");
            // 3a. Add To Workspace blocks for blocks with output ports
            sb.append("    wsSignals = {\n");
            sb.append("        'Np',       '").append(modelName).append("/Turboshaft Engine Control System/Np';\n");
            sb.append("        'Ng',       '").append(modelName).append("/Turboshaft Engine Control System/Ng';\n");
            sb.append("        'NpDem',    '").append(modelName).append("/Turboshaft Engine Control System/NpDem';\n");
            sb.append("        'T45',      '").append(modelName).append("/Turboshaft Engine Control System/T45';\n");
            sb.append("        'Mkp',      '").append(modelName).append("/Turboshaft Engine Control System/Mkp';\n");
            sb.append("        'Wf_cmd',   '").append(modelName).append("/Fuel System/Wf_cmd';\n");
            sb.append("    };\n");
            sb.append("    for i = 1:size(wsSignals, 1)\n");
            sb.append("        try\n");
            sb.append("            sigName = wsSignals{i, 1};\n");
            sb.append("            blockPath = wsSignals{i, 2};\n");
            sb.append("            parent = get_param(blockPath, 'Parent');\n");
            sb.append("            srcName = get_param(blockPath, 'Name');\n");
            sb.append("            twName = ['ToWS_' sigName];\n");
            sb.append("            twPath = [parent '/' twName];\n");
            sb.append("            ph = get_param(blockPath, 'PortHandles');\n");
            sb.append("            if isempty(ph.Outport); continue; end\n");
            sb.append("            if getSimulinkBlockHandle(twPath) ~= -1; delete_block(twPath); end\n");
            sb.append("            pos = get_param(blockPath, 'Position');\n");
            sb.append("            newPos = [pos(3)+80, pos(2), pos(3)+120, pos(2)+30];\n");
            sb.append("            add_block('simulink/Sinks/To Workspace', twPath, ...\n");
            sb.append("                'Position', newPos, 'VariableName', sigName, ...\n");
            sb.append("                'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');\n");
            sb.append("            add_line(parent, [srcName '/1'], [twName '/1']);\n");
            sb.append("            okSignals{end+1} = sigName;\n");
            sb.append("        catch\n");
            sb.append("            try; delete_block(twPath); catch; end\n");
            sb.append("        end\n");
            sb.append("    end\n");
            // 3a2. CLP - Inport inside control system, add To Workspace inside subsystem
            sb.append("    try\n");
            sb.append("        clpPath = ['").append(modelName).append("'/Turboshaft Engine Control System/CLP'];\n");
            sb.append("        clpParent = get_param(clpPath, 'Parent');\n");
            sb.append("        clpName = get_param(clpPath, 'Name');\n");
            sb.append("        twName = 'ToWS_CLP'; twPath = [clpParent '/' twName];\n");
            sb.append("        if getSimulinkBlockHandle(twPath) ~= -1; delete_block(twPath); end\n");
            sb.append("        pos = get_param(clpPath, 'Position');\n");
            sb.append("        add_block('simulink/Sinks/To Workspace', twPath, 'Position', [pos(3)+80, pos(2), pos(3)+120, pos(2)+30], ...\n");
            sb.append("            'VariableName', 'CLP', 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');\n");
            sb.append("        add_line(clpParent, [clpName '/1'], [twName '/1']);\n");
            sb.append("        okSignals{end+1} = 'CLP';\n");
            sb.append("    catch\n");
            sb.append("        try; delete_block(twPath); catch; end\n");
            sb.append("    end\n");
            // 3b. Add From + To Workspace for Goto-tagged signals
            sb.append("    gotoSignals = {\n");
            sb.append("        'Np_fbk', 'Np_fbk'; 'Ng_fbk', 'Ng_fbk'; 'Mkp_fbk', 'Mkp_fbk'; 'T45_fbk', 'T45_fbk';\n");
            sb.append("        'Ngc', 'Ngc'; 'Wf_kgps', 'Wf_kgps'; 'WfProxyCmd', 'WfProxyCmd';\n");
            sb.append("        'Pt3_fbk', 'Pt3_fbk'; 'Tt3_fbk', 'Tt3_fbk';\n");
            sb.append("        'P1', 'P1'; 'T1', 'T1'; 'P45', 'P45'; 'P4', 'P4'; 'P5', 'P5'; 'T5', 'T5'; 'T4', 'T4';\n");
            sb.append("        'Oil_AirTemp_C', 'Oil_AirTemp_C'\n");
            sb.append("    };\n");
            sb.append("    for i = 1:size(gotoSignals, 1)\n");
            sb.append("        try\n");
            sb.append("            sigName = gotoSignals{i, 1}; gotoTag = gotoSignals{i, 2};\n");
            sb.append("            twName = ['ToWS_From_' sigName]; fromName = ['From_' sigName];\n");
            sb.append("            twPath = ['").append(modelName).append("' '/' twName]; fromPath = ['").append(modelName).append("' '/' fromName];\n");
            sb.append("            if getSimulinkBlockHandle(twPath) ~= -1; delete_block(twPath); end\n");
            sb.append("            if getSimulinkBlockHandle(fromPath) ~= -1; delete_block(fromPath); end\n");
            sb.append("            add_block('simulink/Signal Routing/From', fromPath, 'GotoTag', gotoTag, 'Position', [100, 100+i*40, 200, 130+i*40]);\n");
            sb.append("            add_block('simulink/Sinks/To Workspace', twPath, 'VariableName', sigName, ...\n");
            sb.append("                'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1', 'Position', [250, 100+i*40, 350, 130+i*40]);\n");
            sb.append("            add_line('").append(modelName).append("', [fromName '/1'], [twName '/1']);\n");
            sb.append("            okSignals{end+1} = sigName;\n");
            sb.append("        catch\n");
            sb.append("            try; delete_block(twPath); catch; end\n");
            sb.append("            try; delete_block(fromPath); catch; end\n");
            sb.append("        end\n");
            sb.append("    end\n");
            // 3c1. Fuel System Wf output via subsystem port handles
            sb.append("    try\n");
            sb.append("        fsPath = ['").append(modelName).append("'/Fuel System'];\n");
            sb.append("        fsPH = get_param(fsPath, 'PortHandles');\n");
            sb.append("        fsPos = get_param(fsPath, 'Position');\n");
            sb.append("        twName = 'ToWS_Wf'; twPath = ['").append(modelName).append("' '/' twName];\n");
            sb.append("        if getSimulinkBlockHandle(twPath) ~= -1; delete_block(twPath); end\n");
            sb.append("        add_block('simulink/Sinks/To Workspace', twPath, 'Position', [fsPos(3)+80, fsPos(2), fsPos(3)+120, fsPos(2)+30], ...\n");
            sb.append("            'VariableName', 'Wf', 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');\n");
            sb.append("        add_line('").append(modelName).append("', fsPH.Outport(1), get_param(twPath, 'PortHandles').Inport(1));\n");
            sb.append("        okSignals{end+1} = 'Wf';\n");
            sb.append("    catch\n");
            sb.append("        try; delete_block(twPath); catch; end\n");
            sb.append("    end\n");
            // 3c. Air system outputs via subsystem port handles
            sb.append("    try\n");
            sb.append("        airBlocks = find_system('").append(modelName).append("', 'RegExp', 'on', 'Name', 'G0[1-8]_.*W_kgps');\n");
            sb.append("        airParent = '';\n");
            sb.append("        for i = 1:numel(airBlocks)\n");
            sb.append("            p = get_param(airBlocks{i}, 'Parent');\n");
            sb.append("            if strcmp(get_param(p, 'Parent'), '").append(modelName).append("')\n");
            sb.append("                airParent = p; break;\n");
            sb.append("            end\n");
            sb.append("        end\n");
            sb.append("        if ~isempty(airParent)\n");
            sb.append("            subPH = get_param(airParent, 'PortHandles');\n");
            sb.append("            airOuts = find_system(airParent, 'SearchDepth', 1, 'BlockType', 'Outport');\n");
            sb.append("            subPos = get_param(airParent, 'Position');\n");
            sb.append("            for i = 1:numel(airOuts)\n");
            sb.append("                try\n");
            sb.append("                    outName = get_param(airOuts{i}, 'Name');\n");
            sb.append("                    twName = ['ToWS_' outName]; twPath = ['").append(modelName).append("' '/' twName];\n");
            sb.append("                    if getSimulinkBlockHandle(twPath) ~= -1; delete_block(twPath); end\n");
            sb.append("                    yOff = subPos(2) + i * 35;\n");
            sb.append("                    add_block('simulink/Sinks/To Workspace', twPath, 'Position', [subPos(3)+80, yOff, subPos(3)+120, yOff+30], ...\n");
            sb.append("                        'VariableName', outName, 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');\n");
            sb.append("                    add_line('").append(modelName).append("', subPH.Outport(i), get_param(twPath, 'PortHandles').Inport(1));\n");
            sb.append("                    okSignals{end+1} = outName;\n");
            sb.append("                catch\n");
            sb.append("                    try; delete_block(twPath); catch; end\n");
            sb.append("                end\n");
            sb.append("            end\n");
            sb.append("        end\n");
            sb.append("    catch\n");
            sb.append("    end\n");
            // 3d. Oil subsystem outputs via subsystem port handles (find by 28 outports)
            sb.append("    try\n");
            sb.append("        allSubs = find_system('").append(modelName).append("', 'SearchDepth', 1, 'BlockType', 'SubSystem');\n");
            sb.append("        oilSys = '';\n");
            sb.append("        for i = 1:numel(allSubs)\n");
            sb.append("            subOuts = find_system(allSubs{i}, 'SearchDepth', 1, 'BlockType', 'Outport');\n");
            sb.append("            if numel(subOuts) == 28; oilSys = allSubs{i}; break; end\n");
            sb.append("        end\n");
            sb.append("        if ~isempty(oilSys)\n");
            sb.append("            oilPH = get_param(oilSys, 'PortHandles');\n");
            sb.append("            oilOuts = find_system(oilSys, 'SearchDepth', 1, 'BlockType', 'Outport');\n");
            sb.append("            oilPos = get_param(oilSys, 'Position');\n");
            sb.append("            oilVarNames = {'Q_BearingA','Q_BearingB','Q_AirOil','Q_Accessory', ...\n");
            sb.append("                'QA','QB','PA','PB','ToutA','ToutB', ...\n");
            sb.append("                'QretA','QretB','QgenA','QgenB', ...\n");
            sb.append("                'FuelOilCooler_Q','FuelOilCooler_FuelTout', ...\n");
            sb.append("                'AirOilCooler_Pin_Pa','AirOilCooler_Pout_Pa', ...\n");
            sb.append("                'FuelOilCooler_Pin_Pa','FuelOilCooler_Pout_Pa', ...\n");
            sb.append("                'CavityState8_PaK','SealLeak4_kgps','VentFlow3_kgps', ...\n");
            sb.append("                'SealDeltaP4_Pa','VentDeltaP2_Pa','MassResidual2_kgps', ...\n");
            sb.append("                'FuelOil2_ToutC_QkW','AirOil2_ToutC_QkW'};\n");
            sb.append("            for i = 1:numel(oilOuts)\n");
            sb.append("                try\n");
            sb.append("                    varName = oilVarNames{i};\n");
            sb.append("                    twName = ['ToWS_' varName]; twPath = ['").append(modelName).append("' '/' twName];\n");
            sb.append("                    if getSimulinkBlockHandle(twPath) ~= -1; delete_block(twPath); end\n");
            sb.append("                    yOff = oilPos(2) + i * 25;\n");
            sb.append("                    add_block('simulink/Sinks/To Workspace', twPath, 'Position', [oilPos(3)+80, yOff, oilPos(3)+120, yOff+20], ...\n");
            sb.append("                        'VariableName', varName, 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');\n");
            sb.append("                    add_line('").append(modelName).append("', oilPH.Outport(i), get_param(twPath, 'PortHandles').Inport(1));\n");
            sb.append("                    okSignals{end+1} = varName;\n");
            sb.append("                catch\n");
            sb.append("                    try; delete_block(twPath); catch; end\n");
            sb.append("                end\n");
            sb.append("            end\n");
            sb.append("        end\n");
            sb.append("    catch\n");
            sb.append("    end\n");
            // 4. Run simulation
            sb.append("    simOut = sim('").append(escape(modelName)).append("', 'ReturnWorkspaceOutputs', 'on', 'StopTime', '").append(stopTime).append("');\n");
            sb.append("    save('").append(escape(taskDir)).append("/simOut.mat', 'simOut');\n");
            sb.append("    tout = simOut.tout;\n");
            sb.append("    colNames = {'time'};\n");
            sb.append("    colData = tout;\n");
            // 5. Extract from simOut - timeseries and numeric
            sb.append("    tsVars = {'Pt1','Tt1','Pt3','Tt3','Pt45','Tt45','Pt5','Tt5', ...\n");
            sb.append("              'HPC_T4_out','HPC_P4_out1','HPC_T5_out1', ...\n");
            sb.append("              'Np','Ng','NpDem','T45','Mkp','Wf_cmd','Wf','CLP', ...\n");
            sb.append("              'G01_GT1_IN_W_kgps','G02_GT1_OUT_W_kgps','G03_GT2_IN_W_kgps', ...\n");
            sb.append("              'G04_GT2_OUT_W_kgps','G05_PT1_IN_ROOT_W_kgps','G06_PT1_OUT_ROOT_W_kgps', ...\n");
            sb.append("              'G07_PT2_IN_TIP_W_kgps','G08_PT2_OUT_TIP_W_kgps', ...\n");
            sb.append("              'Np_fbk','Ng_fbk','Mkp_fbk','T45_fbk', ...\n");
            sb.append("              'Ngc','Wf_kgps','WfProxyCmd', ...\n");
            sb.append("              'Pt3_fbk','Tt3_fbk','P1','T1','P45','P4','P5','T5','T4', ...\n");
            sb.append("              'Oil_AirTemp_C'};\n");
            sb.append("    for i = 1:length(tsVars)\n");
            sb.append("        try\n");
            sb.append("            v = simOut.(tsVars{i});\n");
            sb.append("            if isa(v, 'timeseries') && size(v.Data,2) == 1\n");
            sb.append("                colNames{end+1} = tsVars{i}; colData = [colData, v.Data];\n");
            sb.append("            elseif isnumeric(v) && size(v,1) == length(tout) && size(v,2) == 1\n");
            sb.append("                colNames{end+1} = tsVars{i}; colData = [colData, v];\n");
            sb.append("            elseif isa(v, 'Simulink.SimulationData.Dataset')\n");
            sb.append("                for j = 1:v.numElements\n");
            sb.append("                    elem = v.get(j);\n");
            sb.append("                    if isa(elem, 'timeseries') && size(elem.Data,2) == 1\n");
            sb.append("                        if v.numElements == 1; colNames{end+1} = tsVars{i};\n");
            sb.append("                        else; colNames{end+1} = sprintf('%s_%d', tsVars{i}, j); end\n");
            sb.append("                        colData = [colData, elem.Data];\n");
            sb.append("                    end\n");
            sb.append("                end\n");
            sb.append("            end\n");
            sb.append("        catch\n");
            sb.append("        end\n");
            sb.append("    end\n");
            // 6. Extract oil variables (multi-dimensional) from simOut
            sb.append("    oilVars = {'Q_BearingA','Q_BearingB','Q_AirOil','Q_Accessory', ...\n");
            sb.append("        'QA','QB','PA','PB','ToutA','ToutB', ...\n");
            sb.append("        'QretA','QretB','QgenA','QgenB', ...\n");
            sb.append("        'FuelOilCooler_Q','FuelOilCooler_FuelTout', ...\n");
            sb.append("        'AirOilCooler_Pin_Pa','AirOilCooler_Pout_Pa', ...\n");
            sb.append("        'FuelOilCooler_Pin_Pa','FuelOilCooler_Pout_Pa', ...\n");
            sb.append("        'CavityState8_PaK','SealLeak4_kgps','VentFlow3_kgps', ...\n");
            sb.append("        'SealDeltaP4_Pa','VentDeltaP2_Pa','MassResidual2_kgps', ...\n");
            sb.append("        'FuelOil2_ToutC_QkW','AirOil2_ToutC_QkW'};\n");
            sb.append("    for i = 1:length(oilVars)\n");
            sb.append("        try\n");
            sb.append("            v = simOut.(oilVars{i});\n");
            sb.append("            if isa(v, 'timeseries')\n");
            sb.append("                d = v.Data;\n");
            sb.append("                if size(d,1) == length(tout)\n");
            sb.append("                    if size(d,2) == 1\n");
            sb.append("                        if ~any(strcmp(colNames, oilVars{i}))\n");
            sb.append("                            colNames{end+1} = oilVars{i}; colData = [colData, d];\n");
            sb.append("                        end\n");
            sb.append("                    else\n");
            sb.append("                        for j = 1:size(d,2)\n");
            sb.append("                            cn = sprintf('%s_%d', oilVars{i}, j);\n");
            sb.append("                            if ~any(strcmp(colNames, cn))\n");
            sb.append("                                colNames{end+1} = cn; colData = [colData, d(:,j)];\n");
            sb.append("                            end\n");
            sb.append("                        end\n");
            sb.append("                    end\n");
            sb.append("                end\n");
            sb.append("            elseif isnumeric(v) && size(v,1) == length(tout)\n");
            sb.append("                if size(v,2) == 1\n");
            sb.append("                    if ~any(strcmp(colNames, oilVars{i}))\n");
            sb.append("                        colNames{end+1} = oilVars{i}; colData = [colData, v];\n");
            sb.append("                    end\n");
            sb.append("                else\n");
            sb.append("                    for j = 1:size(v,2)\n");
            sb.append("                        cn = sprintf('%s_%d', oilVars{i}, j);\n");
            sb.append("                        if ~any(strcmp(colNames, cn))\n");
            sb.append("                            colNames{end+1} = cn; colData = [colData, v(:,j)];\n");
            sb.append("                        end\n");
            sb.append("                    end\n");
            sb.append("                end\n");
            sb.append("            end\n");
            sb.append("        catch\n");
            sb.append("        end\n");
            sb.append("    end\n");
            // 6b. Also check workspace variables from To Workspace blocks
            sb.append("    for i = 1:length(okSignals)\n");
            sb.append("        try\n");
            sb.append("            sigName = okSignals{i};\n");
            sb.append("            if exist(sigName, 'var') == 1\n");
            sb.append("                v = eval(sigName);\n");
            sb.append("                if size(v,2) >= 2 && ~any(strcmp(colNames, sigName))\n");
            sb.append("                    colNames{end+1} = sigName; colData = [colData, v(:,2)];\n");
            sb.append("                end\n");
            sb.append("            end\n");
            sb.append("        catch\n");
            sb.append("        end\n");
            sb.append("    end\n");
            // 6c. Extract workspace scalar variables (limits, error) as constant columns
            sb.append("    wsScalars = {'NgMax','T45Max','MkpMax','WfMax','WfMin','errmax'};\n");
            sb.append("    for i = 1:length(wsScalars)\n");
            sb.append("        try\n");
            sb.append("            sn = wsScalars{i};\n");
            sb.append("            if exist(sn, 'var') == 1\n");
            sb.append("                v = eval(sn);\n");
            sb.append("                if isnumeric(v) && isscalar(v) && ~any(strcmp(colNames, sn))\n");
            sb.append("                    colNames{end+1} = sn; colData = [colData, repmat(v, length(tout), 1)];\n");
            sb.append("                end\n");
            sb.append("            end\n");
            sb.append("        catch\n");
            sb.append("        end\n");
            sb.append("    end\n");
            // 7. Scan simOut fields for any remaining numeric outputs
            sb.append("    try\n");
            sb.append("        allNames = fieldnames(simOut);\n");
            sb.append("        for i = 1:numel(allNames)\n");
            sb.append("            name = allNames{i};\n");
            sb.append("            try\n");
            sb.append("                v = simOut.(name);\n");
            sb.append("                if isnumeric(v) && size(v,1) == length(tout) && ~any(strcmp(colNames, name))\n");
            sb.append("                    if size(v,2) == 1\n");
            sb.append("                        colNames{end+1} = name; colData = [colData, v];\n");
            sb.append("                    else\n");
            sb.append("                        for j = 1:size(v,2)\n");
            sb.append("                            cn = sprintf('%s_%d', name, j);\n");
            sb.append("                            if ~any(strcmp(colNames, cn))\n");
            sb.append("                                colNames{end+1} = cn; colData = [colData, v(:,j)];\n");
            sb.append("                            end\n");
            sb.append("                        end\n");
            sb.append("                    end\n");
            sb.append("                end\n");
            sb.append("            catch\n");
            sb.append("            end\n");
            sb.append("        end\n");
            sb.append("    catch\n");
            sb.append("    end\n");
            sb.append("    T = array2table(colData, 'VariableNames', colNames);\n");
            sb.append("    writetable(T, '").append(escape(taskDir)).append("/signals.csv');\n");
            sb.append("    save('").append(escape(taskDir)).append("/signals.mat', 'T');\n");
            sb.append("    close_system('").append(escape(modelName)).append("', 0);\n");
            sb.append("catch ME\n");
            sb.append("    try; close_system('").append(escape(modelName)).append("', 0); catch; end\n");
            sb.append("    fid = fopen('").append(escape(taskDir)).append("/error.txt', 'w');\n");
            sb.append("    fprintf(fid, '%s\\n', ME.message);\n");
            sb.append("    fclose(fid);\n");
            sb.append("    rethrow(ME);\n");
            sb.append("end\n");
        }
        Files.write(f.toPath(), sb.toString().getBytes(StandardCharsets.UTF_8));
    }

    private void generateResultFiles(File taskDir, ProgramEntity entity, String modelFile,
                                     String stopTime, String fixedStep, String npCommand, String loadPower,
                                     File logFile) {
        try {
            // metadata.json
            ObjectNode metadata = mapper.createObjectNode();
            metadata.put("softwareVersion", "AFO V1.0");
            metadata.put("modelPath", modelFile != null ? modelFile : "");
            metadata.put("modelHash", "");
            metadata.put("matlabVersion", "R2019b");
            metadata.put("solver", "ode4 (Runge-Kutta)");
            metadata.put("fixedStep", fixedStep != null && !fixedStep.isEmpty() ? fixedStep : "0.025");
            metadata.put("stopTime", stopTime != null && !stopTime.isEmpty() ? stopTime : "30");
            metadata.put("signalDictVersion", "1.0");
            metadata.put("runStatus", entity.getStatus());
            metadata.put("runError", entity.getLastError() != null ? entity.getLastError() : "");
            metadata.put("runTimestamp", entity.getLastRunTime() != null ? entity.getLastRunTime() : System.currentTimeMillis());
            metadata.put("exportTime", new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX").format(new Date()));
            Files.write(new File(taskDir, "metadata.json").toPath(),
                    mapper.writerWithDefaultPrettyPrinter().writeValueAsBytes(metadata));

            // scenario.json
            ObjectNode scenario = mapper.createObjectNode();
            scenario.put("stopTime", stopTime != null && !stopTime.isEmpty() ? stopTime : "30");
            scenario.put("fixedStep", fixedStep != null && !fixedStep.isEmpty() ? fixedStep : "0.025");
            scenario.put("npCommand", npCommand != null && !npCommand.isEmpty() ? npCommand : "20800");
            scenario.put("loadPower", loadPower != null && !loadPower.isEmpty() ? loadPower : "2176600");
            scenario.put("modelFile", modelFile != null ? modelFile : "");
            ObjectNode defaults = scenario.putObject("defaults");
            defaults.put("Np0", 20800);
            defaults.put("Ng0", 38000);
            defaults.put("Wf0", 0.1519140445);
            defaults.put("A80", 0.10573);
            defaults.put("power0", 2176600);
            defaults.put("Ts", 0.025);
            Files.write(new File(taskDir, "scenario.json").toPath(),
                    mapper.writerWithDefaultPrettyPrinter().writeValueAsBytes(scenario));

            // events.json — basic alert detection from CSV
            File csvFile = new File(taskDir, "signals.csv");
            List<ObjectNode> events = new ArrayList<>();
            if (csvFile.exists()) {
                List<String[]> rows = new ArrayList<>();
                try (BufferedReader br = Files.newBufferedReader(csvFile.toPath(), StandardCharsets.UTF_8)) {
                    String line;
                    while ((line = br.readLine()) != null) {
                        rows.add(line.split(","));
                    }
                }
                if (!rows.isEmpty()) {
                    String[] headers = rows.remove(0);
                    Map<String, Integer> colIdx = new HashMap<>();
                    for (int i = 0; i < headers.length; i++) colIdx.put(headers[i].trim(), i);

                    String[][] alertRules = {
                        {"HPC_T4_out", "1400", "K", "燃气涡轮后温度超限"},
                        {"Pt3", "3500000", "Pa", "压气机出口压力超限"},
                        {"Pt45", "1000000", "Pa", "涡轮后压力超限"}
                    };
                    for (String[] rule : alertRules) {
                        String col = rule[0];
                        double limit = Double.parseDouble(rule[1]);
                        String unit = rule[2];
                        String desc = rule[3];
                        if (!colIdx.containsKey(col)) continue;
                        int ci = colIdx.get(col);
                        for (int i = 0; i < rows.size(); i++) {
                            try {
                                double v = Double.parseDouble(rows.get(i)[ci].trim());
                                if (v >= limit) {
                                    ObjectNode ev = mapper.createObjectNode();
                                    ev.put("time", Double.parseDouble(rows.get(i)[0].trim()));
                                    ev.put("level", "一级");
                                    ev.put("signal", col);
                                    ev.put("value", v);
                                    ev.put("limit", limit);
                                    ev.put("unit", unit);
                                    ev.put("desc", col + " " + desc + " — " + col + "=" + String.format("%.1f", v) + unit + " >= " + (int)limit + unit);
                                    events.add(ev);
                                    break;
                                }
                            } catch (NumberFormatException ignored) {}
                        }
                    }
                }
            }
            Files.write(new File(taskDir, "events.json").toPath(),
                    mapper.writerWithDefaultPrettyPrinter().writeValueAsBytes(events));

            // run.log — copy if not already in taskDir
            File runLogInTask = new File(taskDir, "run.log");
            if (logFile != null && logFile.exists() && !runLogInTask.exists()) {
                Files.copy(logFile.toPath(), runLogInTask.toPath());
            }

            log.info("结果文件已生成: metadata.json, scenario.json, events.json, run.log");
        } catch (Exception e) {
            log.error("生成结果文件失败", e);
        }
    }

    public byte[] downloadResultPackage(String name, String version, String projectName) throws Exception {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) throw new Exception("程序不存在");
        String resultDirPath = entity.getLastResultDir();
        if (resultDirPath == null && entity.getLastResultCsv() != null) {
            resultDirPath = new File(entity.getLastResultCsv()).getParent();
        }
        if (resultDirPath == null) throw new Exception("无运行结果目录，请先运行仿真");
        File resultDir = new File(resultDirPath);
        if (!resultDir.exists()) throw new Exception("结果目录不存在: " + resultDir.getAbsolutePath());

        // 如果 metadata.json 不存在，说明是旧运行结果，补充生成
        File metadataFile = new File(resultDir, "metadata.json");
        if (!metadataFile.exists()) {
            File logFile = entity.getLastLogPath() != null ? new File(entity.getLastLogPath()) : null;
            generateResultFiles(resultDir, entity, "", "", "", "", "", logFile);
        }

        String ts = new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new Date());
        String folderName = "Result_" + ts;

        java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
        try (java.util.zip.ZipOutputStream zos = new java.util.zip.ZipOutputStream(baos)) {
            String[] fileNames = {"metadata.json", "scenario.json", "signals.mat", "signals.csv", "events.json", "run.log", "overview.png"};
            for (String fn : fileNames) {
                File f = new File(resultDir, fn);
                if (f.exists()) {
                    zos.putNextEntry(new java.util.zip.ZipEntry(folderName + "/" + fn));
                    Files.copy(f.toPath(), zos);
                    zos.closeEntry();
                }
            }
        }
        return baos.toByteArray();
    }

    public void uploadOverview(String name, String version, String projectName, byte[] pngData) throws Exception {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) throw new Exception("程序不存在");
        String resultDirPath = entity.getLastResultDir();
        if (resultDirPath == null && entity.getLastResultCsv() != null) {
            resultDirPath = new File(entity.getLastResultCsv()).getParent();
        }
        if (resultDirPath == null) throw new Exception("无运行结果目录，请先运行仿真");
        File resultDir = new File(resultDirPath);
        if (!resultDir.exists()) throw new Exception("结果目录不存在: " + resultDir.getAbsolutePath());
        File overviewFile = new File(resultDir, "overview.png");
        Files.write(overviewFile.toPath(), pngData);
        log.info("overview.png 已保存到结果目录: {}", overviewFile.getAbsolutePath());
    }

    public byte[] downloadSignalFile(String name, String version, String format, String projectName) throws Exception {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) throw new Exception("程序不存在");
        String resultDirPath = entity.getLastResultDir();
        if (resultDirPath == null && entity.getLastResultCsv() != null) {
            resultDirPath = new File(entity.getLastResultCsv()).getParent();
        }
        if (resultDirPath == null) throw new Exception("无运行结果目录，请先运行仿真");
        File resultDir = new File(resultDirPath);
        if (!resultDir.exists()) throw new Exception("结果目录不存在: " + resultDir.getAbsolutePath());

        String fileName = "mat".equalsIgnoreCase(format) ? "signals.mat" : "signals.csv";
        File signalFile = new File(resultDir, fileName);
        if (!signalFile.exists()) throw new Exception("信号文件不存在: " + fileName + "，请先运行仿真");
        return Files.readAllBytes(signalFile.toPath());
    }

    private byte[] downloadFromIginx(String storagePath, Integer chunkCount, String expectedMd5) throws Exception {
        if (storagePath == null || chunkCount == null || chunkCount <= 0) {
            throw new Exception("IGinX 存储信息不完整");
        }
        SimpleQuery query = SimpleQuery.builder()
                .addMeasurement(storagePath)
                .endKey(Long.MAX_VALUE)
                .build();
        IginXTable table = iginxClient.getQueryClient().query(query);
        if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) {
            throw new Exception("未从 IGinX 找到程序包数据: " + storagePath);
        }
        TreeMap<Integer, byte[]> chunkMap = new TreeMap<>();
        for (IginXRecord record : table.getRecords()) {
            Long timestamp = record.getKey();
            Map<String, Object> valuesMap = record.getValues();
            Object value = valuesMap.get(storagePath);
            if (value instanceof byte[]) {
                chunkMap.put(timestamp.intValue(), (byte[]) value);
            } else if (value != null) {
                chunkMap.put(timestamp.intValue(), value.toString().getBytes(StandardCharsets.UTF_8));
            }
        }
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        for (int i = 0; i < chunkCount; i++) {
            byte[] chunk = chunkMap.get(i);
            if (chunk == null) throw new Exception("程序包数据不完整，缺少第 " + i + " 块");
            baos.write(chunk);
        }
        byte[] data = baos.toByteArray();
        if (expectedMd5 != null && !expectedMd5.isEmpty()) {
            String actual = calculateMD5(data);
            if (!actual.equalsIgnoreCase(expectedMd5)) {
                throw new Exception("程序包 MD5 校验失败");
            }
        }
        return data;
    }

    private String escape(String s) {
        return s.replace("\\", "\\\\").replace("'", "''");
    }

    private String getShortPath(File file) {
        if (!file.exists()) return file.getAbsolutePath();
        try {
            Process p = new ProcessBuilder("cmd", "/c", "for %I in (\""
                    + file.getAbsolutePath() + "\") do @echo %~sI").redirectErrorStream(true).start();
            java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[1024];
            int n;
            while ((n = p.getInputStream().read(buf)) != -1) baos.write(buf, 0, n);
            p.waitFor(5, TimeUnit.SECONDS);
            String output = new String(baos.toByteArray(), StandardCharsets.UTF_8).trim();
            if (!output.isEmpty() && output.matches("^[A-Za-z]:\\\\.*")) {
                return output;
            }
        } catch (Exception e) {
            log.warn("获取短路径失败: {}", file.getAbsolutePath(), e);
        }
        return file.getAbsolutePath();
    }

    public Result<Map<String, Object>> results(String name, String version, String projectName) {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) return Result.error("程序不存在");
        Map<String, Object> data = new HashMap<>();
        data.put("status", entity.getStatus());
        data.put("lastError", entity.getLastError());
        data.put("lastRunTime", entity.getLastRunTime());
        if (entity.getLastLogPath() != null) {
            File logFile = new File(entity.getLastLogPath());
            if (logFile.exists()) {
                try {
                    String logContent = new String(Files.readAllBytes(logFile.toPath()), Charset.forName("GBK"));
                    if (logContent.length() > 20000) {
                        logContent = logContent.substring(logContent.length() - 20000);
                    }
                    data.put("runLog", logContent);
                } catch (Exception e) {
                    log.error("读取运行日志失败", e);
                }
            }
        }
        if (entity.getLastResultCsv() != null) {
            File csv = new File(entity.getLastResultCsv());
            if (csv.exists()) {
                try {
                    List<String[]> rows = new ArrayList<>();
                    try (BufferedReader br = Files.newBufferedReader(csv.toPath(), StandardCharsets.UTF_8)) {
                        String line;
                        while ((line = br.readLine()) != null) {
                            rows.add(line.split(","));
                        }
                    }
                    List<String> headers = new ArrayList<>();
                    if (!rows.isEmpty()) headers.addAll(Arrays.asList(rows.remove(0)));
                    data.put("headers", headers);
                    data.put("rows", rows);
                } catch (Exception e) {
                    log.error("读取结果CSV失败", e);
                    data.put("lastError", "读取CSV失败: " + e.getMessage());
                }
            }
        }
        return Result.success(data);
    }

    public Result<ProgramEntity> updateConfig(String name, String version, String configJson, String projectName) {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) return Result.error("程序不存在");
        try {
            mapper.readTree(configJson);
            entity.setConfigJson(configJson);
            saveProgramMetadata(entity);
            return Result.success("配置更新成功", entity);
        } catch (Exception e) {
            return Result.error("配置更新失败: " + e.getMessage());
        }
    }

    public Map<String, Object> getProgramFiles(String name, String version, String projectName) {
        Map<String, Object> result = new LinkedHashMap<>();
        File programDir = getProgramDir(
                projectName != null ? projectName : ProjectContext.getCurrentProject("unknown"),
                name, version);
        if (!programDir.exists() || !programDir.isDirectory()) {
            result.put("found", false);
            result.put("message", "程序目录不存在: " + programDir.getAbsolutePath());
            return result;
        }
        result.put("found", true);
        result.put("programDir", programDir.getAbsolutePath());

        List<String> modelFiles = new ArrayList<>();
        List<String> scriptFiles = new ArrayList<>();
        List<String> mapFiles = new ArrayList<>();
        List<String> headerFiles = new ArrayList<>();
        List<String> dllFiles = new ArrayList<>();
        List<String> otherFiles = new ArrayList<>();

        scanProgramDir(programDir, programDir, modelFiles, scriptFiles, mapFiles, headerFiles, dllFiles, otherFiles);

        // 如果所有文件都在同一个子目录下，则将 programDir 调整为该子目录
        List<List<String>> allLists = Arrays.asList(modelFiles, scriptFiles, mapFiles, headerFiles, dllFiles, otherFiles);
        String commonPrefix = null;
        boolean hasCommonPrefix = true;
        for (List<String> list : allLists) {
            for (String path : list) {
                int slashIdx = path.indexOf('/');
                if (slashIdx < 0) {
                    hasCommonPrefix = false;
                    break;
                }
                String prefix = path.substring(0, slashIdx);
                if (commonPrefix == null) {
                    commonPrefix = prefix;
                } else if (!commonPrefix.equals(prefix)) {
                    hasCommonPrefix = false;
                    break;
                }
            }
            if (!hasCommonPrefix) break;
        }
        if (hasCommonPrefix && commonPrefix != null) {
            File subDir = new File(programDir, commonPrefix);
            if (subDir.isDirectory()) {
                programDir = subDir;
                result.put("programDir", programDir.getAbsolutePath());
                String prefix = commonPrefix + "/";
                for (List<String> list : allLists) {
                    for (int i = 0; i < list.size(); i++) {
                        list.set(i, list.get(i).substring(prefix.length()));
                    }
                }
            }
        }

        result.put("modelFiles", modelFiles);
        result.put("scriptFiles", scriptFiles);
        result.put("mapFiles", mapFiles);
        result.put("headerFiles", headerFiles);
        result.put("dllFiles", dllFiles);
        result.put("otherFiles", otherFiles);

        Map<String, Object> params = parseProgramParams(programDir, scriptFiles);
        if (params.get("modelName") != null && !((String)params.get("modelName")).isEmpty()) {
            String mn = (String)params.get("modelName");
            for (String mf : modelFiles) {
                if (mf.startsWith(mn + ".") || mf.equals(mn)) {
                    params.put("modelFile", mf);
                    break;
                }
            }
        }
        if (!params.containsKey("modelFile") && !modelFiles.isEmpty()) {
            params.put("modelFile", modelFiles.get(0));
        }
        result.put("params", params);
        return result;
    }

    private Map<String, Object> parseProgramParams(File programDir, List<String> scriptFiles) {
        Map<String, Object> params = new LinkedHashMap<>();
        String stopTime = null;
        String fixedStep = null;
        String npCommand = null;
        String loadPower = null;
        String modelName = null;
        String ngReferenceRpm = null;
        String wfReferenceKgps = null;
        String t45Max = null;
        String mkpMax = null;
        String wfMax = null;
        String wfMin = null;
        String wfRateLim = null;
        String ngMax = null;

        for (String relPath : scriptFiles) {
            File scriptFile = new File(programDir, relPath);
            try {
                String content = new String(Files.readAllBytes(scriptFile.toPath()), StandardCharsets.UTF_8);

                if (relPath.endsWith("RunCtrlSysModelSHT.m")) {
                    java.util.regex.Matcher m;

                    m = java.util.regex.Pattern.compile(
                            "NpReferenceRpm\\s*=\\s*([0-9.]+)").matcher(content);
                    if (m.find()) npCommand = m.group(1);

                    m = java.util.regex.Pattern.compile(
                            "NgReferenceRpm\\s*=\\s*([0-9.]+)").matcher(content);
                    if (m.find()) ngReferenceRpm = m.group(1);

                    m = java.util.regex.Pattern.compile(
                            "MkpReferenceNm\\s*=\\s*([0-9.]+)").matcher(content);
                    if (m.find()) loadPower = m.group(1);

                    m = java.util.regex.Pattern.compile(
                            "WfReferenceKgps\\s*=\\s*([0-9.]+)").matcher(content);
                    if (m.find()) wfReferenceKgps = m.group(1);

                    m = java.util.regex.Pattern.compile(
                            "Ts\\s*=\\s*([0-9.]+)").matcher(content);
                    if (m.find()) fixedStep = m.group(1);

                    m = java.util.regex.Pattern.compile(
                            "T45Max\\s*=\\s*([0-9.]+)").matcher(content);
                    if (m.find()) t45Max = m.group(1);

                    m = java.util.regex.Pattern.compile(
                            "MkpMax\\s*=\\s*([0-9.]+)").matcher(content);
                    if (m.find()) mkpMax = m.group(1);

                    m = java.util.regex.Pattern.compile(
                            "WfMax\\s*=\\s*WfReferenceKgps\\*([0-9.]+)").matcher(content);
                    if (m.find()) wfMax = m.group(1);

                    m = java.util.regex.Pattern.compile(
                            "WfMin\\s*=\\s*WfReferenceKgps\\*([0-9.]+)").matcher(content);
                    if (m.find()) wfMin = m.group(1);

                    m = java.util.regex.Pattern.compile(
                            "WfRateLim\\s*=\\s*([0-9.]+)").matcher(content);
                    if (m.find()) wfRateLim = m.group(1);

                    m = java.util.regex.Pattern.compile(
                            "NgMax\\s*=\\s*NgReferenceRpm\\*([0-9.]+)").matcher(content);
                    if (m.find()) ngMax = m.group(1);
                }

                if (relPath.endsWith("configure_afo_v1disp_reference_point.m")) {
                    java.util.regex.Matcher m = java.util.regex.Pattern.compile(
                            "modelName\\s*=\\s*'([^']+)'").matcher(content);
                    if (m.find()) modelName = m.group(1);
                }
            } catch (Exception e) {
                log.warn("解析脚本参数失败: {}", relPath, e);
            }
        }

        params.put("stopTime", stopTime != null ? stopTime : "30");
        params.put("fixedStep", fixedStep != null ? fixedStep : "0.025");
        params.put("npCommand", npCommand != null ? npCommand : "21000");
        params.put("loadPower", loadPower != null ? loadPower : "1000");
        params.put("modelName", modelName != null ? modelName : "");
        params.put("ngReferenceRpm", ngReferenceRpm != null ? ngReferenceRpm : "36000");
        params.put("wfReferenceKgps", wfReferenceKgps != null ? wfReferenceKgps : "0.15");
        params.put("t45Max", t45Max != null ? t45Max : "1400");
        params.put("mkpMax", mkpMax != null ? mkpMax : "1200");
        params.put("wfMax", wfMax != null ? wfMax : "2");
        params.put("wfMin", wfMin != null ? wfMin : "0.01");
        params.put("wfRateLim", wfRateLim != null ? wfRateLim : "1.5");
        params.put("ngMaxRatio", ngMax != null ? ngMax : "1.05");

        List<Map<String, String>> kpiParams = new ArrayList<>();
        kpiParams.add(makeKpi("Np", "npCommand", npCommand != null ? npCommand : "21000", "rpm"));
        kpiParams.add(makeKpi("Ng", "ngReferenceRpm", ngReferenceRpm != null ? ngReferenceRpm : "36000", "rpm"));
        kpiParams.add(makeKpi("T45", "t45Max", t45Max != null ? t45Max : "1400", "K"));
        kpiParams.add(makeKpi("Mkp", "loadPower", loadPower != null ? loadPower : "850", "N·m"));
        kpiParams.add(makeKpi("Wf", "wfReferenceKgps", wfReferenceKgps != null ? wfReferenceKgps : "0.15", "kg/s"));
        kpiParams.add(makeKpi("Error", "referenceErrMax", "0", "-"));
        params.put("kpiParams", kpiParams);

        List<Map<String, String>> systemModules = new ArrayList<>();
        systemModules.add(makeModule("1", "控制系统", "🖥", "ok", "已接", "数据正常"));
        systemModules.add(makeModule("2", "燃油系统", "⛽", "ok", "已接", "数据正常"));
        systemModules.add(makeModule("3", "发动机总体性能", "⚙", "ok", "已接", "数据正常"));
        systemModules.add(makeModule("4", "滑油系统", "🛢", "ok", "已接", "数据正常"));
        systemModules.add(makeModule("5", "空气系统", "🌬", "ok", "已接", "数据正常"));
        systemModules.add(makeModule("6", "信号与告警", "🔔", "warn", "未连接", "待接入"));
        params.put("systemModules", systemModules);

        return params;
    }

    private Map<String, String> makeKpi(String name, String key, String value, String unit) {
        Map<String, String> kpi = new LinkedHashMap<>();
        kpi.put("name", name);
        kpi.put("key", key);
        kpi.put("value", value);
        kpi.put("unit", unit);
        return kpi;
    }

    private Map<String, String> makeModule(String id, String name, String icon, String status, String statusText, String desc) {
        Map<String, String> mod = new LinkedHashMap<>();
        mod.put("id", id);
        mod.put("name", name);
        mod.put("icon", icon);
        mod.put("status", status);
        mod.put("statusText", statusText);
        mod.put("desc", desc);
        return mod;
    }

    private void scanProgramDir(File baseDir, File dir,
                                List<String> modelFiles, List<String> scriptFiles,
                                List<String> mapFiles, List<String> headerFiles,
                                List<String> dllFiles, List<String> otherFiles) {
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isDirectory()) {
                if (!"slprj".equals(f.getName())) {
                    scanProgramDir(baseDir, f, modelFiles, scriptFiles, mapFiles, headerFiles, dllFiles, otherFiles);
                }
            } else {
                String relPath = baseDir.toPath().relativize(f.toPath()).toString().replace('\\', '/');
                String lower = f.getName().toLowerCase();
                if (lower.endsWith(".slx") || lower.endsWith(".mdl")) {
                    modelFiles.add(relPath);
                } else if (lower.endsWith(".m")) {
                    scriptFiles.add(relPath);
                } else if (lower.endsWith(".map")) {
                    mapFiles.add(relPath);
                } else if (lower.endsWith(".h") || lower.endsWith(".hh")) {
                    headerFiles.add(relPath);
                } else if (lower.endsWith(".dll")) {
                    dllFiles.add(relPath);
                } else if (!lower.endsWith(".slxc") && !lower.endsWith(".slx.r2019b")
                        && !lower.endsWith(".md") && !lower.endsWith(".docx")) {
                    otherFiles.add(relPath);
                }
            }
        }
    }

    private void deleteDirectory(File dir) {
        if (dir == null || !dir.exists()) return;
        File[] files = dir.listFiles();
        if (files != null) {
            for (File f : files) {
                if (f.isDirectory()) deleteDirectory(f);
                else f.delete();
            }
        }
        dir.delete();
    }


    private String readLastLines(File f, int n) {
        if (!f.exists()) return "";
        List<String> lines = new ArrayList<>();
        try (BufferedReader br = Files.newBufferedReader(f.toPath(), StandardCharsets.UTF_8)) {
            String line;
            while ((line = br.readLine()) != null) {
                lines.add(line);
                if (lines.size() > n) lines.remove(0);
            }
        } catch (IOException e) { }
        return lines.stream().collect(Collectors.joining("\n"));
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
