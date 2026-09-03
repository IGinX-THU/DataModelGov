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
import com.tsinghua.entity.ProgramTaskEntity;
import com.tsinghua.enums.TaskStatus;
import com.tsinghua.dto.UploadResult;
import com.tsinghua.dto.DataQueryRequest;
import com.tsinghua.dto.TableDto;
import com.tsinghua.model.Result;
import com.tsinghua.matlab.MatlabSimulationRunner;
import com.tsinghua.matlab.MatlabEnginePool;
import com.tsinghua.matlab.MatlabUtil;
import com.tsinghua.program.config.ProgramConfig;
import com.tsinghua.program.config.ProgramConfigMapper;
import com.tsinghua.util.ArchiveUtil;
import com.tsinghua.util.ConvertUtil;
import com.tsinghua.util.FileUtil;
import com.tsinghua.util.ProjectContext;
import com.tsinghua.util.SimTimeUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import javax.annotation.PostConstruct;

import java.io.*;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.stream.Collectors;

@Slf4j
@Service
public class ProgramService {

    private static final int CHUNK_SIZE = 65536;
    private static final String STORAGE_PREFIX_BASE = "programs_system";
    private static final String META_PREFIX = "relational_system.programs_meta";

    private static final String TASK_BASE_DIR = "project";
    private static final String TASK_DATA_PREFIX = "relational_system.program_task";
    private final ObjectMapper mapper = new ObjectMapper();
    private final Map<Long, Process> processMap = new ConcurrentHashMap<>();
    private final Map<Long, ProgramTaskEntity> runningTasks = new ConcurrentHashMap<>();
    // 实时仿真数据缓冲：key=taskTimestamp, value=LiveDataBuffer
    private final Map<Long, LiveDataBuffer> liveDataMap = new ConcurrentHashMap<>();
    // 暂停/恢复状态：key=taskTimestamp, value=true表示已暂停
    private final Map<Long, Boolean> pauseFlags = new ConcurrentHashMap<>();
    // MATLAB Engine 会话：key=taskTimestamp，存在即表示该任务由引擎驱动（支持真实暂停/恢复/停止）
    private final Map<Long, MatlabSimulationRunner> engineRunners = new ConcurrentHashMap<>();
    // 引擎池（pool-size 在 @PostConstruct 中从 yml 读取后创建）
    private MatlabEnginePool enginePool;
    private final AtomicBoolean prewarming = new AtomicBoolean(false);
    private final Queue<ProgramEntity> prewarmQueue = new ConcurrentLinkedQueue<>();
    private final Set<String> queuedPrewarms = ConcurrentHashMap.newKeySet();
    private volatile String prewarmMessage = "";
    // 引擎运行期不可用（如缺少 MATLAB 原生库）时置位，后续任务直接 FAILED
    private volatile boolean engineDisabled = false;
    // 服务启动时间，用于判断 RUNNING 状态的任务是否为重启前遗留
    private final long serviceStartTime = System.currentTimeMillis();
    // 仿真执行结果码
    private static final int RUN_OK = 0;
    private static final int RUN_STOPPED = 1;
    private static final int RUN_FAILED = 2;

    // 运行期开关：置 false 可禁用引擎（仿真任务将直接 FAILED，不再回退）
    @Value("${matlab.engine.enabled:true}")
    private boolean matlabEngineEnabled;

    // MATLAB 安装根目录（如 C:\Program Files\MATLAB\R2019b）；留空则自动探测。
    // 服务启动时注入到 MatlabSimulationRunner，用于在进程内加载 MATLAB 原生库，免去手动改 PATH。
    @Value("${matlab.engine.home:}")
    private String matlabHome;

    // 引擎池最大并发数（含常驻引擎），每个引擎约占 1-2GB 内存
    @Value("${matlab.engine.pool-size:4}")
    private int enginePoolSize;

    @PostConstruct
    private void initMatlabHome() {
        MatlabSimulationRunner.configureMatlabHome(matlabHome);
        // 创建引擎池（pool-size 从 yml 读取，默认 4）
        enginePool = new MatlabEnginePool(enginePoolSize, matlabHome);
        log.info("MATLAB 引擎池大小: {}", enginePoolSize);
        // 引擎模式启用时，随 Spring Boot 启动常驻 MATLAB 引擎（异步，不阻塞启动）
        if (matlabEngineEnabled) {
            enginePool.init();
        }
    }

    @EventListener(ApplicationReadyEvent.class)
    public void prewarmOnApplicationReady() {
        startPrewarmAsync();
    }

    @PreDestroy
    private void destroyEnginePool() {
        if (enginePool != null) enginePool.shutdown();
    }

    /** Shared MATLAB engine pool for other program execution services in this package. */
    MatlabEnginePool enginePool() {
        if (enginePool == null) {
            throw new IllegalStateException("MATLAB engine pool is not initialized");
        }
        return enginePool;
    }

    @Autowired
    private DataPermissionService dataPermissionService;

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private ProjectService projectService;

    @Autowired
    private DataTableService dataTableService;

    @Autowired
    @org.springframework.context.annotation.Lazy
    private ProgramWorkflowService programWorkflowService;

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

