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

import javax.annotation.PostConstruct;
import java.io.*;
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

    private File getTaskBaseDir(String projectName) {
        String proj = (projectName != null && !projectName.isEmpty()) ? projectName : ProjectContext.getCurrentProject("unknown");
        File dir = new File(TASK_BASE_DIR + "/" + proj + "/program-tasks");
        if (!dir.exists()) dir.mkdirs();
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

    public List<ProgramEntity> queryProgramList() {
        try {
            String sql = String.format("SELECT * FROM %s;", META_PREFIX);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql);
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
        runtime.put("simulinkModel", "");
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
                String storagePath = buildStoragePath(projectName != null ? projectName : (queryMeta != null ? queryMeta.getProjectName() : null), name, version);
                iginxClient.getDeleteClient().deleteMeasurement(storagePath);
                if (queryMeta != null && queryMeta.getTimestamp() != null) {
                    long timestamp = queryMeta.getTimestamp();
                    iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp - 1, timestamp + 1);
                }
                dataPermissionService.deleteByTablePrefix(storagePath);
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

    public Result<Map<String, Object>> run(String name, String version) {
        ProgramEntity entity = queryMeta(name, version);
        if (entity == null) return Result.error("程序不存在");
        entity.setStatus("RUNNING");
        entity.setLastError(null);
        entity.setLastRunTime(System.currentTimeMillis());
        try {
            saveProgramMetadata(entity);
        } catch (Exception e) {
            log.error("保存运行状态失败", e);
        }

        String key = runtimeKey(entity);
        runtimeStatus.put(key, entity);
        new Thread(() -> doRun(key, entity), "program-run-" + key).start();

        Map<String, Object> data = new HashMap<>();
        data.put("status", "RUNNING");
        return Result.success("运行已启动", data);
    }

    private void doRun(String key, ProgramEntity entity) {
        String taskId = key + "_" + System.currentTimeMillis();
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
            String modelName = runtime.path("simulinkModel").asText("");
            int stopTime = runtime.path("stopTime").asInt(30);

            String programDir = findProgramDir(taskDir, preRunScript);
            File wrapper = new File(taskDir, "run_wrapper.m");
            writeWrapper(wrapper, taskDir.getAbsolutePath(), programDir, preRunScript, modelName, stopTime);

            ProcessBuilder pb = new ProcessBuilder();
            pb.directory(taskDir);
            pb.command("matlab", "-batch", "cd('" + escape(taskDir.getAbsolutePath()) + "'); run_wrapper; exit;", "-nosplash", "-nodesktop");
            pb.redirectErrorStream(true);
            File logFile = new File(taskDir, "run.log");
            pb.redirectOutput(logFile);

            Process process = pb.start();
            boolean finished = process.waitFor(300, TimeUnit.SECONDS);
            if (!finished) {
                process.destroyForcibly();
                entity.setStatus("ERROR");
                entity.setLastError("运行超时");
                saveProgramMetadata(entity);
                return;
            }
            int exitCode = process.exitValue();
            if (exitCode != 0) {
                String err = readLastLines(logFile, 20);
                entity.setStatus("ERROR");
                entity.setLastError("MATLAB 退出码 " + exitCode + ": " + err);
                saveProgramMetadata(entity);
                return;
            }

            File csv = new File(taskDir, "results.csv");
            if (!csv.exists()) {
                entity.setStatus("ERROR");
                entity.setLastError("未生成 results.csv");
                saveProgramMetadata(entity);
                return;
            }
            entity.setStatus("SUCCESS");
            entity.setLastResultCsv(csv.getAbsolutePath());
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

    private void writeWrapper(File f, String taskDir, String programDir, String preRun, String model, int stopTime) throws IOException {
        StringBuilder sb = new StringBuilder();
        sb.append("workDir = '").append(escape(taskDir)).append("';\n");
        sb.append("programDir = '").append(escape(programDir)).append("';\n");
        sb.append("cd(workDir);\n");
        sb.append("addpath(programDir);\n");
        sb.append("try\n");
        sb.append("    ").append(preRun).append(";\n");
        if (model != null && !model.isEmpty()) {
            sb.append("    load_system('").append(escape(model)).append("');\n");
            sb.append("    simOut = sim('").append(escape(model)).append("', 'ReturnWorkspaceOutputs', 'on', 'StopTime', '").append(stopTime).append("');\n");
            sb.append("    save('simOut.mat', 'simOut');\n");
            sb.append("    tout = simOut.tout;\n");
            sb.append("    writematrix(tout, 'results.csv');\n");
        }
        sb.append("catch ME\n");
        sb.append("    fid = fopen('error.txt', 'w');\n");
        sb.append("    fprintf(fid, '%s\\n', ME.message);\n");
        sb.append("    fclose(fid);\n");
        sb.append("    rethrow(ME);\n");
        sb.append("end\n");
        Files.write(f.toPath(), sb.toString().getBytes(StandardCharsets.UTF_8));
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

    public Result<Map<String, Object>> results(String name, String version) {
        ProgramEntity entity = queryMeta(name, version);
        if (entity == null) return Result.error("程序不存在");
        Map<String, Object> data = new HashMap<>();
        data.put("status", entity.getStatus());
        data.put("lastError", entity.getLastError());
        data.put("lastRunTime", entity.getLastRunTime());
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

    public Result<ProgramEntity> updateConfig(String name, String version, String configJson) {
        ProgramEntity entity = queryMeta(name, version);
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