    public File getProgramDir(String projectName, String name, String version) {
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
            return dto;
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
                case META_PREFIX + "." + "setupScript":
                    if (value instanceof byte[]) {
                        dto.setSetupScript(new String((byte[]) value, StandardCharsets.UTF_8));
                    } else if (value instanceof String) {
                        dto.setSetupScript((String) value);
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
                list.add(entity);
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

    /** 读取 classpath 资源为字符串 */
    private String readClasspathString(String path) {
        try {
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
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * 上传预置程序：从 classpath:programs/<程序名>/ 读取源码包+配置+脚本，存入 IGinX。
     * configJson 和 setupScript 分别存到两个字段。
     */
    public Map<String, Object> uploadPresetProgram(String programName, String version, String projectName, String displayName) throws Exception {
        // displayName 为用户输入的程序名称，若提供则覆盖 programName 作为存储名
        String effectiveName = (displayName != null && !displayName.trim().isEmpty()) ? displayName.trim() : programName;
        String base = "programs/" + programName + "/";
        // 1. 找到源码压缩包
        org.springframework.core.io.support.PathMatchingResourcePatternResolver resolver =
                new org.springframework.core.io.support.PathMatchingResourcePatternResolver();
        org.springframework.core.io.Resource[] resources = resolver.getResources("classpath:" + base + "*");
        Arrays.sort(resources, Comparator.comparingInt(resource -> presetArchivePriority(resource.getFilename())));
        String archiveFilename = null;
        byte[] archiveBytes = null;
        for (org.springframework.core.io.Resource res : resources) {
            String filename = res.getFilename();
            if (filename == null) continue;
            String lower = filename.toLowerCase();
            if (lower.endsWith(".zip") || lower.endsWith(".rar") || lower.endsWith(".7z") || lower.endsWith(".tar.gz") || lower.endsWith(".tgz") || lower.endsWith(".tar")) {
                try (java.io.InputStream is = res.getInputStream()) {
                    java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
                    byte[] buf = new byte[8192];
                    int n;
                    while ((n = is.read(buf)) > 0) out.write(buf, 0, n);
                    archiveBytes = out.toByteArray();
                    archiveFilename = filename;
                    break;
                }
            }
        }
        if (archiveBytes == null) throw new IllegalArgumentException("预置程序目录下未找到源码压缩包: " + base);

        // 2. 读取 config.json（不内联脚本）
        String configContent = readClasspathString(base + "config.json");

        // 3. 读取 dmg_setup.m 内容（独立存 setupScript 字段）
        String setupScriptContent = readClasspathString(base + "dmg_setup.m");

        // 4. 存入 IGinX
        String programVersion = (version != null && !version.isEmpty()) ? version : "1.0";
        String projName = (projectName != null && !projectName.isEmpty()) ? projectName : ProjectContext.getCurrentProject("unknown");
        String storagePath = buildStoragePath(projName, effectiveName, programVersion);

        if (dataPermissionService.existTablePrefix(storagePath)) {
            throw new IllegalArgumentException("仿真程序资产已存在: " + effectiveName + " " + programVersion);
        }

        // 解压验证
        File programDir = getProgramDir(projName, effectiveName, programVersion);
        if (programDir.exists()) FileUtil.deleteDirectory(programDir);
        programDir.mkdirs();
        File tempArchive = new File(programDir, archiveFilename);
        Files.write(tempArchive.toPath(), archiveBytes);
        try {
            ArchiveUtil.extractArchive(tempArchive, programDir);
        } catch (Exception e) {
            FileUtil.deleteDirectory(programDir);
            throw new IllegalArgumentException("程序包解压失败: " + e.getMessage(), e);
        } finally {
            if (tempArchive.exists()) tempArchive.delete();
        }

        // 写入 IGinX
        int totalChunks = (int) Math.ceil((double) archiveBytes.length / CHUNK_SIZE);
        List<Point> points = new ArrayList<>();
        for (int i = 0; i < totalChunks; i++) {
            int start = i * CHUNK_SIZE;
            int end = Math.min(archiveBytes.length, start + CHUNK_SIZE);
            byte[] chunk = Arrays.copyOfRange(archiveBytes, start, end);
            points.add(Point.builder().measurement(storagePath).key(i).binaryValue(chunk).build());
        }
        iginxClient.getWriteClient().writePoints(points);
        String fileMd5 = FileUtil.calculateMD5(archiveBytes);

        // 保存元数据
        ProgramEntity programMetaDto = new ProgramEntity();
        programMetaDto.setName(effectiveName);
        programMetaDto.setVersion(programVersion);
        programMetaDto.setDescription("预置程序: " + programName);
        programMetaDto.setFileName(archiveFilename);
        programMetaDto.setFileSize((long) archiveBytes.length);
        programMetaDto.setChunkCount(totalChunks);
        programMetaDto.setStoragePath(storagePath);
        programMetaDto.setFileMd5(fileMd5);
        programMetaDto.setProjectName(projName);
        programMetaDto.setAuthor(AuthUtil.getCurrentUsername());
        programMetaDto.setStatus("READY");
        programMetaDto.setConfigJson(configContent != null ? configContent : buildDefaultConfig(effectiveName).toString());
        programMetaDto.setSetupScript(setupScriptContent);
        saveProgramMetadata(programMetaDto);
        dataPermissionService.saveTablePrefix(storagePath);

        if (projName != null && !projName.isEmpty()) {
            try { projectService.addToProject(projName, storagePath, "programs"); } catch (Exception e) { log.error("添加到项目失败", e); }
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("name", programName);
        result.put("version", programVersion);
        result.put("fileName", archiveFilename);
        result.put("fileSize", archiveBytes.length);
        result.put("chunkCount", totalChunks);
        result.put("storagePath", storagePath);
        result.put("fileMd5", fileMd5);
        log.info("预置程序上传成功: {} {}, 块数: {}", programName, programVersion, totalChunks);
        return result;
    }

    private int presetArchivePriority(String filename) {
        if (filename == null) return Integer.MAX_VALUE;
        String lower = filename.toLowerCase(Locale.ROOT);
        if (lower.endsWith(".zip")) return 0;
        if (lower.endsWith(".7z")) return 1;
        if (lower.endsWith(".rar")) return 2;
        if (lower.endsWith(".tar.gz") || lower.endsWith(".tgz")) return 3;
        if (lower.endsWith(".tar")) return 4;
        return Integer.MAX_VALUE;
    }

    /**
     * 获取仿真程序配置 JSON（configJson 字段）。若无配置返回骨架。
     */
    public String getProgramConfig(String name, String version, String projectName) {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) return null;
        String cfg = entity.getConfigJson();
        if (!StringUtils.hasText(cfg)) {
            // 返回骨架配置，便于前端编辑器初始化
            return ProgramConfigMapper.stringify(ProgramConfigMapper.parse(buildDefaultConfig(name).toString()));
        }
        return cfg;
    }

    /** 获取仿真程序的信号采集脚本内容（setupScript 独立字段） */
    public String getProgramSetupScript(String name, String version, String projectName) {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) return null;
        return entity.getSetupScript();
    }

    /** 保存仿真程序的信号采集脚本内容（setupScript 独立字段） */
    public List<String> saveProgramSetupScript(String name, String version, String projectName, String setupScript) {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) return Collections.singletonList("程序不存在");
        entity.setSetupScript(setupScript);
        try {
            saveProgramMetadata(entity);
        } catch (Exception e) {
            log.error("保存脚本失败", e);
            return Collections.singletonList("保存失败: " + e.getMessage());
        }
        return Collections.emptyList();
    }

    /**
     * 统计每个插件被多少个程序配置引用。
     * key = 插件 ID（ProgramConfig.ui.extension.entry），value = 引用计数。
     */
    public java.util.Map<String, Integer> countPluginReferences() {
        java.util.Map<String, Integer> counts = new java.util.HashMap<>();
        try {
            List<ProgramEntity> all = queryProgramList();
            if (all == null) return counts;
            for (ProgramEntity entity : all) {
                String cfg = entity.getConfigJson();
                if (!StringUtils.hasText(cfg)) continue;
                try {
                    JsonNode root = mapper.readTree(cfg);
                    JsonNode ext = root.path("ui").path("extension");
                    if (ext.isMissingNode() || !ext.path("enabled").asBoolean(false)) continue;
                    String entry = ext.path("entry").asText("");
                    if (StringUtils.hasText(entry)) {
                        counts.merge(entry, 1, Integer::sum);
                    }
                } catch (Exception ignored) {}
            }
        } catch (Exception e) {
            log.warn("统计插件引用计数失败: {}", e.getMessage());
        }
        return counts;
    }

    /**
     * 保存仿真程序配置 JSON：校验后写入 ProgramEntity.configJson 并持久化。
     * 返回非空列表表示校验错误（调用方据决定是否放行）；返回空列表表示成功。
     */
    public List<String> saveProgramConfig(String name, String version, String projectName, String configJson) {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) return Collections.singletonList("程序不存在");
        ProgramConfig cfg = ProgramConfigMapper.parse(configJson);
        if (cfg == null) return Collections.singletonList("配置 JSON 解析失败");
        List<String> errors = ProgramConfigMapper.validate(cfg, false);
        if (!errors.isEmpty()) return errors;
        entity.setConfigJson(configJson);
        entity.setStatus("READY");
        try {
            saveProgramMetadata(entity);
        } catch (Exception e) {
            log.error("保存程序配置失败", e);
            return Collections.singletonList("保存失败: " + e.getMessage());
        }
        ProgramConfig.RuntimeConfig runtime = cfg.getRuntime();
        if (runtime != null && Boolean.TRUE.equals(runtime.getPrewarm())) {
            log.info("[MATLAB-PREWARM] 配置保存成功，触发预热: {} {}", entity.getName(), entity.getVersion());
            enqueuePrewarm(entity);
        }
        return Collections.emptyList();
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
        points.add(ConvertUtil.createFieldPoint(META_PREFIX, "setupScript", entity.getSetupScript(), timestamp));
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
        String ext = ArchiveUtil.getExtension(originalName);
        if (ext == null || !ArchiveUtil.SUPPORTED_ARCHIVE.contains(ext)) {
            throw new IllegalArgumentException("仅支持以下压缩格式: zip, rar, 7z, tar, tar.gz, tgz");
        }
        String programName = (name != null && !name.isEmpty()) ? name : ArchiveUtil.removeArchiveExtension(originalName);
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
            FileUtil.deleteDirectory(programDir);
        }
        programDir.mkdirs();
        File tempArchive = new File(programDir, originalName);
        Files.write(tempArchive.toPath(), fileBytes);
        try {
            ArchiveUtil.extractArchive(tempArchive, programDir);
            log.info("仿真程序解压验证成功。目录: {}", programDir.getAbsolutePath());
        } catch (Exception e) {
            FileUtil.deleteDirectory(programDir);
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
        String fileMd5 = FileUtil.calculateMD5(fileBytes);

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
        programMetaDto.setStatus("UNCONFIGURED");
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

    /** 构建骨架配置：不写死任何程序专属值，由集成人员在配置编辑器里补全。
     *  runtime 留空，运行时 doRun 会自动探测 .slx/.m 填入。 */
    private ObjectNode buildDefaultConfig(String programName) {
        ObjectNode config = mapper.createObjectNode();
        config.put("programName", programName);
        ObjectNode runtime = config.putObject("runtime");
        runtime.put("preRunScript", "");
        runtime.put("skipPreRunOnReuse", false);
        runtime.put("prewarm", false);
        runtime.put("simulinkModel", "");
        runtime.put("stopTime", 30);
        config.putArray("parameters");
        config.putNull("setupScript");
        ObjectNode ui = config.putObject("ui");
        ui.put("title", programName);
        ui.putArray("sections");
        return config;
    }

    private void writeProgramConfig(File taskDir, ProgramEntity entity) throws IOException {
        ObjectNode config = (entity.getConfigJson() != null)
                ? (ObjectNode) mapper.readTree(entity.getConfigJson())
                : buildDefaultConfig(entity.getName());
        config.put("programDir", taskDir.getAbsolutePath());
        File cfg = new File(taskDir, "program-config.json");
        mapper.writerWithDefaultPrettyPrinter().writeValue(cfg, config);
        // 从 entity.setupScript（独立字段）写到 taskDir/dmg_setup.m
        String script = entity.getSetupScript();
        if (script != null && !script.trim().isEmpty()) {
            Files.write(new File(taskDir, "dmg_setup.m").toPath(),
                    script.getBytes(StandardCharsets.UTF_8));
        }
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
                    FileUtil.deleteDirectory(programDir);
                    log.info("已删除程序目录: {}", programDir.getAbsolutePath());
                }
                // 删除该程序的所有工作区
                programWorkflowService.deleteWorkspacesByProgram(name, version, actualProjectName);
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
                        FileUtil.deleteDirectory(programDir);
                        log.info("已删除程序目录: {}", programDir.getAbsolutePath());
                    }
                    // 删除该程序版本的所有工作区
                    programWorkflowService.deleteWorkspacesByProgram(meta.getName(), meta.getVersion(), meta.getProjectName());
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

    public Result<Map<String, Object>> run(String name, String version, String stopTime, String fixedStep, String modelFile, String projectName, Map<String, String> params) {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) return Result.error("程序不存在");

        // 停止时间对齐到固定步长的整数倍，保证仿真真的停在用户设定的时刻上
        final String alignedStopTime = alignStopTimeParam(stopTime, fixedStep);

        // Create task record
        long taskTimestamp = System.currentTimeMillis();
        ProgramTaskEntity task = new ProgramTaskEntity();
        task.setTimestamp(taskTimestamp);
        task.setProgramName(name);
        task.setProgramVersion(version);
        task.setProjectName(projectName);
        task.setStartTime(taskTimestamp);
        // 引擎模式下，如果所有引擎都在使用中，先标记为 QUEUED（排队中）
        // doRun 线程 borrow 到引擎后会把状态改为 RUNNING
        boolean willQueue = isEngineMode() && (prewarming.get() || (enginePool.idleCount() == 0
                && enginePool.totalCount() >= enginePool.maxEngines()));
        task.setStatus(willQueue ? TaskStatus.QUEUED.getValue() : TaskStatus.RUNNING.getValue());
        task.setStopTime(alignedStopTime);
        task.setFixedStep(fixedStep);
        task.setModelFile(modelFile);
        // 动态参数序列化为 JSON 存档（兼容旧字段 npCommand/loadPower）
        task.setParamsJson(mapper.valueToTree(params).toString());
        runningTasks.put(taskTimestamp, task);
        saveTask(task);

        // 提前创建 LiveDataBuffer，确保 SSE 连接时 buffer 已存在
        // （doRun 线程下载/解压需要时间，此时前端 SSE 订阅才能拿到 buffer）
        liveDataMap.put(taskTimestamp, new LiveDataBuffer());
        LiveDataBuffer initBuffer = liveDataMap.get(taskTimestamp);
        if (initBuffer != null) initBuffer.setTaskInfo(task.getStatus(), null);

        new Thread(() -> doRun(taskTimestamp, entity, alignedStopTime, fixedStep, modelFile, params), "program-run-" + taskTimestamp).start();

        Map<String, Object> data = new HashMap<>();
        data.put("status", willQueue ? TaskStatus.QUEUED.getValue() : TaskStatus.RUNNING.getValue());
        data.put("taskTimestamp", taskTimestamp);
        // 回传对齐后的停止时间，前端据此校正时间轴与游标上限
        data.put("stopTime", alignedStopTime);
        data.put("engineMode", isEngineMode());
        if (willQueue) {
            data.put("queuePosition", enginePool.waitingCount());
            return Result.success("已加入排队（引擎忙），请稍后...", data);
        }
        return Result.success("运行已启动", data);
    }

    /** 停止时间按固定步长取整（如 步长0.025、停止时间20.31 → 20.3） */
    private String alignStopTimeParam(String stopTime, String fixedStep) {
        if (!StringUtils.hasText(stopTime) || !StringUtils.hasText(fixedStep)) return stopTime;
        double st = SimTimeUtil.parse(stopTime, Double.NaN);
        double fs = SimTimeUtil.parse(fixedStep, Double.NaN);
        if (Double.isNaN(st) || Double.isNaN(fs)) return stopTime;
        String aligned = SimTimeUtil.format(SimTimeUtil.alignToStep(st, fs));
        if (!aligned.equals(stopTime)) {
            log.info("停止时间 {} 按固定步长 {} 对齐为 {}", stopTime, fixedStep, aligned);
        }
        return aligned;
    }

    /** 是否使用 MATLAB Engine API 驱动仿真（否则任务直接 FAILED，不再回退） */
    private boolean isEngineMode() {
        if (!matlabEngineEnabled || engineDisabled) return false;
        if (!MatlabSimulationRunner.isApiAvailable()) return false;
        // 引擎池启动失败时拒绝运行；启动中或已就绪都走引擎模式（borrow 会等待就绪）
        if (enginePool.isFailed()) {
            log.warn("MATLAB 引擎池启动失败，仿真无法运行");
            return false;
        }
        return true;
    }

    private List<ProgramEntity> queryProgramsForPrewarm() {
        try {
            String sql = "SELECT * FROM " + META_PREFIX + " WHERE 1=1;";
            log.info("[MATLAB-PREWARM] 执行系统级程序查询: {}", sql);
            SessionExecuteSqlResult result = iginxSession.executeSql(sql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(result);
            if (records == null) return new ArrayList<>();
            List<ProgramEntity> programs = new ArrayList<>();
            for (Map<String, Object> record : records) {
                ProgramEntity entity = new ProgramEntity();
                record.forEach((key, value) -> setDtoField(entity, key, value));
                programs.add(entity);
            }
            return programs;
        } catch (Exception e) {
            log.error("[MATLAB-PREWARM] 系统级程序查询失败", e);
            return new ArrayList<>();
        }
    }

    private void startPrewarmAsync() {
        startPrewarmAsync(6);
    }

    private void startPrewarmAsync(int attemptsRemaining) {
        if (!matlabEngineEnabled || enginePool == null) return;
        List<ProgramEntity> programs = queryProgramsForPrewarm();
        if (programs.isEmpty() && attemptsRemaining > 1) {
            log.warn("[MATLAB-PREWARM] 暂未发现程序，10 秒后重试（剩余 {} 次）", attemptsRemaining - 1);
            Thread retry = new Thread(() -> {
                try {
                    Thread.sleep(10000);
                    startPrewarmAsync(attemptsRemaining - 1);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }, "matlab-prewarm-discovery");
            retry.setDaemon(true);
            retry.start();
            return;
        }
        int enabled = 0;
        for (ProgramEntity entity : programs) {
            try {
                ProgramConfig config = ProgramConfigMapper.parse(entity.getConfigJson());
                ProgramConfig.RuntimeConfig runtime = config != null ? config.getRuntime() : null;
                if (runtime != null && Boolean.TRUE.equals(runtime.getPrewarm())) {
                    enqueuePrewarm(entity);
                    enabled++;
                }
            } catch (Exception e) {
                log.warn("[MATLAB-PREWARM] 跳过无法解析配置的程序 {} {}: {}",
                        entity.getName(), entity.getVersion(), e.getMessage());
            }
        }
        log.info("[MATLAB-PREWARM] 扫描程序 {} 个，已启用预热 {} 个，当前队列 {} 个",
                programs.size(), enabled, prewarmQueue.size());
        startPrewarmWorker();
    }

    private void enqueuePrewarm(ProgramEntity entity) {
        if (entity == null || !matlabEngineEnabled || enginePool == null) return;
        String key = String.valueOf(entity.getProjectName()) + "|" + entity.getName() + "|" + entity.getVersion();
        if (queuedPrewarms.add(key)) {
            prewarmQueue.offer(entity);
            log.info("[MATLAB-PREWARM] 已加入预热队列: {} {}", entity.getName(), entity.getVersion());
        }
        startPrewarmWorker();
    }

    private void startPrewarmWorker() {
        if (prewarmQueue.isEmpty() || !prewarming.compareAndSet(false, true)) return;
        Thread thread = new Thread(() -> {
            try {
                ProgramEntity entity;
                while ((entity = prewarmQueue.poll()) != null) {
                    String key = String.valueOf(entity.getProjectName()) + "|" + entity.getName() + "|" + entity.getVersion();
                    prewarmMessage = "正在预热 " + entity.getName() + " " + entity.getVersion();
                    try {
                        ProgramConfig config = ProgramConfigMapper.parse(entity.getConfigJson());
                        if (config == null || config.getRuntime() == null || !Boolean.TRUE.equals(config.getRuntime().getPrewarm())) {
                            log.info("[MATLAB-PREWARM] 配置已关闭预热，跳过 {} {}", entity.getName(), entity.getVersion());
                            continue;
                        }
                        prewarmProgram(entity, config);
                        log.info("[MATLAB-PREWARM] {} {} 预热完成", entity.getName(), entity.getVersion());
                    } catch (Exception e) {
                        log.error("[MATLAB-PREWARM] {} {} 预热失败", entity.getName(), entity.getVersion(), e);
                    } finally {
                        queuedPrewarms.remove(key);
                    }
                }
                prewarmMessage = "程序预热完成";
            } finally {
                prewarming.set(false);
                if (!prewarmQueue.isEmpty()) startPrewarmWorker();
            }
        }, "matlab-program-prewarm");
        thread.setDaemon(true);
        thread.start();
    }

    private void prewarmProgram(ProgramEntity entity, ProgramConfig config) throws Exception {
        ProgramConfig.RuntimeConfig runtime = config.getRuntime();
        String modelFile = runtime.getSimulinkModel();
        if (!StringUtils.hasText(modelFile)) throw new Exception("未配置 Simulink 模型");
        File baseDir = new File(System.getProperty("java.io.tmpdir"), "datamodelgov-prewarm");
        if (!baseDir.exists() && !baseDir.mkdirs()) throw new IOException("无法创建预热目录: " + baseDir);
        File taskDir = new File(baseDir, entity.getName() + "-" + entity.getVersion() + "-" + System.currentTimeMillis());
        if (!taskDir.mkdirs()) throw new IOException("无法创建程序预热目录: " + taskDir);
        byte[] archiveBytes = downloadFromIginx(entity.getStoragePath(), entity.getChunkCount(), entity.getFileMd5());
        File archiveFile = new File(taskDir, entity.getFileName());
        Files.write(archiveFile.toPath(), archiveBytes);
        ArchiveUtil.extractArchive(archiveFile, taskDir, true);
        writeProgramConfig(taskDir, entity);
        String preRunScript = StringUtils.hasText(runtime.getPreRunScript()) ? runtime.getPreRunScript() : "";
        String programDir = FileUtil.findProgramDir(taskDir, preRunScript);
        File setupSource = new File(taskDir, "dmg_setup.m");
        File setupTarget = new File(programDir, "dmg_setup.m");
        if (setupSource.exists() && !setupTarget.exists()) Files.copy(setupSource.toPath(), setupTarget.toPath());
        Map<String, String> parameterValues = new LinkedHashMap<>();
        if (config.getParameters() != null) {
            for (ProgramConfig.ParameterSpec parameter : config.getParameters()) {
                if (StringUtils.hasText(parameter.getDefaultValue())) {
                    parameterValues.put(parameter.getKey(), parameter.getDefaultValue());
                }
            }
        }
        double fixedStepValue = SimTimeUtil.parse(runtime.getFixedStep(), 0.025);
        String modelName = modelFile.replaceAll("\\.(slx|mdl)$", "");
        String signalCacheKey = buildSignalCacheKey(entity);
        MatlabSimulationRunner runner = new MatlabSimulationRunner(taskDir, programDir, preRunScript,
                true, modelName, fixedStepValue, runtime.getFixedStep(), parameterValues,
                config.getParameters(), StringUtils.hasText(entity.getSetupScript()) ? "dmg_setup" : null,
                signalCacheKey, new MatlabSimulationRunner.LiveSink() {
                    @Override public void onStopTime(double alignedStopTime) {}
                    @Override public void onHeaders(List<String> headers) {}
                    @Override public void onRows(List<String[]> rows) {}
                    @Override public void onLog(String line) { log.info("[MATLAB-PREWARM] {}", line); }
                }, enginePool);
        try {
            runner.prewarm();
        } finally {
            runner.close();
        }
    }

    private String buildSignalCacheKey(ProgramEntity entity) {
        String archiveHash = entity.getFileMd5() != null ? entity.getFileMd5() : "";
        String setupSource = entity.getSetupScript() != null ? entity.getSetupScript() : "";
        return FileUtil.calculateMD5((archiveHash + "\n" + setupSource).getBytes(StandardCharsets.UTF_8));
    }

    /** MATLAB 引擎状态（供前端 footer 显示） */
    public Result<Map<String, Object>> getEngineStatus() {
        Map<String, Object> data = new HashMap<>();
        if (!matlabEngineEnabled) {
            data.put("status", "disabled");
            data.put("message", "[MATLAB] 引擎模式未启用（matlab.engine.enabled=false）");
        } else if (engineDisabled) {
            data.put("status", "disabled");
            data.put("message", "[MATLAB] 引擎运行期不可用，仿真无法运行（已禁用，不再回退）");
        } else if (!MatlabSimulationRunner.isApiAvailable()) {
            data.put("status", "unavailable");
            data.put("message", "[MATLAB] Engine API 不可用（缺少原生库）");
        } else if (enginePool.isFailed()) {
            data.put("status", "failed");
            data.put("message", "[MATLAB] 引擎启动失败，仿真无法运行");
        } else if (prewarming.get()) {
            data.put("status", "warming");
            data.put("message", "[MATLAB] " + prewarmMessage + "，首次使用前请耐心等待...");
        } else if (enginePool.isReady()) {
            data.put("status", "ready");
            int idle = enginePool.idleCount();
            int total = enginePool.totalCount();
            int max = enginePool.maxEngines();
            int waiting = enginePool.waitingCount();
            data.put("message", "[MATLAB] 引擎已就绪（空闲 " + idle + "/" + total + "，上限 " + max + "，排队 " + waiting + "）");
            data.put("idle", idle);
            data.put("total", total);
            data.put("max", max);
            data.put("waiting", waiting);
        } else {
            data.put("status", "starting");
            data.put("message", "[MATLAB] 引擎启动中...");
        }
        return Result.success(data);
    }

    /** 重启 MATLAB 引擎（用户在引擎卡住时手动触发） */
    public Result<Map<String, Object>> restartEngine() {
        log.info("用户请求重启 MATLAB 引擎");
        engineDisabled = false;
        enginePool.restart();
        startPrewarmAsync();
        Map<String, Object> data = new HashMap<>();
        data.put("status", "starting");
        data.put("message", "[MATLAB] 引擎正在重启...");
        return Result.success("重启请求已发送", data);
    }

    public Result<Map<String, Object>> stop(String name, String version, String projectName) {
        log.info("停止请求: name={}, version={}, projectName={}", name, version, projectName);
        try {
            // 优先从内存缓存查找运行中的任务，避免 IGinX 查询（同 pause/resume）
            ProgramTaskEntity task = findRunningTask(name, version, projectName);
            if (task == null) {
                task = queryLatestTask(name, version, projectName);
            }
            if (task != null && task.getStatus().equals(TaskStatus.RUNNING.getValue())) {
                Long ts = task.getTimestamp();
                if (ts != null) {
                    // 引擎模式：直接给 Simulink 发 stop 命令，仿真立即终止且已记录数据保留
                    MatlabSimulationRunner runner = engineRunners.get(ts);
                    if (runner != null) {
                        runner.stopSimulation();
                        pauseFlags.remove(ts);
                        // 不在此处 setFinished：让 doRun 线程的 pollLoop 退出 + exportResults 完成后，
                        // 由 finally 块统一设 finished=true，确保"已执行停止命令"、"仿真结束"等日志能通过 SSE 推送到前端
                        updateTaskStatus(ts, TaskStatus.STOPPED.getValue(), null, null, null, null);
                        Map<String, Object> stopped = new HashMap<>();
                        stopped.put("status", TaskStatus.STOPPED.getValue());
                        return Result.success("已停止", stopped);
                    }
                    // 引擎不可用或 runner 已退出：直接标记停止
                    pauseFlags.remove(ts);
                    LiveDataBuffer buffer = liveDataMap.get(ts);
                    if (buffer != null) buffer.setFinished(true);
                    updateTaskStatus(ts, TaskStatus.STOPPED.getValue(), null, null, null, null);
                }
            }
            Map<String, Object> data = new HashMap<>();
            data.put("status", TaskStatus.STOPPED.getValue());
            return Result.success("已停止", data);
        } catch (Exception e) {
            log.error("停止异常", e);
            return Result.error("停止失败: " + e.getMessage());
        }
    }

    private void doRun(long taskTimestamp, ProgramEntity entity, String stopTimeParam, String fixedStepParam, String modelFileParam, Map<String, String> params) {
        File taskDir = new File(getTaskBaseDir(entity.getProjectName()), String.valueOf(taskTimestamp));
        try {
            taskDir.mkdirs();
            byte[] archiveBytes = downloadFromIginx(entity.getStoragePath(), entity.getChunkCount(), entity.getFileMd5());
            File archiveFile = new File(taskDir, entity.getFileName());
            Files.write(archiveFile.toPath(), archiveBytes);
            ArchiveUtil.extractArchive(archiveFile, taskDir, true);
            writeProgramConfig(taskDir, entity);

            File configFile = new File(taskDir, "program-config.json");
            if (!configFile.exists()) {
                updateTaskStatus(taskTimestamp, TaskStatus.FAILED.getValue(), "缺少 program-config.json", null, null, null);
                return;
            }
            ProgramConfig pgConfig = ProgramConfigMapper.parse(new String(Files.readAllBytes(configFile.toPath()), StandardCharsets.UTF_8));
            if (pgConfig == null) {
                updateTaskStatus(taskTimestamp, TaskStatus.FAILED.getValue(), "program-config.json 解析失败", null, null, null);
                return;
            }
            ProgramConfig.RuntimeConfig runtime = pgConfig.getRuntime();
            String preRunScript = runtime != null && StringUtils.hasText(runtime.getPreRunScript())
                    ? runtime.getPreRunScript() : "";
            boolean skipPreRunOnReuse = runtime != null && !Boolean.FALSE.equals(runtime.getSkipPreRunOnReuse());
            String modelFile = StringUtils.hasText(modelFileParam) ? modelFileParam
                    : (runtime != null ? runtime.getSimulinkModel() : "");
            double stopTime = StringUtils.hasText(stopTimeParam)
                    ? SimTimeUtil.parse(stopTimeParam, runtime != null ? runtime.getStopTime() : 30)
                    : (runtime != null ? runtime.getStopTime() : 30);
            // setupScript 内容已由 writeProgramConfig 从 entity.setupScript 写到 taskDir/dmg_setup.m
            // runner cd(taskDir) 后用固定函数名 dmg_setup 调用
            String setupScript = StringUtils.hasText(entity.getSetupScript()) ? "dmg_setup" : null;

            // 构造参数值映射：优先用前端传入，其次用 config 里的默认值
            Map<String, String> paramValues = new LinkedHashMap<>();
            if (pgConfig.getParameters() != null) {
                for (ProgramConfig.ParameterSpec p : pgConfig.getParameters()) {
                    String v = params.get(p.getKey());
                    if (!StringUtils.hasText(v)) v = p.getDefaultValue();
                    if (StringUtils.hasText(v)) paramValues.put(p.getKey(), v);
                }
            }

            String programDir = FileUtil.findProgramDir(taskDir, preRunScript);
            // dmg_setup.m 由 writeProgramConfig 写到 taskDir，但 runner 会 cd(programDir)，
            // 如果 programDir 是 taskDir 的子目录（解压目录），MATLAB 找不到 dmg_setup。
            // 把 dmg_setup.m 复制到 programDir，确保 cd 后能找到。
            File dmgSetupInTask = new File(taskDir, "dmg_setup.m");
            File dmgSetupInProgramDir = new File(programDir, "dmg_setup.m");
            if (dmgSetupInTask.exists() && !dmgSetupInProgramDir.exists()) {
                try {
                    Files.copy(dmgSetupInTask.toPath(), dmgSetupInProgramDir.toPath());
                } catch (Exception e) {
                    log.warn("复制 dmg_setup.m 到 programDir 失败", e);
                }
            }
            if (modelFile.isEmpty()) {
                File programDirFile = new File(programDir);
                File[] slxFiles = programDirFile.listFiles((d, n) ->
                        n.toLowerCase().endsWith(".slx") && !n.toLowerCase().endsWith(".slxc"));
                if (slxFiles != null && slxFiles.length > 0) {
                    modelFile = slxFiles[0].getName();
                    log.info("自动检测 Simulink 模型: {}", modelFile);
                }
            }
            File oldCsv = new File(taskDir, "signals.csv");
            if (oldCsv.exists()) oldCsv.delete();
            File oldLiveCsv = new File(taskDir, "signals_live.csv");
            if (oldLiveCsv.exists()) oldLiveCsv.delete();

            // 复用 run 方法中提前创建的 LiveDataBuffer（确保 SSE 订阅时已存在）
            // 使用 computeIfAbsent 保证变量 effectively final（lambda 中引用）
            LiveDataBuffer liveBuffer = liveDataMap.computeIfAbsent(taskTimestamp, k -> new LiveDataBuffer());
            File logFile = new File(taskDir, "run.log");

            if (!isEngineMode()) {
                updateTaskStatus(taskTimestamp, TaskStatus.FAILED.getValue(),
                        "MATLAB Engine 模式未启用，无法运行仿真（已移除 matlab -batch 回退方案）",
                        null, null, null);
                return;
            }
            if (prewarming.get()) {
                liveBuffer.appendLogLine("[MATLAB] 后台预热尚未完成，当前任务正在等待预热模型...");
                long deadline = System.currentTimeMillis() + TimeUnit.MINUTES.toMillis(20);
                while (prewarming.get() && System.currentTimeMillis() < deadline) {
                    Thread.sleep(1000);
                }
                if (prewarming.get()) {
                    updateTaskStatus(taskTimestamp, TaskStatus.FAILED.getValue(), "等待 MATLAB 预热超时", null, logFile.getAbsolutePath(), null);
                    return;
                }
                liveBuffer.appendLogLine("[MATLAB] 后台预热完成，开始运行仿真...");
            }
            int result = runWithEngine(taskTimestamp, taskDir, programDir, preRunScript, skipPreRunOnReuse,
                    modelFile, stopTime, fixedStepParam, paramValues, pgConfig.getParameters(), setupScript,
                    buildSignalCacheKey(entity), liveBuffer);
            if (result != RUN_OK) {
                // 用户停止 / 运行失败：状态已由停止端点或运行分支设置，不再覆盖。
                // signals.csv 已由引擎 exportResults() 写到 taskDir（如果仿真已开始），
                // results 接口会从 taskDir 兜底读取，无需在此入库。
                return;
            }

            File csv = new File(taskDir, "signals.csv");
            if (!csv.exists()) {
                updateTaskStatus(taskTimestamp, TaskStatus.FAILED.getValue(), "未生成 signals.csv", null, logFile.getAbsolutePath(), null);
                return;
            }
            log.info("程序运行成功，结果文件: {}", csv.getAbsolutePath());

            generateResultFiles(taskDir, entity, modelFile, stopTimeParam, fixedStepParam, paramValues, logFile);

            // Import result CSV to IGinX with key column
            String outputTable = importResultCsvToIginx(csv, entity, taskTimestamp, modelFile);

            updateTaskStatus(taskTimestamp, TaskStatus.SUCCESS.getValue(), null, csv.getAbsolutePath(), logFile.getAbsolutePath(), taskDir.getAbsolutePath());
            if (outputTable != null) {
                ProgramTaskEntity task = runningTasks.get(taskTimestamp);
                if (task == null) task = loadTask(taskTimestamp);
                if (task != null) {
                    task.setOutputTable(outputTable);
                    saveTask(task);
                }
            }
        } catch (Exception e) {
            log.error("运行程序失败", e);
            updateTaskStatus(taskTimestamp, TaskStatus.FAILED.getValue(), e.getMessage(), null, null, null);
        } finally {
            processMap.remove(taskTimestamp);
            runningTasks.remove(taskTimestamp);
            pauseFlags.remove(taskTimestamp);
            // 延迟清理 liveDataMap（让前端最后一次轮询能拿到 finished 状态）
            LiveDataBuffer buffer = liveDataMap.get(taskTimestamp);
            if (buffer != null) buffer.setFinished(true);
        }
    }

    /**
     * 通过 MATLAB Engine API 执行仿真：常驻 MATLAB 会话 + 异步 SimulationCommand，
     * 曲线随仿真真实推进，暂停/恢复/停止直接作用于 Simulink 求解器。
     *
     * @return RUN_OK 正常结束；RUN_STOPPED 用户停止；RUN_FAILED 运行失败（状态已写）
     */
    private int runWithEngine(long taskTimestamp, File taskDir, String programDir, String preRunScript,
                              boolean skipPreRunOnReuse, String modelFile, double stopTime, String fixedStep,
                              Map<String, String> paramValues, List<ProgramConfig.ParameterSpec> parameters,
                              String setupScript, String signalCacheKey, LiveDataBuffer liveBuffer) {
        if (!StringUtils.hasText(modelFile)) {
            log.warn("未指定 Simulink 模型");
            updateTaskStatus(taskTimestamp, TaskStatus.FAILED.getValue(), "未指定 Simulink 模型", null, null, null);
            return RUN_FAILED;
        }
        String modelName = modelFile.replaceAll("\\.(slx|mdl)$", "");
        MatlabSimulationRunner runner = new MatlabSimulationRunner(taskDir, programDir, preRunScript,
                skipPreRunOnReuse, modelName, stopTime, fixedStep, paramValues, parameters, setupScript,
                signalCacheKey, new MatlabSimulationRunner.LiveSink() {
                    @Override
                    public void onStopTime(double alignedStopTime) {
                        liveBuffer.setStopTime(alignedStopTime);
                    }

                    @Override
                    public void onHeaders(List<String> headers) {
                        liveBuffer.setHeaders(headers);
                    }

                    @Override
                    public void onRows(List<String[]> rows) {
                        liveBuffer.appendRows(rows);
                    }

                    @Override
                    public void onLog(String line) {
                        liveBuffer.appendLogLine(line);
                    }
                },
                enginePool);
        engineRunners.put(taskTimestamp, runner);
        try {
            // borrow 成功（或即将成功），从 QUEUED 切换到 RUNNING
            ProgramTaskEntity curTask = runningTasks.get(taskTimestamp);
            if (curTask != null && curTask.getStatus().equals(TaskStatus.QUEUED.getValue())) {
                updateTaskStatus(taskTimestamp, TaskStatus.RUNNING.getValue(), null, null, null, null);
            }
            runner.run();
            if (runner.isUserStopped()) {
                log.info("引擎仿真被用户停止，仿真时间={}", runner.getLastSimTime());
                return RUN_STOPPED;
            }
            log.info("引擎仿真完成：停止时间={}，最终仿真时间={}", runner.getAlignedStopTime(), runner.getLastSimTime());
            return RUN_OK;
        } catch (Throwable t) {
            if (isEngineUnavailable(t)) {
                engineDisabled = true;
                log.error("MATLAB Engine 不可用，本次及后续仿真将直接 FAILED。"
                        + "请确认本机已安装与 engine.jar 匹配的 MATLAB 版本，"
                        + "或通过 matlab.engine.home 指定安装目录。原因: {}", t.toString());
                updateTaskStatus(taskTimestamp, TaskStatus.FAILED.getValue(),
                        "MATLAB Engine 不可用: " + t.getMessage(), null,
                        new File(taskDir, "run.log").getAbsolutePath(), null);
                return RUN_FAILED;
            }
            log.error("引擎仿真失败", t);
            updateTaskStatus(taskTimestamp, TaskStatus.FAILED.getValue(), t.getMessage(), null,
                    new File(taskDir, "run.log").getAbsolutePath(), null);
            return RUN_FAILED;
        } finally {
            engineRunners.remove(taskTimestamp);
            runner.close();
        }
    }

    /** 判断异常是否源于 MATLAB 原生库缺失 */
    private boolean isEngineUnavailable(Throwable t) {
        for (Throwable c = t; c != null; c = c.getCause()) {
            if (c instanceof UnsatisfiedLinkError || c instanceof NoClassDefFoundError
                    || c instanceof ExceptionInInitializerError) {
                return true;
            }
            if (c == c.getCause()) break;
        }
        return false;
    }


    /**
     * 线程安全的实时数据缓冲：MATLAB 写 CSV → 监控线程读 CSV → append 到这里 → 前端轮询/SSE 取增量
     * 支持 SSE 订阅：有新数据时主动推送给所有订阅者，避免前端频繁轮询
     */
    public static class LiveDataBuffer {
        private volatile List<String> headers = new ArrayList<>();
        private final List<String[]> rows = Collections.synchronizedList(new ArrayList<>());
        private volatile int lastIndex = 0;
        private volatile boolean finished = false;
        // 对齐到固定步长后的停止时间（引擎模式下由 MATLAB 实际生效值回填）
        private volatile double stopTime = 0.0;
        // 最新一条 MATLAB 日志（供前端 footer 显示）
        private volatile String logLine = "";
        // 当前任务状态与错误（解决仿真结束时 SSE 缺少 status，前端出现 UNKNOWN 的问题）
        private volatile String taskStatus = "";
        private volatile String taskError = "";
        // SSE 订阅者列表
        private final List<SseEmitter> emitters = Collections.synchronizedList(new ArrayList<>());

        public void setHeaders(List<String> h) {
            this.headers = h;
            // header 变化时清空已累积的行（列数/列序可能不匹配），并通知前端整体替换
            rows.clear();
            lastIndex = 0;
            Map<String, Object> payload = buildPayload(new ArrayList<>());
            payload.put("reset", true);
            notifySubscribers(payload);
        }

        public List<String> getHeaders() { return headers; }

        public void setStopTime(double t) { this.stopTime = t; }

        public void appendRows(List<String[]> newRows) {
            rows.addAll(newRows);
            // 有新数据时主动推送给所有 SSE 订阅者
            notifySubscribers(buildPayload(newRows));
        }

        public void appendLogLine(String line) {
            this.logLine = line;
            notifySubscribers(buildPayload(new ArrayList<>()));
        }

        /** 更新任务状态/错误，不主动推送，随下一次数据/结束事件一并下发 */
        public void setTaskInfo(String status, String error) {
            this.taskStatus = status;
            this.taskError = error;
        }

        /** 返回从 lastIndex 到末尾的增量数据，并更新 lastIndex（轮询降级用） */
        public synchronized Map<String, Object> getIncremental() {
            Map<String, Object> result = new HashMap<>();
            result.put("headers", headers);
            int total = rows.size();
            if (lastIndex < total) {
                List<String[]> incremental = new ArrayList<>(rows.subList(lastIndex, total));
                result.put("newRows", incremental);
                lastIndex = total;
            } else {
                result.put("newRows", new ArrayList<String[]>());
            }
            result.put("totalRows", total);
            result.put("currentSimTime", getCurrentSimTime());
            result.put("stopTime", stopTime);
            result.put("finished", finished);
            result.put("logLine", logLine);
            result.put("status", taskStatus);
            result.put("lastError", taskError);
            return result;
        }

        /** 注册 SSE 订阅者，连接断开时自动移除 */
        public void subscribe(SseEmitter emitter) {
            emitters.add(emitter);
            // 心跳保活：MATLAB 仿真启动可能需要 2-3 分钟，期间无数据推送，
            // 不发心跳会导致 SseEmitter 超时或代理/浏览器断开连接
            final boolean[] alive = {true};
            Thread heartbeat = new Thread(() -> {
                while (alive[0]) {
                    try { Thread.sleep(15000); } catch (InterruptedException e) { break; }
                    if (alive[0]) {
                        sendToEmitter(emitter, Collections.singletonMap("heartbeat", true));
                    }
                }
            }, "sse-heartbeat");
            heartbeat.setDaemon(true);
            heartbeat.start();
            emitter.onCompletion(() -> { alive[0] = false; emitters.remove(emitter); });
            emitter.onTimeout(() -> { alive[0] = false; emitters.remove(emitter); emitter.complete(); });
            emitter.onError(e -> { alive[0] = false; emitters.remove(emitter); });
            // 订阅时立即推送已有数据（避免订阅后到下个 chunk 之间的空窗）
            Map<String, Object> snapshot = new HashMap<>();
            snapshot.put("headers", headers);
            int total = rows.size();
            snapshot.put("newRows", total > 0 ? new ArrayList<>(rows) : new ArrayList<>());
            snapshot.put("totalRows", total);
            snapshot.put("currentSimTime", getCurrentSimTime());
            snapshot.put("stopTime", stopTime);
            snapshot.put("finished", finished);
            snapshot.put("logLine", logLine);
            snapshot.put("status", taskStatus);
            snapshot.put("lastError", taskError);
            // 快照包含全量数据（首次订阅或断线重连），前端需整体替换而非追加，避免重复
            snapshot.put("reset", true);
            sendToEmitter(emitter, snapshot);
        }

        /** 向所有订阅者推送数据 */
        private void notifySubscribers(Map<String, Object> payload) {
            if (emitters.isEmpty()) return;
            // 复制一份避免遍历时并发修改
            List<SseEmitter> snapshot = new ArrayList<>(emitters);
            for (SseEmitter emitter : snapshot) {
                sendToEmitter(emitter, payload);
            }
        }

        private void sendToEmitter(SseEmitter emitter, Map<String, Object> payload) {
            try {
                emitter.send(SseEmitter.event().data(payload));
            } catch (Exception e) {
                emitters.remove(emitter);
            }
        }

        private Map<String, Object> buildPayload(List<String[]> newRows) {
            Map<String, Object> payload = new HashMap<>();
            payload.put("headers", headers);
            payload.put("newRows", newRows);
            payload.put("totalRows", rows.size());
            payload.put("currentSimTime", getCurrentSimTime());
            payload.put("stopTime", stopTime);
            payload.put("finished", finished);
            payload.put("logLine", logLine);
            payload.put("status", taskStatus);
            payload.put("lastError", taskError);
            return payload;
        }

        private double getCurrentSimTime() {
            if (rows.isEmpty()) return 0.0;
            String[] last = rows.get(rows.size() - 1);
            if (last != null && last.length > 0) {
                try { return Double.parseDouble(last[0]); } catch (NumberFormatException e) { return 0.0; }
            }
            return 0.0;
        }

        public void setFinished(boolean f) {
            this.finished = f;
            if (f) {
                // 仿真结束：推送最终状态后关闭所有 SSE 连接
                notifySubscribers(buildPayload(new ArrayList<>()));
                List<SseEmitter> snapshot = new ArrayList<>(emitters);
                for (SseEmitter emitter : snapshot) {
                    try { emitter.complete(); } catch (Exception ignored) {}
                }
                emitters.clear();
            }
        }

        public boolean isFinished() { return finished; }
        public int getRowCount() { return rows.size(); }
    }

    /**
     * 查询实时仿真数据（增量）
     */
    public Result<Map<String, Object>> getLiveData(String name, String version, String projectName) {
        ProgramTaskEntity task = queryLatestTask(name, version, projectName);
        if (task == null) return Result.error("无运行任务记录");

        // 检查是否因服务重启导致任务实际已终止
        checkRestartedTask(task);

        LiveDataBuffer buffer = liveDataMap.get(task.getTimestamp());
        Map<String, Object> data = new HashMap<>();
        if (buffer != null) {
            data.putAll(buffer.getIncremental());
        } else {
            data.put("newRows", new ArrayList<String[]>());
            data.put("totalRows", 0);
            data.put("currentSimTime", 0.0);
            data.put("finished", !task.getStatus().equals(TaskStatus.RUNNING.getValue()));
        }
        // 以任务实体中的状态为准，覆盖 buffer 中可能滞后的值
        data.put("status", task.getStatus());
        data.put("lastError", task.getError());
        return Result.success(data);
    }

    /**
     * SSE 订阅实时仿真数据：服务器在有新数据时主动推送，避免前端频繁轮询
     * 返回 SseEmitter，Spring MVC 异步处理保持连接
     */
    public SseEmitter subscribeLiveData(String name, String version, String projectName) {
        // 超时设为 30 分钟：引擎模式下曲线随真实仿真推进，长仿真 + 暂停都会拉长连接时间
        SseEmitter emitter = new SseEmitter(1800000L);

        // 优先取内存中最新运行/排队任务，避免新任务落盘延迟串到旧任务
        ProgramTaskEntity task = findLatestRunningOrQueuedTask(name, version, projectName);
        if (task == null) task = queryLatestTask(name, version, projectName);
        if (task == null) {
            try {
                emitter.send(SseEmitter.event().data(Collections.singletonMap("error", "无运行任务记录")));
                emitter.complete();
            } catch (Exception ignored) {}
            return emitter;
        }

        // 检查是否因服务重启导致任务实际已终止
        checkRestartedTask(task);

        LiveDataBuffer buffer = liveDataMap.get(task.getTimestamp());
        if (buffer == null) {
            // buffer 已被清理（仿真已结束），立即推送结束状态
            try {
                Map<String, Object> endPayload = new HashMap<>();
                endPayload.put("status", task.getStatus());
                endPayload.put("lastError", task.getError());
                endPayload.put("finished", true);
                endPayload.put("newRows", new ArrayList<String[]>());
                endPayload.put("totalRows", 0);
                endPayload.put("currentSimTime", 0.0);
                emitter.send(SseEmitter.event().data(endPayload));
                emitter.complete();
            } catch (Exception ignored) {}
            return emitter;
        }

        // 订阅 buffer，有新数据时由 buffer 主动推送
        buffer.subscribe(emitter);

        // 如果仿真已经结束，订阅时会自动收到 finished 数据，但 emitter 可能未 complete
        if (buffer.isFinished()) {
            try { emitter.complete(); } catch (Exception ignored) {}
        }

        return emitter;
    }

    /**
     * 暂停仿真：创建 pause.flag 文件，progressiveReveal 检测到后进入等待循环。
     * 优先从内存缓存 runningTasks 查找任务，避免查 IGinX（消除锁竞争和延迟，
     * 这是导致 ERR_INCOMPLETE_CHUNKED_ENCODING 的根因——IGinX 全局锁等待
     * 使请求长时间阻塞，Tomcat 最终关闭连接导致响应不完整）。
     */
    public Result<Map<String, Object>> pause(String name, String version, String projectName) {
        log.info("暂停请求: name={}, version={}, projectName={}", name, version, projectName);
        try {
            // 优先从内存缓存查找，避免 IGinX 查询
            ProgramTaskEntity task = findRunningTask(name, version, projectName);
            if (task == null) {
                // 降级：查 IGinX（仅在缓存未命中时，如服务重启后恢复运行状态）
                task = queryLatestTask(name, version, projectName);
            }
            if (task == null || !task.getStatus().equals(TaskStatus.RUNNING.getValue())) {
                log.warn("暂停失败：无运行中的仿真任务 (found={}, status={})",
                        task != null, task != null ? task.getStatus() : "null");
                return Result.error("无运行中的仿真任务");
            }
            Long ts = task.getTimestamp();
            if (ts == null) {
                log.warn("暂停失败：任务时间戳为空");
                return Result.error("任务时间戳为空");
            }
            pauseFlags.put(ts, true);
            // 引擎模式：SimulationCommand pause，求解器真正冻结（仿真时间不再推进）
            MatlabSimulationRunner runner = engineRunners.get(ts);
            if (runner != null) {
                runner.pause();
                log.info("已暂停仿真（引擎模式）: timestamp={}", ts);
                Map<String, Object> paused = new HashMap<>();
                paused.put("status", "PAUSED");
                return Result.success("已暂停", paused);
            }
            File taskDir = new File(getTaskBaseDir(projectName != null ? projectName : task.getProjectName()), String.valueOf(ts));
            File pauseFlag = new File(taskDir, "pause.flag");
            if (!pauseFlag.exists()) {
                try {
                    Files.createFile(pauseFlag.toPath());
                } catch (IOException e) {
                    log.warn("创建 pause.flag 失败: {}", e.getMessage());
                }
            }
            log.info("已暂停任务: timestamp={}", ts);
            Map<String, Object> data = new HashMap<>();
            data.put("status", "PAUSED");
            return Result.success("已暂停", data);
        } catch (Exception e) {
            log.error("暂停异常", e);
            return Result.error("暂停失败: " + e.getMessage());
        }
    }

    /**
     * 恢复仿真：删除 pause.flag 文件，progressiveReveal 检测到后继续释放数据。
     * 同 pause，优先从内存缓存查找任务，避免 IGinX 查询。
     */
    public Result<Map<String, Object>> resume(String name, String version, String projectName) {
        log.info("恢复请求: name={}, version={}, projectName={}", name, version, projectName);
        try {
            ProgramTaskEntity task = findRunningTask(name, version, projectName);
            if (task == null) {
                task = queryLatestTask(name, version, projectName);
            }
            if (task == null) {
                return Result.error("无运行任务记录");
            }
            Long ts = task.getTimestamp();
            if (ts == null) {
                return Result.error("任务时间戳为空");
            }
            pauseFlags.remove(ts);
            // 引擎模式：SimulationCommand continue，从冻结的仿真时刻继续推进
            MatlabSimulationRunner runner = engineRunners.get(ts);
            if (runner != null) {
                runner.resume();
                log.info("已恢复仿真（引擎模式）: timestamp={}", ts);
                Map<String, Object> resumed = new HashMap<>();
                resumed.put("status", "RUNNING");
                return Result.success("已恢复", resumed);
            }
            File taskDir = new File(getTaskBaseDir(projectName != null ? projectName : task.getProjectName()), String.valueOf(ts));
            try {
                Files.deleteIfExists(new File(taskDir, "pause.flag").toPath());
            } catch (IOException e) {
                log.warn("删除 pause.flag 失败: {}", e.getMessage());
            }
            log.info("已恢复任务: timestamp={}", ts);
            Map<String, Object> data = new HashMap<>();
            data.put("status", "RUNNING");
            return Result.success("已恢复", data);
        } catch (Exception e) {
            log.error("恢复异常", e);
            return Result.error("恢复失败: " + e.getMessage());
        }
    }

    private void generateResultFiles(File taskDir, ProgramEntity entity, String modelFile,
                                     String stopTime, String fixedStep, Map<String, String> params,
                                     File logFile) {
        try {
            // metadata.json
            ObjectNode metadata = mapper.createObjectNode();
            metadata.put("softwareVersion", "Simulation V1.0");
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
            scenario.put("modelFile", modelFile != null ? modelFile : "");
            // 动态参数写入 scenario（按实际传入的 params，不再硬编码 npCommand/loadPower）
            if (params != null) {
                ObjectNode paramsNode = scenario.putObject("params");
                params.forEach(paramsNode::put);
            }
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
        String resultDirPath = null;
        ProgramEntity entity = null;
        ProgramTaskEntity task = queryLatestTask(name, version, projectName);
        if (task != null) {
            resultDirPath = task.getResultDir();
            if (resultDirPath == null && task.getResultCsvPath() != null) {
                resultDirPath = new File(task.getResultCsvPath()).getParent();
            }
        }
        if (resultDirPath == null) {
            entity = queryMeta(name, version, projectName);
            if (entity == null) throw new Exception("程序不存在");
            resultDirPath = entity.getLastResultDir();
            if (resultDirPath == null && entity.getLastResultCsv() != null) {
                resultDirPath = new File(entity.getLastResultCsv()).getParent();
            }
        }
        if (resultDirPath == null) throw new Exception("无运行结果目录，请先运行仿真");
        File resultDir = new File(resultDirPath);
        if (!resultDir.exists()) throw new Exception("结果目录不存在: " + resultDir.getAbsolutePath());

        // 如果 metadata.json 不存在，说明是旧运行结果，补充生成
        File metadataFile = new File(resultDir, "metadata.json");
        if (!metadataFile.exists()) {
            if (entity == null) entity = queryMeta(name, version, projectName);
            File logFile = entity != null && entity.getLastLogPath() != null ? new File(entity.getLastLogPath()) : null;
            generateResultFiles(resultDir, entity, "", "", "", new java.util.LinkedHashMap<>(), logFile);
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
        String resultDirPath = null;
        ProgramTaskEntity task = queryLatestTask(name, version, projectName);
        if (task != null) {
            resultDirPath = task.getResultDir();
            if (resultDirPath == null && task.getResultCsvPath() != null) {
                resultDirPath = new File(task.getResultCsvPath()).getParent();
            }
        }
        if (resultDirPath == null) {
            ProgramEntity entity = queryMeta(name, version, projectName);
            if (entity == null) throw new Exception("程序不存在");
            resultDirPath = entity.getLastResultDir();
            if (resultDirPath == null && entity.getLastResultCsv() != null) {
                resultDirPath = new File(entity.getLastResultCsv()).getParent();
            }
        }
        if (resultDirPath == null) throw new Exception("无运行结果目录，请先运行仿真");
        File resultDir = new File(resultDirPath);
        if (!resultDir.exists()) throw new Exception("结果目录不存在: " + resultDir.getAbsolutePath());
        File overviewFile = new File(resultDir, "overview.png");
        Files.write(overviewFile.toPath(), pngData);
        log.info("overview.png 已保存到结果目录: {}", overviewFile.getAbsolutePath());
    }

    public byte[] downloadSignalFile(String name, String version, String format, String projectName) throws Exception {
        String resultDirPath = null;
        ProgramTaskEntity task = queryLatestTask(name, version, projectName);
        if (task != null) {
            resultDirPath = task.getResultDir();
            if (resultDirPath == null && task.getResultCsvPath() != null) {
                resultDirPath = new File(task.getResultCsvPath()).getParent();
            }
        }
        if (resultDirPath == null) {
            ProgramEntity entity = queryMeta(name, version, projectName);
            if (entity == null) throw new Exception("程序不存在");
            resultDirPath = entity.getLastResultDir();
            if (resultDirPath == null && entity.getLastResultCsv() != null) {
                resultDirPath = new File(entity.getLastResultCsv()).getParent();
            }
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
            String actual = FileUtil.calculateMD5(data);
            if (!actual.equalsIgnoreCase(expectedMd5)) {
                throw new Exception("程序包 MD5 校验失败");
            }
        }
        return data;
    }

    // ==================== Program Task IGinX persistence ====================

    private String importResultCsvToIginx(File csvFile, ProgramEntity entity, long taskTimestamp, String modelFile) {
        try {
            // Read original CSV
            List<String> lines = Files.readAllLines(csvFile.toPath(), StandardCharsets.UTF_8);
            if (lines.isEmpty()) return null;

            String[] headers = lines.get(0).split(",");
            int timeColIdx = -1;
            for (int i = 0; i < headers.length; i++) {
                if (headers[i].trim().equalsIgnoreCase("time")) {
                    timeColIdx = i;
                    break;
                }
            }
            if (timeColIdx == -1) {
                log.warn("CSV中未找到time列，跳过IGinX导入");
                return null;
            }

            // Build output table path from model file name
            String modelName = "";
            if (modelFile != null && !modelFile.isEmpty()) {
                modelName = modelFile.replace(".", "_");
            }
            String proj = entity.getProjectName() != null ? entity.getProjectName() : ProjectContext.getCurrentProject("unknown");
            String outputTable = proj + "." + "program_result" + "." + entity.getName() + "_" + entity.getVersion() + "." + modelName + ".signals_" + taskTimestamp;
            String newFileName = "signals_keyed_" + taskTimestamp + ".csv";
            File newCsv = new File(csvFile.getParentFile(), newFileName);

            StringBuilder sb = new StringBuilder();
            // Header: key,time,col2,col3,...
            sb.append("key,");
            sb.append(lines.get(0));
            sb.append("\n");

            // Data rows: convert time (seconds) to millisecond timestamp, ensure numeric columns are double
            for (int i = 1; i < lines.size(); i++) {
                String[] cols = lines.get(i).split(",");
                if (cols.length <= timeColIdx) continue;
                double timeSec;
                try {
                    timeSec = Double.parseDouble(cols[timeColIdx].trim());
                } catch (NumberFormatException e) {
                    continue;
                }
                long keyTs = (long) (timeSec * 1000);
                sb.append(keyTs).append(",");
                for (int j = 0; j < cols.length; j++) {
                    if (j > 0) sb.append(",");
                    String val = cols[j].trim();
                    // Try to parse as number and format as double
                    try {
                        double dval = Double.parseDouble(val);
                        sb.append(dval);
                    } catch (NumberFormatException e) {
                        sb.append(cols[j]);
                    }
                }
                sb.append("\n");
            }

            Files.write(newCsv.toPath(), sb.toString().getBytes(StandardCharsets.UTF_8));
            log.info("已生成带key列的CSV: {}", newCsv.getAbsolutePath());

            // Import to IGinX
//            String uploadedFileName = taskTimestamp + "_signals.csv";
            long recordsNum = dataTableService.importCsvFile(newCsv.toPath(), outputTable, newFileName, null, entity.getAuthor());
            log.info("结果CSV已入库到 {}, 记录数: {}", outputTable, recordsNum);

            return outputTable;
        } catch (Exception e) {
            log.error("导入结果CSV到IGinX失败", e);
            return null;
        }
    }

    private void saveTask(ProgramTaskEntity task) {
        try {
            List<Point> points = new ArrayList<>();
            long ts = task.getTimestamp();
            String basePath = TASK_DATA_PREFIX;
            points.add(ConvertUtil.createFieldPoint(basePath, "timestamp", ts, ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "programName", task.getProgramName(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "programVersion", task.getProgramVersion(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "projectName", task.getProjectName(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "startTime", task.getStartTime(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "endTime", task.getEndTime(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "status", task.getStatus(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "error", task.getError(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "stopTime", task.getStopTime(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "fixedStep", task.getFixedStep(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "npCommand", task.getNpCommand(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "loadPower", task.getLoadPower(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "paramsJson", task.getParamsJson(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "modelFile", task.getModelFile(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "resultCsvPath", task.getResultCsvPath(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "logPath", task.getLogPath(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "resultDir", task.getResultDir(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "outputTable", task.getOutputTable(), ts));
            points.add(ConvertUtil.createFieldPoint(basePath, "runLog", task.getRunLog(), ts));
            iginxClient.getWriteClient().writePoints(points.stream().filter(Objects::nonNull).collect(Collectors.toList()));
            log.info("程序任务记录已保存: timestamp={}, program={}", ts, task.getProgramName());
        } catch (Exception e) {
            log.error("保存程序任务记录失败", e);
        }
    }

    private void updateTaskStatus(long taskTimestamp, String status, String error, String csvPath, String logPath, String resultDir) {
        ProgramTaskEntity task = runningTasks.get(taskTimestamp);
        if (task == null) task = loadTask(taskTimestamp);
        if (task == null) return;
        task.setStatus(status);
        task.setError(error);
        LiveDataBuffer buffer = liveDataMap.get(taskTimestamp);
        if (buffer != null) buffer.setTaskInfo(status, error);
        task.setEndTime(System.currentTimeMillis());
        if (csvPath != null) task.setResultCsvPath(csvPath);
        if (logPath != null) task.setLogPath(logPath);
        if (resultDir != null) task.setResultDir(resultDir);
        // Read log content (last 20000 chars) and save to entity
        String actualLogPath = logPath != null ? logPath : task.getLogPath();
        if (actualLogPath != null) {
            File logFile = new File(actualLogPath);
            if (logFile.exists()) {
                try {
                    String logContent = new String(Files.readAllBytes(logFile.toPath()), Charset.forName("GBK"));
                    if (logContent.length() > 20000) {
                        logContent = logContent.substring(logContent.length() - 20000);
                    }
                    task.setRunLog(logContent);
                } catch (Exception e) {
                    log.error("读取运行日志失败", e);
                }
            }
        }
        saveTask(task);
    }

    private ProgramTaskEntity loadTask(Long timestamp) {
        try {
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(ProgramTaskEntity.class, TASK_DATA_PREFIX);
            IginXTable table = iginxClient.getQueryClient().query(
                SimpleQuery.builder()
                    .addMeasurements(new HashSet<>(measurements))
                    .startKey(timestamp - 1)
                    .endKey(timestamp + 1)
                    .build()
            );
            if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) return null;
            IginXRecord record = table.getRecords().get(0);
            ProgramTaskEntity task = new ProgramTaskEntity();
            task.setTimestamp(timestamp);
            for (String path : measurements) {
                Object value = record.getValue(path);
                if (value == null) continue;
                String fieldName = path.substring(path.lastIndexOf('.') + 1);
                String strValue = value instanceof byte[] ? ConvertUtil.bytesToString((byte[]) value) : value.toString();
                switch (fieldName) {
                    case "programName": task.setProgramName(strValue); break;
                    case "programVersion": task.setProgramVersion(strValue); break;
                    case "projectName": task.setProjectName(strValue); break;
                    case "startTime": task.setStartTime(value instanceof Number ? ((Number) value).longValue() : null); break;
                    case "endTime": task.setEndTime(value instanceof Number ? ((Number) value).longValue() : null); break;
                    case "status": task.setStatus(strValue); break;
                    case "error": task.setError(strValue); break;
                    case "stopTime": task.setStopTime(strValue); break;
                    case "fixedStep": task.setFixedStep(strValue); break;
                    case "npCommand": task.setNpCommand(strValue); break;
                    case "loadPower": task.setLoadPower(strValue); break;
                    case "paramsJson": task.setParamsJson(strValue); break;
                    case "modelFile": task.setModelFile(strValue); break;
                    case "resultCsvPath": task.setResultCsvPath(strValue); break;
                    case "logPath": task.setLogPath(strValue); break;
                    case "resultDir": task.setResultDir(strValue); break;
                    case "outputTable": task.setOutputTable(strValue); break;
                    case "runLog": task.setRunLog(strValue); break;
                }
            }
            return task;
        } catch (Exception e) {
            log.error("加载程序任务记录失败: timestamp={}", timestamp, e);
            return null;
        }
    }

    /**
     * 从内存缓存 runningTasks 中查找运行中的任务（避免查 IGinX，消除锁竞争和延迟）。
     * pause/resume/stop 等高频控制接口优先使用此方法，仅在缓存未命中时降级到 queryLatestTask。
     */
    private ProgramTaskEntity findRunningTask(String name, String version, String projectName) {
        for (ProgramTaskEntity task : runningTasks.values()) {
            if (task == null) continue;
            boolean match = true;
            if (name != null && !name.equals(task.getProgramName())) match = false;
            if (version != null && !version.equals(task.getProgramVersion())) match = false;
            if (projectName != null && !projectName.equals(task.getProjectName())) match = false;
            if (match && task.getStatus().equals(TaskStatus.RUNNING.getValue())) {
                return task;
            }
        }
        return null;
    }

    /**
     * 从内存缓存 runningTasks 中查找最新运行中/排队任务（优先于 DB 查询）。
     * 避免新任务落盘延迟导致 /live-stream 串到旧的结束任务。
     */
    private ProgramTaskEntity findLatestRunningOrQueuedTask(String name, String version, String projectName) {
        ProgramTaskEntity latest = null;
        for (ProgramTaskEntity task : runningTasks.values()) {
            if (task == null || task.getTimestamp() == null) continue;
            boolean match = true;
            if (name != null && !name.equals(task.getProgramName())) match = false;
            if (version != null && !version.equals(task.getProgramVersion())) match = false;
            if (projectName != null && !projectName.equals(task.getProjectName())) match = false;
            if (!match) continue;
            if (!task.getStatus().equals(TaskStatus.RUNNING.getValue()) && !task.getStatus().equals(TaskStatus.QUEUED.getValue())) continue;
            if (latest == null || task.getTimestamp() > latest.getTimestamp()) {
                latest = task;
            }
        }
        return latest;
    }

    private ProgramTaskEntity queryLatestTask(String programName, String programVersion, String projectName) {
        try {
            StringBuilder sql = new StringBuilder("SELECT * FROM " + TASK_DATA_PREFIX + " WHERE 1=1");
            if (StringUtils.hasText(programName)) sql.append(" AND programName='").append(programName).append("'");
            if (StringUtils.hasText(programVersion)) sql.append(" AND programVersion='").append(programVersion).append("'");
            if (StringUtils.hasText(projectName)) sql.append(" AND projectName='").append(projectName).append("'");
            sql.append(" ORDER BY timestamp DESC LIMIT 1;");
            log.info("查询最新程序任务SQL: {}", sql);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            if (records == null || records.isEmpty()) return null;
            Map<String, Object> row = records.get(0);
            ProgramTaskEntity task = new ProgramTaskEntity();
            row.forEach((k, v) -> {
                String fieldName = k.replace(TASK_DATA_PREFIX + ".", "");
                ConvertUtil.setEntityField(task, TASK_DATA_PREFIX, fieldName, v);
            });
            return task;
        } catch (Exception e) {
            log.error("查询最新程序任务记录失败", e);
            return null;
        }
    }

    private List<Map<String, String>> buildKpiParamsFromTask(ProgramTaskEntity task, List<Map<String, String>> originalKpiParams) {
        if (originalKpiParams == null) originalKpiParams = new ArrayList<>();
        List<Map<String, String>> kpiParams = new ArrayList<>(originalKpiParams);
        // Only override Np and Mkp from task input if present
        for (int i = 0; i < kpiParams.size(); i++) {
            Map<String, String> kpi = kpiParams.get(i);
            String name = kpi.get("name");
            if ("Np".equals(name) && task.getNpCommand() != null && !task.getNpCommand().isEmpty()) {
                kpi.put("value", task.getNpCommand());
            } else if ("Mkp".equals(name) && task.getLoadPower() != null && !task.getLoadPower().isEmpty()) {
                kpi.put("value", task.getLoadPower());
            }
        }
        return kpiParams;
    }

    /**
     * 检查任务是否因服务重启而实际已终止。
     * 判断依据：任务创建时间早于服务启动时间（说明是重启前遗留），
     * 且内存中 engineRunners/runningTasks 都没有该任务。
     */
    private boolean checkRestartedTask(ProgramTaskEntity task) {
        if (task == null) return false;
        if (!task.getStatus().equals(TaskStatus.RUNNING.getValue()) && !task.getStatus().equals(TaskStatus.QUEUED.getValue())) {
            return false;
        }
        Long ts = task.getTimestamp();
        if (ts == null) return false;
        // 任务创建于本次服务启动之前 → 重启前遗留，进程已不存在
        if (ts >= serviceStartTime) {
            // 本次启动后创建的任务，检查内存中是否还在
            if (engineRunners.get(ts) != null || runningTasks.get(ts) != null) {
                return false;
            }
        }
        updateTaskStatus(ts, TaskStatus.FAILED.getValue(), "服务重启，仿真进程已终止", null, null, null);
        task.setStatus(TaskStatus.FAILED.getValue());
        task.setError("服务重启，仿真进程已终止");
        return true;
    }

    public Result<Map<String, Object>> results(String name, String version, String projectName) {
        ProgramTaskEntity task = queryLatestTask(name, version, projectName);
        if (task == null) return Result.error("无运行任务记录");

        // 检查是否因服务重启导致任务实际已终止
        checkRestartedTask(task);

        Map<String, Object> data = new HashMap<>();
        // 检查是否处于暂停状态：pause 端点只设内存 pauseFlags + pause.flag 文件，不更新 IGinX 状态。
        // 刷新页面后 results 需要返回 "paused" 让前端恢复按钮显示"恢复"。
        boolean isPaused = Boolean.TRUE.equals(pauseFlags.get(task.getTimestamp()));
        if (!isPaused && task.getStatus().equals(TaskStatus.RUNNING.getValue()) && task.getTimestamp() != null) {
            // 降级检查：服务重启后 pauseFlags 丢失，用 pause.flag 文件判断
            File taskDir = new File(getTaskBaseDir(projectName), String.valueOf(task.getTimestamp()));
            isPaused = new File(taskDir, "pause.flag").exists();
        }
        data.put("status", isPaused ? "paused" : task.getStatus());
        data.put("lastError", task.getError());
        data.put("lastRunTime", task.getStartTime());
        data.put("npCommand", task.getNpCommand());
        data.put("loadPower", task.getLoadPower());
        // 解析 paramsJson，把动态参数也平铺到 data 中，供前端 KPI 回显
        if (task.getParamsJson() != null && !task.getParamsJson().isEmpty()) {
            try {
                Map<String, Object> paramMap = mapper.readValue(task.getParamsJson(),
                        new com.fasterxml.jackson.core.type.TypeReference<Map<String, Object>>() {});
                for (Map.Entry<String, Object> entry : paramMap.entrySet()) {
                    if (entry.getValue() != null) {
                        data.putIfAbsent(entry.getKey(), entry.getValue());
                    }
                }
            } catch (Exception e) {
                log.warn("解析 paramsJson 失败: {}", e.getMessage());
            }
        }
        // 返回对齐后的停止时间，刷新页面时前端据此设置时间轴上限
        if (task.getStopTime() != null) {
            data.put("stopTime", task.getStopTime());
        }
        if (task.getFixedStep() != null) {
            data.put("fixedStep", task.getFixedStep());
        }
        if (task.getModelFile() != null) {
            data.put("modelFile", task.getModelFile());
        }

        if (task.getRunLog() != null) {
            data.put("runLog", task.getRunLog());
        }

        // First try to query from IGinX outputTable
        if (task.getOutputTable() != null && !task.getOutputTable().isEmpty()) {
            try {
                DataQueryRequest queryReq = new DataQueryRequest();
                queryReq.setPaths(Collections.singletonList(task.getOutputTable() + ".*"));
                TableDto tableDto = dataTableService.queryData(queryReq);
                if (tableDto != null && tableDto.getHeader() != null && !tableDto.getHeader().isEmpty()
                        && tableDto.getRecords() != null && !tableDto.getRecords().isEmpty()) {
                    // Strip full path prefix from column names
                    String tablePrefix = task.getOutputTable() + ".";
                    List<String> headers = new ArrayList<>();
                    for (String col : tableDto.getHeader()) {
                        headers.add(col.startsWith(tablePrefix) ? col.substring(tablePrefix.length()) : col);
                    }
                    data.put("headers", headers);
                    List<String[]> rows = new ArrayList<>();
                    for (Map<String, Object> record : tableDto.getRecords()) {
                        String[] rowArr = new String[headers.size()];
                        for (int i = 0; i < headers.size(); i++) {
                            String fullColName = headers.get(i).equals("key") ? "key" : tablePrefix + headers.get(i);
                            Object val = record.get(fullColName);
                            rowArr[i] = val != null ? String.valueOf(val) : "";
                        }
                        rows.add(rowArr);
                    }
                    data.put("rows", rows);
                    return Result.success(data);
                }
            } catch (Exception e) {
                log.warn("从IGinX查询结果数据失败，尝试读取CSV文件: {}", e.getMessage());
            }
        }

        // Fallback: read from CSV file
        File csv = task.getResultCsvPath() != null ? new File(task.getResultCsvPath()) : null;
        // resultCsvPath 尚未设置时（doRun 线程还在导出/入库），尝试从任务目录读 signals.csv
        if (csv == null || !csv.exists()) {
            File taskDir = new File(getTaskBaseDir(projectName != null ? projectName : task.getProjectName()),
                    String.valueOf(task.getTimestamp()));
            File fallbackCsv = new File(taskDir, "signals.csv");
            if (fallbackCsv.exists()) csv = fallbackCsv;
        }
        if (csv != null && csv.exists()) {
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
        return Result.success(data);
    }

    public Result<ProgramEntity> updateConfig(String name, String version, String configJson, String projectName) {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) return Result.error("程序不存在");
        try {
            JsonNode configNode = mapper.readTree(configJson);
            entity.setConfigJson(configJson);
            saveProgramMetadata(entity);
            if (configNode.path("runtime").path("prewarm").asBoolean(false)) {
                enqueuePrewarm(entity);
            }
            return Result.success("配置更新成功", entity);
        } catch (Exception e) {
            return Result.error("配置更新失败: " + e.getMessage());
        }
    }

    /**
     * 下载仿真程序原始压缩包。
     * 复用 downloadFromIginx 从 IGinX 读取上传时存储的原始字节流：
     *   - 严格按 0..chunkCount-1 顺序取块，缺块即抛异常（避免错位/缺内容）
     *   - 用 fileMd5 校验完整性，确保下载字节与原始上传包完全一致
     * 这样下载下来的包再走 uploadProgram 解析时，内容与首次上传完全一致，
     * 不会出现 getProgramFiles 扫描结果变少的问题。
     * 注意：不要基于本地解压目录重新打包（会丢失 slprj/.slxc/.md 等文件）。
     */
    public byte[] downloadProgram(String name, String version, String projectName) throws Exception {
        ProgramEntity entity = queryMeta(name, version, projectName);
        if (entity == null) {
            throw new IllegalArgumentException("程序不存在");
        }
        String storagePath = entity.getStoragePath();
        Integer chunkCount = entity.getChunkCount();
        String fileMd5 = entity.getFileMd5();
        if (storagePath == null || storagePath.isEmpty() || chunkCount == null || chunkCount <= 0) {
            throw new IllegalStateException("程序存储信息不完整，无法下载");
        }
        return downloadFromIginx(storagePath, chunkCount, fileMd5);
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

        // 优先从 ProgramConfig 取参数（配置驱动），无配置时回退到脚本解析
        ProgramEntity entity = queryMeta(name, version, projectName);
        ProgramConfig pgConfig = entity != null && StringUtils.hasText(entity.getConfigJson())
                ? ProgramConfigMapper.parse(entity.getConfigJson()) : null;
        Map<String, Object> params;
        if (pgConfig != null && pgConfig.getParameters() != null && !pgConfig.getParameters().isEmpty()) {
            // 配置驱动：从 ProgramConfig 构造参数（优先从 MATLAB 源码解析实际值）
            params = buildParamsFromConfig(pgConfig, modelFiles, programDir, scriptFiles);
        } else {
            // 旧模式：解析 AFO 脚本
            params = parseProgramParams(programDir, scriptFiles);
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
        }
        result.put("params", params);
        return result;
    }

    /** 从 ProgramConfig 构造前端参数（配置驱动模式）*/
    private Map<String, Object> buildParamsFromConfig(ProgramConfig cfg, List<String> modelFiles,
                                                       File programDir, List<String> scriptFiles) {
        Map<String, Object> params = new LinkedHashMap<>();
        ProgramConfig.RuntimeConfig rt = cfg.getRuntime();
        params.put("stopTime", rt != null && rt.getStopTime() != 0 ? String.valueOf(rt.getStopTime()) : "30");
        // fixedStep：如果是纯数值直接用；如果是变量名（如 "Ts"）尝试从源码求值，求不到 fallback 0.025
        String fixedStep = rt != null ? rt.getFixedStep() : null;
        if (!StringUtils.hasText(fixedStep)) {
            fixedStep = "0.025";
        } else if (!fixedStep.matches("[0-9.]+")) {
            // 非纯数值，当作变量名从源码求值
            String resolved = resolveVarFromScripts(programDir, scriptFiles, fixedStep);
            if (resolved != null) fixedStep = resolved;
            else fixedStep = "0.025";
        }
        params.put("fixedStep", fixedStep);
        // 模型文件：从 runtime.simulinkModel 或自动检测
        String modelName = rt != null ? rt.getSimulinkModel() : "";
        if (StringUtils.hasText(modelName)) {
            for (String mf : modelFiles) {
                if (mf.equals(modelName) || mf.startsWith(modelName + ".")) {
                    params.put("modelFile", mf);
                    break;
                }
            }
        }
        if (!params.containsKey("modelFile") && !modelFiles.isEmpty()) {
            params.put("modelFile", modelFiles.get(0));
        }
        params.put("modelName", modelName != null ? modelName : "");
        // 动态参数：优先用 defaultValue（集成人员填写，最可靠）；
        // defaultValue 为空时尝试从 MATLAB 源码按 matlabVar 解析兜底
        List<ProgramConfig.ParameterSpec> ps = cfg.getParameters();
        if (ps != null) {
            // 只对 defaultValue 为空的参数尝试源码解析
            java.util.Set<String> varsToResolve = new java.util.HashSet<>();
            for (ProgramConfig.ParameterSpec p : ps) {
                if (p.getMatlabVar() != null && (p.getDefaultValue() == null || p.getDefaultValue().isEmpty())) {
                    varsToResolve.add(p.getMatlabVar());
                }
            }
            java.util.Map<String, String> sourceValues = varsToResolve.isEmpty()
                    ? new java.util.HashMap<>()
                    : resolveVarsFromScripts(programDir, scriptFiles, varsToResolve);
            for (ProgramConfig.ParameterSpec p : ps) {
                if (p.getKey() == null) continue;
                String val = p.getDefaultValue();
                if (val == null || val.isEmpty()) {
                    // defaultValue 为空，尝试源码解析
                    if (p.getMatlabVar() != null) val = sourceValues.get(p.getMatlabVar());
                }
                if (val != null) params.put(p.getKey(), val);
            }
        }
        return params;
    }

    /** 从 MATLAB 源码解析单个变量的数值（用于 fixedStep 等可能是变量名的字段） */
    private String resolveVarFromScripts(File programDir, List<String> scriptFiles, String varName) {
        java.util.Set<String> vars = new java.util.HashSet<>();
        vars.add(varName);
        java.util.Map<String, String> result = resolveVarsFromScripts(programDir, scriptFiles, vars);
        return result.get(varName);
    }

    /**
     * 从 MATLAB 源码脚本里按变量名解析数值（通用兜底）。
     * 遍历所有 .m 文件，对每个变量用正则 "var\s*=\s*([0-9.eE+-]+)" 搜索。
     * 支持纯数值和科学计数法，不支持表达式（表达式需集成人员在 defaultValue 里显式填写）。
     */
    private java.util.Map<String, String> resolveVarsFromScripts(File programDir,
                                                                  List<String> scriptFiles,
                                                                  java.util.Set<String> vars) {
        java.util.Map<String, String> result = new java.util.HashMap<>();
        if (vars == null || vars.isEmpty() || programDir == null || scriptFiles == null) return result;
        for (String relPath : scriptFiles) {
            File scriptFile = new File(programDir, relPath);
            try {
                String content = new String(Files.readAllBytes(scriptFile.toPath()), StandardCharsets.UTF_8);
                for (String var : vars) {
                    if (result.containsKey(var)) continue;
                    // 支持 21000 / 0.025 / 1e-3 / 2.1e4 等
                    java.util.regex.Matcher m = java.util.regex.Pattern.compile(
                            var + "\\s*=\\s*([0-9.]+[eE][+-]?[0-9]+|[0-9.]+)").matcher(content);
                    if (m.find()) {
                        result.put(var, m.group(1));
                    }
                }
            } catch (Exception e) {
                log.warn("解析脚本参数失败: {}", relPath, e);
            }
        }
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
}
