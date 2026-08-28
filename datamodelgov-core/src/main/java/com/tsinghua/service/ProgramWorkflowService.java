package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.query.SimpleQuery;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.ProgramEntity;
import com.tsinghua.entity.WorkflowMeasureDataEntity;
import com.tsinghua.entity.WorkflowScheduleVarEntity;
import com.tsinghua.entity.WorkflowTaskEntity;
import com.tsinghua.entity.WorkflowWorkspaceEntity;
import com.tsinghua.enums.TaskStatus;
import com.tsinghua.matlab.MatlabFunctionRunner;
import com.tsinghua.program.config.ProgramConfig;
import com.tsinghua.program.config.ProgramConfigMapper;
import com.tsinghua.util.ArchiveUtil;
import com.tsinghua.util.ConvertUtil;
import com.tsinghua.util.ProjectContext;
import lombok.extern.slf4j.Slf4j;
import org.apache.poi.ss.usermodel.DataFormatter;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.usermodel.WorkbookFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/** Minimal persistent backend for config-driven MATLAB workflows. */
@Slf4j
@Service
public class ProgramWorkflowService {

    private static final Pattern SAFE_ID = Pattern.compile("^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$|^\\d{1,19}$");
    private static final Pattern SAFE_KEY = Pattern.compile("^[A-Za-z][A-Za-z0-9_-]*$");
    /** 工作流阶段标记：[DMG:STAGE:<A-D>:START/END] */
    private static final Pattern STAGE_PATTERN = Pattern.compile("\\[DMG:STAGE:([A-D]):(START|END)\\]");
    /** workspace 目录名：ASCII 安全字符（兼容旧 UUID） */
    private static final Pattern SAFE_WORKSPACE_DIR = Pattern.compile("^[A-Za-z0-9._-]{1,64}$|^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$");
    private static final Set<String> ARTIFACT_DIRECTORY_NAMES = new LinkedHashSet<>(Arrays.asList(
            "output", "outputs", "result", "results", "report", "reports", "report_outputs"));

    private final ObjectMapper mapper = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT);
    private final ExecutorService executor = Executors.newCachedThreadPool(r -> {
        Thread thread = new Thread(r, "program-workflow-task");
        thread.setDaemon(true);
        return thread;
    });
    private final Map<String, MatlabFunctionRunner> running = new ConcurrentHashMap<>();
    /** 服务启动时间，用于判断 workflow_running 任务是否为重启前遗留 */
    private final long serviceStartTime = System.currentTimeMillis();
    /** 任务取消标志（内存，运行时高频检查） */
    private final Map<String, Boolean> cancelFlags = new ConcurrentHashMap<>();
    private final Map<String, Object> fileLocks = new ConcurrentHashMap<>();
    private final Map<String, Object> workspaceExecutionLocks = new ConcurrentHashMap<>();

    /** IGINX 存储前缀：工作流工作区元数据 */
    private static final String WF_WORKSPACE_PREFIX = "relational_system.workflow_workspace";
    /** IGINX 存储前缀：工作流任务记录 */
    private static final String WF_TASK_PREFIX = "relational_system.workflow_task";
    /** IGINX 存储前缀：工作流测量数据行 */
    private static final String WF_MEASURE_PREFIX = "relational_system.workflow_measure_data";
    /** IGINX 存储前缀：工作流调度变量行 */
    private static final String WF_SCHEDULE_PREFIX = "relational_system.workflow_schedule_var";

    @Autowired
    private ProgramService programService;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private Session iginxSession;

    @PostConstruct
    public void recoverInterruptedTasks() {
        try {
            // 从 IGINX 查询所有非终态任务
            String sql = "SELECT * FROM " + WF_TASK_PREFIX + ";";
            SessionExecuteSqlResult res = iginxSession.executeSql(sql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            if (records == null) return;
            for (Map<String, Object> record : records) {
                WorkflowTaskEntity entity = iginxRecordToTaskEntity(record);
                String status = entity.getStatus();
                if (TaskStatus.QUEUED.getValue().equals(status) || TaskStatus.RUNNING.getValue().equals(status)
                        || TaskStatus.WORKFLOW_RUNNING.getValue().equals(status) || TaskStatus.READY.getValue().equals(status)
                        || TaskStatus.CANCELLING.getValue().equals(status)) {
                    entity.setStatus(TaskStatus.WORKFLOW_FAILED.getValue());
                    entity.setError("服务重启导致任务中断");
                    entity.setFinishedAt(System.currentTimeMillis());
                    saveTaskToIginx(entity);
                    log.info("恢复工作流任务状态: taskId={} -> WORKFLOW_FAILED", entity.getTaskId());
                }
            }
        } catch (Exception e) {
            log.warn("从 IGINX 恢复工作流任务状态失败", e);
        }
    }

    @PreDestroy
    public void shutdown() {
        for (MatlabFunctionRunner runner : running.values()) runner.requestCancel();
        executor.shutdown();
    }

    /**
     * 列出程序包内可用的数据文件（Excel），用于项目创建前的下拉选择。
     * 直接扫描上传时已解压的程序目录，不重复解压。
     */
    public List<Map<String, Object>> listAvailableData(String name, String version, String projectName) throws Exception {
        requireSafeQueryValue(name, "name");
        requireSafeQueryValue(version, "version");
        String project = effectiveProject(projectName);
        ProgramEntity entity = requireWorkflowProgram(name, version, project);
        ProgramConfig config = parseWorkflowConfig(entity);

        // 使用上传时已解压的程序目录
        File programDir = programService.getProgramDir(project, name, version);
        if (!programDir.isDirectory()) {
            throw new IllegalArgumentException("程序解压目录不存在，请重新上传程序包");
        }

        String configuredWorkingDirectory = config.getRuntime().getWorkingDirectory().trim();
        Path workingDirectory = resolveInside(programDir.toPath(), configuredWorkingDirectory, true);

        List<Map<String, Object>> result = new ArrayList<>();
        // 扫描 TestData 目录下的 Excel 文件
        Path testData = child(workingDirectory, "TestData");
        if (Files.isDirectory(testData)) {
            try (Stream<Path> paths = Files.list(testData)) {
                for (Path file : (Iterable<Path>) paths::iterator) {
                    if (!Files.isRegularFile(file)) continue;
                    String fileName = file.getFileName().toString();
                    String lower = fileName.toLowerCase();
                    if (lower.endsWith(".xlsx") || lower.endsWith(".xls")) {
                        Map<String, Object> entry = new LinkedHashMap<>();
                        entry.put("fileName", fileName);
                        entry.put("size", Files.size(file));
                        entry.put("relativePath", "TestData/" + fileName);
                        result.add(entry);
                    }
                }
            }
        }
        result.sort(Comparator.comparing(m -> value(m.get("fileName"))));
        return result;
    }

    private static final List<String> REQUIRED_COLUMNS = Arrays.asList(
            "point_id", "Np_mean", "Ng_mean", "Wf_mean", "Mkp_mean", "Mkg_mean",
            "Tt1_mean", "Pt2_mean", "Pt3_mean", "Tt3_mean", "Tt45_mean", "Pt45_mean",
            "Pamb_mean", "Tamb_mean", "Altitude_mean", "Mach_mean");

    private static final double NG0 = 38000.0;
    private static final double T_REF = 288.15;

    /**
     * 预览指定数据文件的内容：返回测量数据表行、调度变量与训练分组、数据合同校验结果。
     */
    public Map<String, Object> previewData(String name, String version, String projectName,
                                            String fileName) throws Exception {
        requireSafeQueryValue(name, "name");
        requireSafeQueryValue(version, "version");
        String project = effectiveProject(projectName);
        ProgramEntity entity = requireWorkflowProgram(name, version, project);
        ProgramConfig config = parseWorkflowConfig(entity);

        File programDir = programService.getProgramDir(project, name, version);
        if (!programDir.isDirectory()) {
            throw new IllegalArgumentException("程序解压目录不存在，请重新上传程序包");
        }
        String configuredWorkingDirectory = config.getRuntime().getWorkingDirectory().trim();
        Path workingDirectory = resolveInside(programDir.toPath(), configuredWorkingDirectory, true);
        Path testData = child(workingDirectory, "TestData");
        Path file = child(testData, safeFileName(fileName, "data.xlsx"));
        if (!Files.isRegularFile(file)) {
            throw new IllegalArgumentException("数据文件不存在: " + fileName);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("fileName", fileName);

        // 读取 Excel
        List<Map<String, Object>> rows = new ArrayList<>();
        List<String> columns = new ArrayList<>();
        List<String> missingColumns = new ArrayList<>();
        try (InputStream in = Files.newInputStream(file);
             Workbook wb = WorkbookFactory.create(in)) {
            Sheet sheet = wb.getSheetAt(0);
            if (sheet.getPhysicalNumberOfRows() == 0) {
                result.put("rowCount", 0);
                result.put("columns", columns);
                result.put("rows", rows);
                result.put("missingColumns", REQUIRED_COLUMNS);
                result.put("valid", false);
                return result;
            }

            // 读取表头
            Row headerRow = sheet.getRow(0);
            if (headerRow == null) {
                result.put("rowCount", 0);
                result.put("columns", columns);
                result.put("rows", rows);
                result.put("missingColumns", REQUIRED_COLUMNS);
                result.put("valid", false);
                return result;
            }
            DataFormatter formatter = new DataFormatter();
            for (int c = 0; c < headerRow.getLastCellNum(); c++) {
                String colName = formatter.formatCellValue(headerRow.getCell(c)).trim();
                columns.add(colName);
            }

            // 检查必需字段
            for (String req : REQUIRED_COLUMNS) {
                if (!columns.contains(req)) missingColumns.add(req);
            }
            result.put("columns", columns);
            result.put("missingColumns", missingColumns);
            result.put("valid", missingColumns.isEmpty());

            // 读取数据行
            int colCount = columns.size();
            for (int r = 1; r <= sheet.getLastRowNum(); r++) {
                Row row = sheet.getRow(r);
                if (row == null) continue;
                Map<String, Object> rowData = new LinkedHashMap<>();
                boolean hasData = false;
                for (int c = 0; c < colCount; c++) {
                    String colName = columns.get(c);
                    String cellVal = formatter.formatCellValue(row.getCell(c)).trim();
                    if (!cellVal.isEmpty()) hasData = true;
                    rowData.put(colName, cellVal);
                }
                if (hasData) rows.add(rowData);
            }
        }
        result.put("rowCount", rows.size());
        result.put("rows", rows);

        // 计算数据指纹（SHA-256）
        result.put("fingerprint", sha256(file));

        // 计算调度变量和训练分组
        if (missingColumns.isEmpty() && rows.size() > 0) {
            result.put("scheduleRows", computeScheduleAndGroups(rows));
            result.put("groupCount", countGroups(rows));
        } else {
            result.put("scheduleRows", Collections.emptyList());
            result.put("groupCount", 0);
        }

        return result;
    }

    /**
     * 计算调度变量和训练分组。
     * AC相对换算转速 = (Ng_mean / Ng0) * sqrt(288.15 / Tt1_mean)
     * 分组：按 AC 相对换算转速排序，组内跨度不超过 0.010。
     */
    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> computeScheduleAndGroups(List<Map<String, Object>> rows) {
        int n = rows.size();
        double[] acSpeed = new double[n];
        for (int i = 0; i < n; i++) {
            try {
                double ng = Double.parseDouble(String.valueOf(rows.get(i).get("Ng_mean")));
                double tt1 = Double.parseDouble(String.valueOf(rows.get(i).get("Tt1_mean")));
                acSpeed[i] = (ng / NG0) * Math.sqrt(T_REF / tt1);
            } catch (Exception e) {
                acSpeed[i] = Double.NaN;
            }
        }

        // 排序索引
        Integer[] order = new Integer[n];
        for (int i = 0; i < n; i++) order[i] = i;
        Integer[] sorted = order.clone();
        Arrays.sort(sorted, (a, b) -> Double.compare(acSpeed[a], acSpeed[b]));

        // 分组：组内跨度 <= 0.010
        double spanLimit = 0.010;
        List<List<Integer>> clusters = new ArrayList<>();
        int start = 0;
        for (int i = 1; i < n; i++) {
            if (acSpeed[sorted[i]] - acSpeed[sorted[start]] > spanLimit) {
                List<Integer> cluster = new ArrayList<>();
                for (int j = start; j < i; j++) cluster.add(sorted[j]);
                clusters.add(cluster);
                start = i;
            }
        }
        List<Integer> lastCluster = new ArrayList<>();
        for (int j = start; j < n; j++) lastCluster.add(sorted[j]);
        clusters.add(lastCluster);

        // 为每行分配组号
        int[] groupOfRow = new int[n];
        for (int g = 0; g < clusters.size(); g++) {
            for (int idx : clusters.get(g)) groupOfRow[idx] = g + 1;
        }

        // 构造调度变量行
        List<Map<String, Object>> scheduleRows = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            Map<String, Object> row = rows.get(i);
            Map<String, Object> sr = new LinkedHashMap<>();
            sr.put("工况", row.get("point_id"));
            sr.put("数据角色", "训练");
            int g = groupOfRow[i];
            sr.put("训练分组", "组" + g);
            sr.put("AC相对换算转速", String.format("%.4f", acSpeed[i]));
            // 其他调度变量需要 DLL 计算，这里只给出 AC 相对换算转速
            sr.put("进气道换算流量", "—");
            sr.put("燃烧室进口换算流量", "—");
            sr.put("GT物理压比", "—");
            sr.put("GT-PT涵道换算流量", "—");
            sr.put("PT物理压比", "—");
            sr.put("PT-尾喷管涵道换算流量", "—");
            sr.put("测量燃油流量归一化坐标", "—");
            scheduleRows.add(sr);
        }
        return scheduleRows;
    }

    private int countGroups(List<Map<String, Object>> rows) {
        // 复用 computeScheduleAndGroups 的分组逻辑
        List<Map<String, Object>> sr = computeScheduleAndGroups(rows);
        Set<String> groups = new LinkedHashSet<>();
        for (Map<String, Object> r : sr) groups.add(String.valueOf(r.get("训练分组")));
        return groups.size();
    }

    public Map<String, Object> createWorkspace(String name, String version, String projectName,
                                                 String jobName, String trainingDataFile, String testDataFile,
                                                 String notes) throws Exception {
        requireSafeQueryValue(name, "name");
        requireSafeQueryValue(version, "version");
        String project = effectiveProject(projectName);
        ProgramEntity entity = requireWorkflowProgram(name, version, project);
        ProgramConfig config = parseWorkflowConfig(entity);

        String id = safeJobName(jobName);
        Path root = workflowRoot(project);
        Path workspace = child(root, id);
        // 检查重名：查 IGINX 是否已有该 workspace 记录（不检查目录，因为目录可能残留）
        Map<String, Object> existing = queryWorkspaceFromIginxById(id);
        if (existing != null) {
            throw new IllegalArgumentException("项目名称已存在: " + jobName + "，请使用其他名称");
        }

        // 只做轻量校验，不执行重活
        if (!StringUtils.hasText(trainingDataFile)) {
            throw new IllegalArgumentException("请选择训练数据文件");
        }

        // 先创建 IGINX 记录（status=CREATING），立即返回给前端
        long now = System.currentTimeMillis();
        WorkflowWorkspaceEntity wsEntity = new WorkflowWorkspaceEntity();
        wsEntity.setTimestamp(now);
        wsEntity.setId(id);
        wsEntity.setProgramName(name);
        wsEntity.setProgramVersion(version);
        wsEntity.setProjectName(project);
        wsEntity.setJobName(jobName != null ? jobName : "");
        wsEntity.setNotes(notes != null ? notes : "");
        wsEntity.setTrainingDataFile(trainingDataFile);
        wsEntity.setTestDataFile(testDataFile != null ? testDataFile : "");
        wsEntity.setStatus(TaskStatus.CREATING.getValue());
        wsEntity.setProgramFileMd5(entity.getFileMd5());
        wsEntity.setCreatedAt(now);
        wsEntity.setUpdatedAt(now);
        wsEntity.setInitStatus("PENDING");
        wsEntity.setUploadedDatasets("[]");

        // 保存工作区元数据到 IGINX（轻量，只有基本字段）
        saveWorkspaceToIginx(wsEntity);

        // 构建返回给前端的 Map
        Map<String, Object> record = workspaceEntityToMap(wsEntity);
        addStatusLabel(record);

        // 所有重活（下载、解压、复制文件、校验、MATLAB 初始化）全部异步执行
        final String trainingFile = trainingDataFile;
        final String testDataFileFinal = testDataFile;
        final String notesFinal = notes;
        final String jobNameFinal = jobName;
        final long wsTimestamp = now;
        final String wsId = id;
        final String nameFinal = name;
        final String versionFinal = version;
        final String projectFinal = project;
        final ProgramEntity entityFinal = entity;
        final ProgramConfig configFinal = config;

        executor.submit(() -> {
            log.info("工作区 {} 异步创建任务开始执行", wsId);
            try {
                runWorkspaceCreation(entityFinal, configFinal, nameFinal, versionFinal, projectFinal,
                        wsId, jobNameFinal, trainingFile, testDataFileFinal, notesFinal, wsTimestamp);
            } catch (Exception e) {
                log.error("工作区 {} 创建失败", wsId, e);
                WorkflowWorkspaceEntity failUpdate = new WorkflowWorkspaceEntity();
                failUpdate.setTimestamp(wsTimestamp);
                failUpdate.setId(wsId);
                failUpdate.setStatus(TaskStatus.FAILED.getValue());
                failUpdate.setUpdatedAt(System.currentTimeMillis());
                failUpdate.setInitStatus("FAILED");
                failUpdate.setInitMessage(e.getMessage() != null ? e.getMessage() : String.valueOf(e));
                updateWorkspaceInIginx(failUpdate);
            }
        });

        return record;
    }

    /** 异步执行工作区创建的全部重活：下载、解压、复制文件、校验、MATLAB 初始化 */
    @SuppressWarnings("unchecked")
    private void runWorkspaceCreation(ProgramEntity entity, ProgramConfig config, String name, String version,
                                       String project, String id, String jobName,
                                       String trainingDataFile, String testDataFile, String notes,
                                       long wsTimestamp) throws Exception {
        log.info("工作区 {} 异步创建开始: 下载/解压/复制/校验/MATLAB初始化", id);
        Path root = workflowRoot(project);
        Path workspace = child(root, id);
        Path source = child(workspace, "source");
        Path datasets = child(workspace, "datasets");
        Path tasks = child(workspace, "tasks");
        Path output = child(workspace, "output");
        Files.createDirectories(source);
        Files.createDirectories(datasets);
        Files.createDirectories(tasks);
        Files.createDirectories(output);

        // 1. 下载并解压程序包
        log.info("工作区 {} 步骤1: 下载程序包", id);
        String archiveName = safeFileName(entity.getFileName(), "program.zip");
        if (!ArchiveUtil.isSupportedArchive(archiveName)) {
            throw new IllegalArgumentException("Program archive has an unsupported file extension");
        }
        Path archive = child(workspace, archiveName);
        Files.write(archive, programService.downloadProgram(name, version, project));
        Map<String, String> dirMapping = new LinkedHashMap<>();
        try {
            ArchiveUtil.extractArchive(archive.toFile(), source.toFile(), true, dirMapping);
        } finally {
            Files.deleteIfExists(archive);
        }
        log.info("工作区 {} 步骤1完成: 程序包已解压", id);

        // 2. 解析工作目录
        log.info("工作区 {} 步骤2: 解析工作目录", id);
        String configuredWorkingDirectory = config.getRuntime().getWorkingDirectory().trim();
        // 如果解压时替换了中文目录名，用映射修正 workingDirectory
        configuredWorkingDirectory = applyDirMapping(configuredWorkingDirectory, dirMapping);
        Path workingDirectory = resolveInside(source, configuredWorkingDirectory, true);
        if (!Files.isDirectory(workingDirectory)) {
            throw new IllegalArgumentException("runtime.workingDirectory does not exist in the program archive");
        }
        validateWorkflowFiles(workingDirectory, config);
        installWorkflowAdapter(workingDirectory);
        log.info("工作区 {} 步骤2完成: 工作目录已就绪", id);

        // 3. 复制数据文件
        log.info("工作区 {} 步骤3: 复制数据文件", id);
        Path testDataDir = child(workingDirectory, "TestData");
        List<Map<String, Object>> uploadedDatasets = new ArrayList<>();

        Path srcTrain = child(testDataDir, safeFileName(trainingDataFile, "training.xlsx"));
        if (!Files.isRegularFile(srcTrain)) {
            throw new IllegalArgumentException("训练数据文件不存在于程序包: " + trainingDataFile);
        }
        String trainStoredName = "trainingData-" + safeFileName(trainingDataFile, "training.xlsx");
        Path destTrain = child(datasets, trainStoredName);
        Files.copy(srcTrain, destTrain, StandardCopyOption.REPLACE_EXISTING);
        Map<String, Object> trainRecord = new LinkedHashMap<>();
        trainRecord.put("datasetKey", "trainingData");
        trainRecord.put("fileName", trainingDataFile);
        trainRecord.put("storedName", trainStoredName);
        trainRecord.put("size", Files.size(destTrain));
        trainRecord.put("sha256", sha256(destTrain));
        trainRecord.put("uploadedAt", System.currentTimeMillis());
        uploadedDatasets.add(trainRecord);

        if (StringUtils.hasText(testDataFile)) {
            Path srcTest = child(testDataDir, safeFileName(testDataFile, "test.xlsx"));
            if (!Files.isRegularFile(srcTest)) {
                throw new IllegalArgumentException("测试数据文件不存在于程序包: " + testDataFile);
            }
            String testStoredName = "testData-" + safeFileName(testDataFile, "test.xlsx");
            Path destTest = child(datasets, testStoredName);
            Files.copy(srcTest, destTest, StandardCopyOption.REPLACE_EXISTING);
            Map<String, Object> testRecord = new LinkedHashMap<>();
            testRecord.put("datasetKey", "testData");
            testRecord.put("fileName", testDataFile);
            testRecord.put("storedName", testStoredName);
            testRecord.put("size", Files.size(destTest));
            testRecord.put("sha256", sha256(destTest));
            testRecord.put("uploadedAt", System.currentTimeMillis());
            uploadedDatasets.add(testRecord);
        }

        // 4. 校验训练数据合同
        log.info("工作区 {} 步骤4: 校验训练数据合同", id);
        Path trainingPath = child(datasets, trainStoredName);
        Map<String, Object> dataContract = validateDataContract(trainingPath);
        if (!Boolean.TRUE.equals(dataContract.get("valid"))) {
            throw new IllegalArgumentException("训练数据合同校验失败: 缺少字段 " +
                    String.join(", ", (List<String>) dataContract.get("missingColumns")));
        }
        log.info("工作区 {} 步骤4完成: 数据合同校验通过", id);

        // 5. 写 program-config.json（MATLAB 运行时需要）
        String configJson = ProgramConfigMapper.stringify(config);
        Files.write(child(workspace, "program-config.json"), configJson.getBytes(StandardCharsets.UTF_8));

        // 6. 更新 IGINX：补充完整字段，状态改为 INITIALIZING
        log.info("工作区 {} 步骤6: 更新状态为 INITIALIZING", id);
        WorkflowWorkspaceEntity initUpdate = new WorkflowWorkspaceEntity();
        initUpdate.setTimestamp(wsTimestamp);
        initUpdate.setId(id);
        initUpdate.setStatus(TaskStatus.INITIALIZING.getValue());
        initUpdate.setUpdatedAt(System.currentTimeMillis());
        initUpdate.setWorkingDirectory(source.relativize(workingDirectory).toString().replace(File.separatorChar, '/'));
        initUpdate.setWorkspaceDir(workspace.toAbsolutePath().toString().replace(File.separatorChar, '/'));
        initUpdate.setConfigSha256(sha256Text(configJson));
        initUpdate.setRequiredFileHashes(mapper.writeValueAsString(requiredFileHashes(workingDirectory, config)));
        initUpdate.setUploadedDatasets(mapper.writeValueAsString(uploadedDatasets));
        initUpdate.setDataContract(mapper.writeValueAsString(dataContract));
        initUpdate.setInitStatus("INITIALIZING");
        updateWorkspaceInIginx(initUpdate);
        log.info("工作区 {} 步骤6完成: IGINX 状态已更新为 INITIALIZING", id);

        // 7. 执行 MATLAB 初始化
        log.info("工作区 {} 步骤7: 开始 MATLAB 初始化", id);
        Map<String, Object> initResult = runMatlabInit(workingDirectory, trainingDataFile, workspace);
        log.info("工作区 {} 步骤7完成: MATLAB 初始化结果 status={}", id, initResult != null ? initResult.get("status") : "null");

        // 8. 将 MATLAB 初始化产生的测量数据和调度变量写入 IGINX（实体表）
        if (initResult != null && "SUCCEEDED".equals(initResult.get("status"))) {
            Object measureRows = initResult.get("measureRows");
            if (measureRows instanceof List) {
                saveMeasureDataToIginx(id, (List<Map<String, Object>>) measureRows);
            }
            Object scheduleRows = initResult.get("scheduleRows");
            if (scheduleRows instanceof List) {
                saveScheduleVarsToIginx(id, (List<Map<String, Object>>) scheduleRows);
            }
        }

        // 9. 将初始化摘要写入 IGINX
        WorkflowWorkspaceEntity readyUpdate = new WorkflowWorkspaceEntity();
        readyUpdate.setTimestamp(wsTimestamp);
        readyUpdate.setId(id);
        readyUpdate.setStatus(TaskStatus.READY.getValue());
        readyUpdate.setUpdatedAt(System.currentTimeMillis());
        readyUpdate.setInitStatus(value(initResult.get("status")));
        readyUpdate.setInitMessage(value(initResult.get("message")));
        Object rowCount = initResult.get("rowCount");
        if (rowCount instanceof Number) readyUpdate.setInitRowCount(((Number) rowCount).intValue());
        Object groupCount = initResult.get("groupCount");
        if (groupCount instanceof Number) readyUpdate.setInitGroupCount(((Number) groupCount).intValue());
        readyUpdate.setInitDllHash(value(initResult.get("dllHash")));
        Object initValid = initResult.get("valid");
        if (initValid instanceof Boolean) readyUpdate.setInitValid((Boolean) initValid);
        Object baselineValid = initResult.get("baselineValid");
        if (baselineValid instanceof Boolean) readyUpdate.setInitBaselineValid((Boolean) baselineValid);
        Object missingCols = initResult.get("missingColumns");
        if (missingCols instanceof List) {
            readyUpdate.setInitMissingColumns(String.join(",", (List<String>) missingCols));
        } else {
            readyUpdate.setInitMissingColumns(value(missingCols));
        }
        readyUpdate.setInitStartedAt(value(initResult.get("startedAt")));
        readyUpdate.setInitCompletedAt(value(initResult.get("completedAt")));
        updateWorkspaceInIginx(readyUpdate);
        log.info("工作区 {} 创建并初始化完成: {}", id, initResult.get("status"));
    }

    /**
     * 调用 MATLAB 适配器 dmg_init_project 执行初始化和零修正回放。
     * 返回包含测量数据行、调度变量行和分组信息的 Map。
     */
    @SuppressWarnings("unchecked")
    private Map<String, Object> runMatlabInit(Path workingDirectory, String trainingDataFile,
                                               Path workspace) throws Exception {
        Path initDir = child(child(workspace, "output"), "init");
        Files.createDirectories(initDir);
        Path matlabResult = child(initDir, "init_result.mat");
        Path matlabManifest = child(initDir, "init_manifest.json");
        Path logFile = child(initDir, "init.log");

        Object[] args = new Object[]{
                trainingDataFile != null ? trainingDataFile : "",
                matlabResult.toFile().getAbsolutePath(),
                matlabManifest.toFile().getAbsolutePath()
        };

        MatlabFunctionRunner runner = new MatlabFunctionRunner(
                workingDirectory.toFile(), "dmg_init_project", args,
                logFile.toFile(), programService.enginePool());

        try {
            runner.run();
        } catch (Exception e) {
            log.warn("MATLAB 项目初始化失败，将使用纯 Java 计算的调度变量", e);
            Map<String, Object> fallback = new LinkedHashMap<>();
            fallback.put("status", "FALLBACK");
            fallback.put("message", e.getMessage() != null ? e.getMessage() : String.valueOf(e));
            return fallback;
        }

        try {
            Map<String, Object> manifest = readMap(matlabManifest);
            return manifest;
        } catch (IOException e) {
            log.warn("读取 MATLAB 初始化清单失败", e);
            Map<String, Object> fallback = new LinkedHashMap<>();
            fallback.put("status", "FALLBACK");
            fallback.put("message", "读取初始化结果失败: " + e.getMessage());
            return fallback;
        }
    }

    /** 校验 Excel 数据合同：检查必需字段是否齐全 */
    private Map<String, Object> validateDataContract(Path excelFile) throws Exception {
        Map<String, Object> result = new LinkedHashMap<>();
        if (!Files.isRegularFile(excelFile)) {
            result.put("valid", false);
            result.put("missingColumns", REQUIRED_COLUMNS);
            result.put("rowCount", 0);
            return result;
        }
        List<String> columns = new ArrayList<>();
        int rowCount = 0;
        try (InputStream in = Files.newInputStream(excelFile);
             Workbook wb = WorkbookFactory.create(in)) {
            Sheet sheet = wb.getSheetAt(0);
            Row headerRow = sheet.getRow(0);
            if (headerRow != null) {
                DataFormatter formatter = new DataFormatter();
                for (int c = 0; c < headerRow.getLastCellNum(); c++) {
                    columns.add(formatter.formatCellValue(headerRow.getCell(c)).trim());
                }
            }
            rowCount = sheet.getLastRowNum();
        }
        List<String> missing = new ArrayList<>();
        for (String req : REQUIRED_COLUMNS) {
            if (!columns.contains(req)) missing.add(req);
        }
        result.put("valid", missing.isEmpty());
        result.put("missingColumns", missing);
        result.put("rowCount", Math.max(0, rowCount));
        result.put("columns", columns);
        result.put("fingerprint", sha256(excelFile));
        return result;
    }

    public List<Map<String, Object>> listWorkspaces(String name, String version, String projectName) throws Exception {
        String project = effectiveProject(projectName);
        // 从 IGINX 查询
        List<Map<String, Object>> result = queryWorkspacesFromIginx(name, version, project);
        result.sort((a, b) -> Long.compare(longValue(b.get("createdAt")), longValue(a.get("createdAt"))));
        return result;
    }

    public Map<String, Object> getWorkspace(String id, String name, String version, String projectName) throws Exception {
        // 从 IGINX 查询
        Map<String, Object> record = queryWorkspaceFromIginxById(id);
        if (record == null) throw new IllegalArgumentException("Workspace does not exist");
        return record;
    }

    public void deleteWorkspace(String id, String name, String version, String projectName) throws Exception {
        Path workspace = requireWorkspace(id, name, version, projectName);
        // 从 IGINX 查 workspace timestamp
        Map<String, Object> wsRecord = queryWorkspaceFromIginxById(id);
        long wsTimestamp = wsRecord != null ? longValue(wsRecord.get("timestamp")) : 0L;

        // 检查是否有进程在执行中：workspace 处于创建/初始化中，或有任务正在运行
        String wsStatus = wsRecord != null ? value(wsRecord.get("status")) : "";
        if (TaskStatus.CREATING.getValue().equals(wsStatus) || TaskStatus.INITIALIZING.getValue().equals(wsStatus)) {
            throw new IllegalStateException("项目正在创建/初始化中，无法删除");
        }
        // 检查是否有运行中的任务
        List<Map<String, Object>> tasks = queryTasksFromIginx(id);
        for (Map<String, Object> task : tasks) {
            String taskStatus = value(task.get("status"));
            if (TaskStatus.QUEUED.getValue().equals(taskStatus)
                    || TaskStatus.WORKFLOW_RUNNING.getValue().equals(taskStatus)
                    || TaskStatus.CANCELLING.getValue().equals(taskStatus)) {
                throw new IllegalStateException("项目有任务正在运行中，无法删除");
            }
        }

        // 先删除 IGINX 中的数据（元数据权威）
        deleteWorkspaceFromIginx(id, wsTimestamp);
        // 再删除磁盘文件
        deleteRecursively(workspace);
    }

    private void deleteRecursively(Path path) throws IOException {
        if (Files.isDirectory(path)) {
            try (Stream<Path> paths = Files.list(path)) {
                for (Path child : (Iterable<Path>) paths::iterator) {
                    deleteRecursively(child);
                }
            }
        }
        Files.deleteIfExists(path);
    }

    public Map<String, Object> uploadDataset(String workspaceId, String datasetKey, MultipartFile file,
                                              String name, String version, String projectName) throws Exception {
        if (file == null || file.isEmpty()) throw new IllegalArgumentException("Dataset file is empty");
        if (!SAFE_KEY.matcher(value(datasetKey)).matches()) throw new IllegalArgumentException("Invalid datasetKey");
        Path workspace = requireWorkspace(workspaceId, name, version, projectName);
        ProgramConfig config = configForWorkspace(workspace);
        ProgramConfig.DatasetSpec spec = findDataset(config, datasetKey);
        if (spec == null) throw new IllegalArgumentException("datasetKey is not declared by the program config");
        validateDatasetFile(spec, file);

        Path datasetDir = child(workspace, "datasets");
        String storedName = UUID.randomUUID().toString() + "-" + safeFileName(file.getOriginalFilename(), "dataset.bin");
        Path destination = child(datasetDir, storedName);
        file.transferTo(destination.toFile());

        // 从 IGINX 读当前 uploadedDatasets
        List<Map<String, Object>> records = queryUploadedDatasetsFromIginx(workspaceId);
        for (Map<String, Object> old : records) {
            if (datasetKey.equals(old.get("datasetKey"))) {
                Object oldName = old.get("storedName");
                if (oldName != null) Files.deleteIfExists(child(datasetDir, String.valueOf(oldName)));
            }
        }
        records.removeIf(item -> datasetKey.equals(item.get("datasetKey")));
        Map<String, Object> record = new LinkedHashMap<>();
        record.put("datasetKey", datasetKey);
        record.put("label", spec.getLabel());
        record.put("type", spec.getType());
        record.put("role", spec.getRole());
        record.put("required", Boolean.TRUE.equals(spec.getRequired()));
        record.put("fileName", safeFileName(file.getOriginalFilename(), "dataset.bin"));
        record.put("storedName", storedName);
        record.put("size", Files.size(destination));
        record.put("sha256", sha256(destination));
        record.put("uploadedAt", System.currentTimeMillis());
        records.add(record);
        // 更新 IGINX 中的 uploadedDatasets
        Map<String, Object> wsRecord = queryWorkspaceFromIginxById(workspaceId);
        if (wsRecord != null) {
            WorkflowWorkspaceEntity wsEntity = iginxRecordToWorkspaceEntity(wsRecord);
            wsEntity.setUploadedDatasets(mapper.writeValueAsString(records));
            wsEntity.setUpdatedAt(System.currentTimeMillis());
            updateWorkspaceInIginx(wsEntity);
        }
        return publicDataset(record);
    }

    public List<Map<String, Object>> listDatasets(String workspaceId, String name, String version,
                                                   String projectName) throws Exception {
        Path workspace = requireWorkspace(workspaceId, name, version, projectName);
        List<Map<String, Object>> records = queryUploadedDatasetsFromIginx(workspaceId);
        List<Map<String, Object>> result = new ArrayList<>();
        for (Map<String, Object> record : records) result.add(publicDataset(record));
        return result;
    }

    /** 查询工作区的测量数据行（从 IGINX） */
    public List<Map<String, Object>> listMeasureData(String workspaceId, String name, String version,
                                                      String projectName) throws Exception {
        requireWorkspace(workspaceId, name, version, projectName);
        return queryMeasureDataFromIginx(workspaceId);
    }

    /** 查询工作区的调度变量行（从 IGINX） */
    public List<Map<String, Object>> listScheduleVars(String workspaceId, String name, String version,
                                                       String projectName) throws Exception {
        requireWorkspace(workspaceId, name, version, projectName);
        return queryScheduleVarsFromIginx(workspaceId);
    }

    public Map<String, Object> createTask(JsonNode request, String name, String version, String projectName) throws Exception {
        if (request == null || !request.isObject()) throw new IllegalArgumentException("Task request must be a JSON object");
        String workspaceId = text(request, "workspaceId");
        String actionKey = text(request, "actionKey");
        Path workspace = requireWorkspace(workspaceId, name, version, projectName);
        ProgramConfig config = configForWorkspace(workspace);
        ProgramConfig.WorkflowAction action = findAction(config, actionKey);
        if (action == null) throw new IllegalArgumentException("actionKey is not declared by the program config");

        Object[] arguments = resolveArguments(workspace, workspaceId, config, action, request.get("inputs"));
        long taskTimestamp = System.currentTimeMillis();
        String taskId = String.valueOf(taskTimestamp);
        Path taskDir = child(child(workspace, "tasks"), taskId);
        Files.createDirectories(taskDir);
        WorkflowTaskEntity taskEntity = new WorkflowTaskEntity();
        taskEntity.setTimestamp(taskTimestamp);
        taskEntity.setTaskId(taskId);
        taskEntity.setWorkspaceId(workspaceId);
        taskEntity.setActionKey(action.getKey());
        taskEntity.setEntryPoint(action.getEntryPoint());
        taskEntity.setStage(action.getStage());
        taskEntity.setResultType(action.getResultType());
        taskEntity.setStatus(TaskStatus.READY.getValue());
        taskEntity.setCreatedAt(taskTimestamp);
        taskEntity.setLogPath("tasks/" + taskId + "/run.log");
        // 任务元数据只写 IGINX（不写 task.json）
        saveTaskToIginx(taskEntity);
        Map<String, Object> task = taskEntityToMap(taskEntity);
        executor.submit(() -> {
            Object executionLock = workspaceExecutionLocks.computeIfAbsent(workspace.toString(), key -> new Object());
            synchronized (executionLock) {
                runTask(workspace, taskDir, task, action, arguments);
            }
        });
        addStatusLabel(task);
        return task;
    }

    public List<Map<String, Object>> listTasks(String workspaceId, String name, String version,
                                               String projectName) throws Exception {
        // 从 IGINX 查询
        List<Map<String, Object>> result = queryTasksFromIginx(workspaceId);
        Map<String, Map<String, Object>> unique = new LinkedHashMap<>();
        for (Map<String, Object> t : result) unique.putIfAbsent(String.valueOf(t.get("id")), t);
        result = new ArrayList<>(unique.values());
        result.sort((a, b) -> Long.compare(longValue(b.get("createdAt")), longValue(a.get("createdAt"))));
        return result;
    }

    public Map<String, Object> getTask(String taskId, String name, String version, String projectName) throws Exception {
        Path task = requireTask(taskId, name, version, projectName);
        long ts = taskTimestamp(taskId);
        WorkflowTaskEntity entity = loadTaskFromIginx(ts);
        if (entity == null) throw new IllegalStateException("任务记录不存在");
        Map<String, Object> record = taskEntityToMap(entity);
        addStatusLabel(record);
        Path progressFile = child(task, "task-progress.json");
        if (Files.isRegularFile(progressFile)) {
            try {
                Map<String, Object> progress = readMap(progressFile);
                record.put("phase", progress.get("phase"));
                record.put("progressMessage", progress.get("message"));
            } catch (Exception ignored) {}
        }
        String taskStatus = String.valueOf(record.getOrDefault("status", ""));
        String phase = String.valueOf(record.getOrDefault("phase", ""));
        if (("RUNNING".equals(taskStatus) || "READY".equals(taskStatus))
                && !"completed".equals(phase) && !"failed".equals(phase)) {
            Path resultFile = child(task, "result.json");
            if (Files.isRegularFile(resultFile)) {
                try {
                    Map<String, Object> resultMap = readMap(resultFile);
                    @SuppressWarnings("unchecked")
                    Map<String, Object> value = (Map<String, Object>) resultMap.get("value");
                    if (value != null) {
                        String matlabStatus = String.valueOf(value.getOrDefault("status", ""));
                        WorkflowTaskEntity taskEntity = loadTaskFromIginx(ts);
                        if ("SUCCEEDED".equalsIgnoreCase(matlabStatus) || "COMPLETED".equalsIgnoreCase(matlabStatus)) {
                            record.put("status", TaskStatus.COMPLETED.getValue());
                            record.put("statusLabel", TaskStatus.COMPLETED.getLabel());
                            record.put("phase", "completed");
                            record.put("progressMessage", "MATLAB 运行完成");
                            if (taskEntity != null) {
                                taskEntity.setStatus(TaskStatus.COMPLETED.getValue());
                                taskEntity.setFinishedAt(System.currentTimeMillis());
                                saveTaskToIginx(taskEntity);
                            }
                            writeTaskProgress(task, "completed", "MATLAB 运行完成");
                        } else if ("FAILED".equalsIgnoreCase(matlabStatus)) {
                            String error = String.valueOf(value.getOrDefault("message", "MATLAB 运行失败"));
                            record.put("status", TaskStatus.WORKFLOW_FAILED.getValue());
                            record.put("statusLabel", TaskStatus.WORKFLOW_FAILED.getLabel());
                            record.put("phase", "failed");
                            record.put("progressMessage", error);
                            if (taskEntity != null) {
                                taskEntity.setStatus(TaskStatus.WORKFLOW_FAILED.getValue());
                                taskEntity.setError(error);
                                taskEntity.setFinishedAt(System.currentTimeMillis());
                                saveTaskToIginx(taskEntity);
                            }
                            writeTaskProgress(task, "failed", error);
                        }
                    }
                } catch (Exception ignored) {}
            }
        }
        boolean cancelled = Boolean.TRUE.equals(cancelFlags.get(taskId)) || Files.isRegularFile(child(task, "cancel.flag"));
        if (cancelled && !"completed".equals(phase) && !"failed".equals(phase)) {
            record.put("status", TaskStatus.CANCELLING.getValue());
            record.put("statusLabel", TaskStatus.CANCELLING.getLabel());
            record.put("phase", "cancelling");
            record.put("progressMessage", "取消中；当前DLL调用结束后停止");
        }
        String currentStatus = String.valueOf(record.getOrDefault("status", ""));
        String currentPhase = String.valueOf(record.getOrDefault("phase", ""));
        boolean shouldCheckRunner = TaskStatus.WORKFLOW_RUNNING.getValue().equals(currentStatus)
                || TaskStatus.CANCELLING.getValue().equals(currentStatus);
        if (shouldCheckRunner && !"completed".equals(currentPhase) && !"failed".equals(currentPhase)) {
            Path resultFile = child(task, "result.json");
            if (!Files.isRegularFile(resultFile) && (running == null || !running.containsKey(taskId))) {
                long started = longValue(record.getOrDefault("startedAt", record.getOrDefault("createdAt", 0L)));
                if (started < serviceStartTime) {
                    record.put("status", TaskStatus.WORKFLOW_FAILED.getValue());
                    record.put("statusLabel", TaskStatus.WORKFLOW_FAILED.getLabel());
                    record.put("phase", "failed");
                    record.put("progressMessage", "MATLAB 任务线程已退出且未生成结果");
                try {
                    WorkflowTaskEntity taskEntity = loadTaskFromIginx(ts);
                    if (taskEntity != null) {
                        taskEntity.setStatus(TaskStatus.WORKFLOW_FAILED.getValue());
                        taskEntity.setError("MATLAB 任务线程已退出且未生成结果");
                        taskEntity.setFinishedAt(System.currentTimeMillis());
                        saveTaskToIginx(taskEntity);
                    }
                    writeTaskProgress(task, "failed", "MATLAB 任务线程已退出且未生成结果");
                } catch (Exception ignored) {}
            }
        }
        }
        Path logFile = child(task, "run.log");
        if (Files.isRegularFile(logFile)) {
            try {
                long size = Files.size(logFile);
                int tailSize = (int) Math.min(size, 2048);
                if (tailSize > 0) {
                    byte[] tail = new byte[tailSize];
                    try (java.io.RandomAccessFile raf = new java.io.RandomAccessFile(logFile.toFile(), "r")) {
                        raf.seek(size - tailSize);
                        raf.readFully(tail);
                    }
                    String text = new String(tail, StandardCharsets.UTF_8);
                    String[] lines = text.split("\\r?\\n");
                    String last = null;
                    for (int i = lines.length - 1; i >= 0; i--) {
                        if (!lines[i].trim().isEmpty()) {
                            last = lines[i].trim();
                            break;
                        }
                    }
                    if (last != null) record.put("logLine", last);
                }
            } catch (Exception ignored) {}
        }
        return record;
    }

    public Map<String, Object> getTaskLog(String taskId, String name, String version, String projectName) throws Exception {
        Path task = requireTask(taskId, name, version, projectName);
        Path logFile = child(task, "run.log");
        String content = Files.isRegularFile(logFile)
                ? new String(Files.readAllBytes(logFile), StandardCharsets.UTF_8) : "";
        if (content.length() > 20000) content = content.substring(content.length() - 20000);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("taskId", taskId);
        result.put("content", content);
        return result;
    }

    public Map<String, Object> cancelTask(String taskId, String name, String version, String projectName) throws Exception {
        Path taskDir = requireTask(taskId, name, version, projectName);
        // 从 IGINX 加载任务实体
        long ts = taskTimestamp(taskId);
        WorkflowTaskEntity taskEntity = loadTaskFromIginx(ts);
        if (taskEntity == null) throw new IllegalStateException("任务记录不存在");
        Map<String, Object> task;
        if (!isTerminal(taskEntity.getStatus())) {
            taskEntity.setStatus(TaskStatus.CANCELLING.getValue());
            saveTaskToIginx(taskEntity);
            cancelFlags.put(taskId, true);
            task = taskEntityToMap(taskEntity);
            task.put("cancelRequested", true);
        } else {
            task = taskEntityToMap(taskEntity);
        }
        Files.write(child(taskDir, "cancel.flag"), new byte[]{1});
        MatlabFunctionRunner runner = running.get(taskId);
        if (runner != null) runner.requestCancel();
        return task;
    }

    public Map<String, Object> getResult(String taskId, String name, String version, String projectName) throws Exception {
        Path task = requireTask(taskId, name, version, projectName);
        // 优先从 IGINX 读 result
        long ts = taskTimestamp(taskId);
        WorkflowTaskEntity entity = loadTaskFromIginx(ts);
        if (entity != null && StringUtils.hasText(entity.getResult())) {
            try {
                return mapper.readValue(entity.getResult(), Map.class);
            } catch (Exception ignored) {}
        }
        // 回退到文件
        Path result = child(task, "result.json");
        if (!Files.isRegularFile(result)) throw new IllegalStateException("Task result is not available");
        return readMap(result);
    }

    public Map<String, Object> reviewResult(String taskId, JsonNode request, String name, String version,
                                            String projectName) throws Exception {
        Path taskDir = requireTask(taskId, name, version, projectName);
        String decision = request == null ? "" : text(request, "decision").toUpperCase(Locale.ROOT);
        if (!"APPROVED".equals(decision) && !"REJECTED".equals(decision)) {
            throw new IllegalArgumentException("decision must be APPROVED or REJECTED");
        }
        long ts = taskTimestamp(taskId);
        WorkflowTaskEntity taskEntity = loadTaskFromIginx(ts);
        if (taskEntity == null) throw new IllegalStateException("任务记录不存在");
        if (!TaskStatus.COMPLETED.getValue().equals(taskEntity.getStatus())) throw new IllegalStateException("只有已完成的任务才能审核");
        String notes = request == null ? "" : text(request, "notes");
        if (notes.length() > 2000) throw new IllegalArgumentException("Review notes are too long");
        taskEntity.setReviewStatus("APPROVED".equals(decision) ? TaskStatus.REVIEW_APPROVED.getValue() : TaskStatus.REVIEW_REJECTED.getValue());
        saveTaskToIginx(taskEntity);
        Map<String, Object> task = taskEntityToMap(taskEntity);
        task.put("reviewNotes", notes);
        task.put("reviewedBy", AuthUtil.getCurrentUsername());
        task.put("reviewedAt", System.currentTimeMillis());
        return task;
    }

    public Map<String, Object> publishResult(String taskId, String name, String version,
                                             String projectName) throws Exception {
        Path taskDir = requireTask(taskId, name, version, projectName);
        long ts = taskTimestamp(taskId);
        WorkflowTaskEntity taskEntity = loadTaskFromIginx(ts);
        if (taskEntity == null) throw new IllegalStateException("任务记录不存在");
        if (!TaskStatus.COMPLETED.getValue().equals(taskEntity.getStatus())) throw new IllegalStateException("只有已完成的任务才能发布");
        if (!TaskStatus.REVIEW_APPROVED.getValue().equals(taskEntity.getReviewStatus())) throw new IllegalStateException("结果必须审核通过后才能发布");
        if (!"estimation".equals(taskEntity.getResultType())) throw new IllegalStateException("Only identified model results can be published");
        Map<String, Object> result = readMap(child(taskDir, "result.json"));
        Object summaryObject = result.get("value");
        if (summaryObject instanceof Map) {
            Map<?, ?> summary = (Map<?, ?>) summaryObject;
            if (Boolean.TRUE.equals(summary.get("truthWasRead"))) throw new SecurityException("Truth-contaminated results cannot be published");
            if (summary.containsKey("passed") && !Boolean.TRUE.equals(summary.get("passed"))) {
                throw new IllegalStateException("Result acceptance did not pass");
            }
            Object resultSummary = summary.get("resultSummary");
            if (resultSummary instanceof Map) {
                Object acceptance = ((Map<?, ?>) resultSummary).get("acceptance");
                if (acceptance instanceof Map && ((Map<?, ?>) acceptance).containsKey("formalAccepted")
                        && !Boolean.TRUE.equals(((Map<?, ?>) acceptance).get("formalAccepted"))) {
                    throw new IllegalStateException("Identified model was not formally accepted");
                }
            }
        }
        Map<String, Object> publication = new LinkedHashMap<>();
        publication.put("taskId", taskId);
        publication.put("actionKey", taskEntity.getActionKey());
        publication.put("publishedBy", AuthUtil.getCurrentUsername());
        publication.put("publishedAt", System.currentTimeMillis());
        publication.put("status", TaskStatus.PUBLISHED.getValue());
        // 更新任务实体的发布状态
        taskEntity.setPublicationStatus(TaskStatus.PUBLISHED.getValue());
        saveTaskToIginx(taskEntity);
        return publication;
    }

    public List<Map<String, Object>> listArtifacts(String taskId, String name, String version,
                                                    String projectName) throws Exception {
        Path task = requireTask(taskId, name, version, projectName);
        Path artifacts = child(task, "artifacts.json");
        if (!Files.isRegularFile(artifacts)) return Collections.emptyList();
        List<Map<String, Object>> result = readListOfMaps(artifacts);
        for (Map<String, Object> artifact : result) artifact.remove("relativePath");
        return result;
    }

    public ArtifactDownload getArtifact(String taskId, String artifactId, String name, String version,
                                         String projectName) throws Exception {
        requireId(artifactId, "artifactId");
        Path task = requireTask(taskId, name, version, projectName);
        Map<String, Object> selected = null;
        Path artifactManifest = child(task, "artifacts.json");
        List<Map<String, Object>> storedArtifacts = Files.isRegularFile(artifactManifest)
                ? readListOfMaps(artifactManifest) : Collections.emptyList();
        for (Map<String, Object> artifact : storedArtifacts) {
            if (artifactId.equals(artifact.get("id"))) { selected = artifact; break; }
        }
        if (selected == null) throw new IllegalArgumentException("Artifact does not exist");
        String relativePath = value(selected.get("relativePath"));
        Path workspace = task.getParent().getParent();
        Path file = resolveInside(workspace, relativePath, true);
        if (!Files.isRegularFile(file) || !isAllowedArtifactPath(workspace, file)) {
            throw new SecurityException("Artifact path is not allowed");
        }
        return new ArtifactDownload(value(selected.get("name")), Files.readAllBytes(file));
    }

    @SuppressWarnings("unchecked")
    private void runTask(Path workspace, Path taskDir, Map<String, Object> initialTask,
                         ProgramConfig.WorkflowAction action, Object[] arguments) {
        String taskId = value(initialTask.get("id"));
        Path manifest = taskDir.resolve("task.json");
        Path runLog = taskDir.resolve("run.log");
        MatlabFunctionRunner runner = null;
        Map<String, Stamp> before = Collections.emptyMap();
        try {
            before = snapshotArtifacts(workspace);
            boolean cancelled = Boolean.TRUE.equals(cancelFlags.get(taskId));
            updateTask(manifest, cancelled ? TaskStatus.CANCELLING.getValue() : TaskStatus.WORKFLOW_RUNNING.getValue(), null, System.currentTimeMillis(), false);
            String workspaceId = value(initialTask.get("workspaceId"));
            Map<String, Object> wsRecord = queryWorkspaceFromIginxById(workspaceId);
            Path workingDirectory = resolveInside(workspace.resolve("source"),
                    value(wsRecord != null ? wsRecord.get("workingDirectory") : null), true);
            // 清理上次可能遗留的 0 字节 MAT 文件（MATLAB save -v7.3 写入失败会留下空文件，导致后续 save 也失败）
            cleanupZeroByteMatFiles(workingDirectory);
            Path requestFile = taskDir.resolve("request.json");
            Path taskOutput = child(child(workspace, "output"), taskId);
            Files.createDirectories(taskOutput);
            Path matlabResult = child(taskOutput, "result.mat");
            Path matlabManifest = child(taskOutput, "result-manifest.json");
            if ("uq".equalsIgnoreCase(action.getStage()) && arguments.length > 0 && arguments[0] instanceof Map) {
                Map<String, Object> uqConfig = new LinkedHashMap<>((Map<String, Object>) arguments[0]);
                uqConfig.put("cancelFile", child(taskDir, "cancel.flag").toFile().getCanonicalPath());
                arguments[0] = uqConfig;
            }
            Map<String, Object> adapterRequest = new LinkedHashMap<>();
            adapterRequest.put("argumentCount", arguments.length);
            for (int i = 0; i < arguments.length; i++) adapterRequest.put("arg" + (i + 1), arguments[i]);
            writeJson(requestFile, adapterRequest);

            Object[] adapterArguments = new Object[]{action.getEntryPoint(), requestFile.toFile().getCanonicalPath(),
                    matlabResult.toFile().getCanonicalPath(), matlabManifest.toFile().getCanonicalPath()};
            // 每次运行前重新安装适配器，确保最新版本
            installWorkflowAdapter(workingDirectory);
            runner = new MatlabFunctionRunner(workingDirectory.toFile(), "dmg_run_workflow", adapterArguments,
                    runLog.toFile(), programService.enginePool(), new MatlabFunctionRunner.ProgressCancellationSink() {
                private long lastUpdate;
                private String phase = "pending";
                @Override public void onProgress(String message) {
                    long now = System.currentTimeMillis();
                    java.util.regex.Matcher m = STAGE_PATTERN.matcher(message);
                    boolean isMarker = m.find();
                    if (isMarker) {
                        String stage = m.group(1);
                        String event = m.group(2);
                        if ("START".equals(event)) {
                            phase = stage;
                        } else if ("END".equals(event)) {
                            phase = "D".equals(stage) ? "completed" : stage;
                        }
                        writeTaskProgress(manifest.getParent(), phase, message);
                    }
                    if (!message.startsWith("[stdout]") || now - lastUpdate >= 1000L) {
                        lastUpdate = now;
                        updateTaskMessage(manifest, message);
                        if (!isMarker) writeTaskProgress(manifest.getParent(), phase, message);
                    }
                }
                @Override public boolean isCancellationRequested() {
                    return Boolean.TRUE.equals(cancelFlags.get(taskId));
                }
            });
            running.put(taskId, runner);
            if (Boolean.TRUE.equals(cancelFlags.get(taskId))) runner.requestCancel();
            runner.run();
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("taskId", taskId);
            result.put("actionKey", action.getKey());
            result.put("resultType", action.getResultType());
            result.put("matlabRelease", runner.getActualRelease());
            result.put("value", Files.isRegularFile(matlabManifest) ? readMap(matlabManifest) : Collections.emptyMap());
            result.put("completedAt", System.currentTimeMillis());
            writeJson(taskDir.resolve("result.json"), result);
            writeJson(taskDir.resolve("artifacts.json"), collectArtifacts(workspace, before));
            // 将结果写入 IGINX task 表 result 字段
            long taskTs = taskTimestamp(taskId);
            WorkflowTaskEntity taskEntity = loadTaskFromIginx(taskTs);
            if (taskEntity != null) {
                taskEntity.setResult(mapper.writeValueAsString(result));
                saveTaskToIginx(taskEntity);
            }
            updateTask(manifest, TaskStatus.COMPLETED.getValue(), null, null, true);
        } catch (CancellationException e) {
            finishArtifactsQuietly(workspace, taskDir, before);
            updateTaskQuietly(manifest, TaskStatus.CANCELLING.getValue(), "用户取消，当前DLL调用结束后已停止并保存检查点");
        } catch (Exception e) {
            finishArtifactsQuietly(workspace, taskDir, before);
            try {
                if (Boolean.TRUE.equals(cancelFlags.get(taskId))) {
                    updateTaskQuietly(manifest, TaskStatus.CANCELLING.getValue(), "用户取消，当前DLL调用结束后已停止并保存检查点");
                } else {
                    log.error("MATLAB workflow task {} failed", taskId, e);
                    String errMsg = e.getMessage() != null ? e.getMessage() : "";
                    if (errMsg.contains("test") && errMsg.contains("not found") || errMsg.contains("测试数据不存在")) {
                        updateTaskQuietly(manifest, TaskStatus.SKIPPED.getValue(), "测试数据不存在，已安全跳过测试验证");
                    } else {
                        long ts2 = taskTimestamp(taskId);
                        WorkflowTaskEntity taskEntity2 = loadTaskFromIginx(ts2);
                        if (taskEntity2 != null) {
                            taskEntity2.setStatus(TaskStatus.WORKFLOW_FAILED.getValue());
                            taskEntity2.setError(safeError(e));
                            taskEntity2.setFinishedAt(System.currentTimeMillis());
                            saveTaskToIginx(taskEntity2);
                        }
                    }
                }
            } catch (Exception statusError) {
                log.error("MATLAB workflow task {} failed", taskId, e);
                updateTaskQuietly(manifest, TaskStatus.WORKFLOW_FAILED.getValue(), safeError(e));
            }
        } finally {
            running.remove(taskId);
            cancelFlags.remove(taskId);
        }
    }

    private Object[] resolveArguments(Path workspace, String workspaceId, ProgramConfig config, ProgramConfig.WorkflowAction action,
                                      JsonNode inputs) throws Exception {
        List<String> ordered = action.getInputs() == null ? Collections.emptyList() : action.getInputs();
        // 从 IGINX 查询工作区的 uploadedDatasets
        List<Map<String, Object>> uploaded = queryUploadedDatasetsFromIginx(workspaceId);
        Map<String, Map<String, Object>> uploadedByKey = new HashMap<>();
        for (Map<String, Object> item : uploaded) uploadedByKey.put(value(item.get("datasetKey")), item);
        Set<String> datasetKeys = new LinkedHashSet<>();
        Map<String, ProgramConfig.DatasetSpec> datasetSpecs = new HashMap<>();
        if (config.getWorkflow().getDatasets() != null) {
            for (ProgramConfig.DatasetSpec spec : config.getWorkflow().getDatasets()) {
                datasetKeys.add(spec.getKey());
                datasetSpecs.put(spec.getKey(), spec);
            }
        }
        Object[] arguments = new Object[ordered.size()];
        for (int i = 0; i < ordered.size(); i++) {
            String inputName = ordered.get(i);
            if (datasetKeys.contains(inputName)) {
                ProgramConfig.DatasetSpec datasetSpec = datasetSpecs.get(inputName);
                String stage = value(action.getStage()).toLowerCase(Locale.ROOT);
                if (("identification".equals(stage) || "estimation".equals(stage))
                        && datasetSpec != null && "test".equalsIgnoreCase(datasetSpec.getRole())) {
                    throw new SecurityException("Test datasets cannot be used for parameter estimation");
                }
                Map<String, Object> upload = uploadedByKey.get(inputName);
                if (upload == null) throw new IllegalArgumentException("Dataset has not been uploaded: " + inputName);
                Path file = child(child(workspace, "datasets"), value(upload.get("storedName")));
                if (!Files.isRegularFile(file)) throw new IllegalStateException("Managed dataset file is missing: " + inputName);
                arguments[i] = file.toFile().getCanonicalPath();
            } else {
                JsonNode node = inputValue(inputs, inputName, i);
                if (node == null || node.isMissingNode()) throw new IllegalArgumentException("Missing action input: " + inputName);
                rejectClientPath(node);
                arguments[i] = mapper.convertValue(node, Object.class);
            }
        }
        return arguments;
    }

    private JsonNode inputValue(JsonNode inputs, String name, int index) {
        if (inputs == null || inputs.isNull()) return null;
        if (inputs.isObject()) return inputs.get(name);
        if (inputs.isArray() && index < inputs.size()) return inputs.get(index);
        throw new IllegalArgumentException("inputs must be an object or ordered array");
    }

    private void rejectClientPath(JsonNode node) {
        if (node == null) return;
        if (node.isTextual()) {
            String text = node.asText();
            String normalized = text.replace('\\', '/');
            if (new File(text).isAbsolute() || normalized.startsWith("/") || normalized.matches("^[A-Za-z]:/.*")
                    || normalized.equals("..") || normalized.startsWith("../") || normalized.contains("/../")
                    || normalized.startsWith("file:")) {
                throw new IllegalArgumentException("Client filesystem paths are not accepted as action inputs");
            }
        } else if (node.isContainerNode()) {
            for (JsonNode child : node) rejectClientPath(child);
        }
    }

    private ProgramEntity requireWorkflowProgram(String name, String version, String project) {
        ProgramEntity entity = programService.queryMeta(name, version, project);
        if (entity == null) throw new IllegalArgumentException("Program does not exist");
        parseWorkflowConfig(entity);
        return entity;
    }

    private ProgramConfig parseWorkflowConfig(ProgramEntity entity) {
        ProgramConfig config = ProgramConfigMapper.parse(entity.getConfigJson());
        if (config == null || config.getRuntime() == null
                || !"matlabWorkflow".equals(config.getRuntime().getExecutionType())) {
            throw new IllegalArgumentException("Program config executionType must be matlabWorkflow");
        }
        List<String> errors = ProgramConfigMapper.validate(config, true);
        if (config.getWorkflow() != null && config.getWorkflow().getDatasets() != null) {
            for (ProgramConfig.DatasetSpec dataset : config.getWorkflow().getDatasets()) {
                if (dataset != null && !SAFE_KEY.matcher(value(dataset.getKey())).matches()) {
                    errors.add("workflow.dataset.key format is invalid: " + value(dataset.getKey()));
                }
            }
        }
        if (config.getWorkflow() != null && config.getWorkflow().getActions() != null) {
            for (ProgramConfig.WorkflowAction action : config.getWorkflow().getActions()) {
                if (action == null || action.getInputs() == null) continue;
                for (String input : action.getInputs()) {
                    if (!SAFE_KEY.matcher(value(input)).matches()) errors.add("workflow.action input format is invalid");
                }
            }
        }
        if (!errors.isEmpty()) throw new IllegalArgumentException("Invalid workflow config: " + String.join("; ", errors));
        return config;
    }

    private ProgramConfig configForWorkspace(Path workspace) {
        try {
            Path snapshot = child(workspace, "program-config.json");
            if (!Files.isRegularFile(snapshot)) throw new IllegalStateException("Workspace config snapshot is missing");
            ProgramConfig config = ProgramConfigMapper.parse(new String(Files.readAllBytes(snapshot), StandardCharsets.UTF_8));
            if (config == null) throw new IllegalStateException("Workspace config snapshot is invalid");
            return config;
        } catch (IOException e) {
            throw new IllegalStateException("Workspace config snapshot cannot be read", e);
        }
    }

    private Path requireWorkspace(String id, String name, String version, String projectName) throws Exception {
        requireWorkspaceId(id, "workspaceId");
        String project = effectiveProject(projectName);
        Path workspace = child(workflowRoot(project), id);
        // 从 IGINX 验证 workspace 存在且归属正确
        Map<String, Object> wsRecord = queryWorkspaceFromIginxById(id);
        if (wsRecord == null) throw new IllegalArgumentException("Workspace does not exist");
        if (!matchesProgram(wsRecord, name, version, project)) throw new SecurityException("Workspace does not belong to this program context");
        return workspace;
    }

    private Path requireTask(String taskId, String name, String version, String projectName) throws Exception {
        requireId(taskId, "taskId");
        String project = effectiveProject(projectName);
        // 从 IGINX 查 task 的 workspaceId
        long ts = taskTimestamp(taskId);
        if (ts == 0) throw new IllegalArgumentException("Task does not exist");
        WorkflowTaskEntity taskEntity = loadTaskFromIginx(ts);
        if (taskEntity == null) throw new IllegalArgumentException("Task does not exist");
        String workspaceId = taskEntity.getWorkspaceId();
        if (workspaceId == null) throw new IllegalArgumentException("Task does not exist");
        // 验证 workspace 归属
        Path workspace = requireWorkspace(workspaceId, name, version, projectName);
        Path taskDir = child(child(workspace, "tasks"), taskId);
        return taskDir;
    }

    private Path workflowRoot(String project) throws IOException {
        Path projectRoot = new File("project").getCanonicalFile().toPath();
        Files.createDirectories(projectRoot);
        String safeProj = project != null && !project.isEmpty() ? project : ProjectContext.getCurrentProject("unknown");
        Path root = child(projectRoot, safeProj).resolve("program-workflows");
        Files.createDirectories(root);
        return root;
    }

    private String safeProject(String project) {
        String cleaned = project.replaceAll("[^A-Za-z0-9._-]", "_");
        if (cleaned.isEmpty() || ".".equals(cleaned) || "..".equals(cleaned)) cleaned = "project";
        return cleaned.substring(0, Math.min(48, cleaned.length())) + "-" + shortHash(project);
    }

    /** 将用户输入的项目名转换为安全的目录名，与 ProgramService.safeProjectName 一致：非 ASCII 替换为 undefined */
    private String safeJobName(String jobName) {
        String input = jobName != null ? jobName.trim() : "";
        if (input.isEmpty()) throw new IllegalArgumentException("项目名称不能为空");
        String cleaned = input.replaceAll("[^\\x00-\\x7F]+", "undefined");
        if (cleaned.isEmpty() || ".".equals(cleaned) || "..".equals(cleaned)) {
            throw new IllegalArgumentException("项目名称包含非法字符: " + jobName);
        }
        return cleaned.substring(0, Math.min(128, cleaned.length()));
    }

    private String shortHash(String value) {
        try {
            byte[] bytes = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder();
            for (int i = 0; i < 6; i++) out.append(String.format("%02x", bytes[i]));
            return out.toString();
        } catch (Exception e) { throw new IllegalStateException(e); }
    }

    private Path child(Path parent, String child) throws IOException {
        Path base = parent.toFile().getCanonicalFile().toPath();
        Path target = new File(base.toFile(), child).getCanonicalFile().toPath();
        if (target.equals(base) || !target.startsWith(base)) {
            throw new SecurityException("Path escapes managed workflow storage");
        }
        return target;
    }

    /**
     * 根据目录重命名映射修正相对路径。
     * mapping 的 key/value 均为用 "/" 分隔的相对路径。
     * 如果 path 以某个 key 开头（完整路径段匹配），则替换为对应的 value。
     */
    private String applyDirMapping(String path, Map<String, String> mapping) {
        if (mapping == null || mapping.isEmpty() || path == null) return path;
        String normalized = path.replace('\\', '/');
        for (Map.Entry<String, String> e : mapping.entrySet()) {
            String orig = e.getKey();
            String replacement = e.getValue();
            if (normalized.equals(orig)) return replacement.replace('/', File.separatorChar);
            if (normalized.startsWith(orig + "/")) {
                return (replacement + normalized.substring(orig.length())).replace('/', File.separatorChar);
            }
        }
        return path;
    }

    private Path resolveInside(Path basePath, String relative, boolean requireRelative) throws IOException {
        if (!StringUtils.hasText(relative)) relative = ".";
        Path supplied = new File(relative).toPath();
        if (requireRelative && supplied.isAbsolute()) throw new SecurityException("Absolute paths are not allowed");
        Path base = basePath.toFile().getCanonicalFile().toPath();
        Path target = new File(base.toFile(), relative).getCanonicalFile().toPath();
        if (!target.equals(base) && !target.startsWith(base)) throw new SecurityException("Path escapes managed workspace");
        return target;
    }

    private String effectiveProject(String projectName) {
        String project = StringUtils.hasText(projectName) ? projectName : ProjectContext.getCurrentProject("unknown");
        if (!StringUtils.hasText(project) || project.length() > 200 || containsControl(project)) {
            throw new IllegalArgumentException("Invalid projectName");
        }
        return project;
    }

    private void requireSafeQueryValue(String value, String field) {
        if (!StringUtils.hasText(value) || value.length() > 200 || value.indexOf('\'') >= 0 || containsControl(value)) {
            throw new IllegalArgumentException("Invalid " + field);
        }
    }

    private boolean containsControl(String text) {
        for (int i = 0; i < text.length(); i++) if (Character.isISOControl(text.charAt(i))) return true;
        return false;
    }

    private void requireId(String id, String field) {
        if (id == null || !SAFE_ID.matcher(id).matches()) throw new IllegalArgumentException("Invalid " + field);
    }

    /** workspace id 可以是旧 UUID 或新的 jobName-hash 格式 */
    private void requireWorkspaceId(String id, String field) {
        if (id == null || !SAFE_WORKSPACE_DIR.matcher(id).matches()) throw new IllegalArgumentException("Invalid " + field);
    }

    private boolean matchesProgram(Map<String, Object> record, String name, String version, String project) {
        return value(record.get("projectName")).equals(project)
                && (!StringUtils.hasText(name) || value(record.get("programName")).equals(name))
                && (!StringUtils.hasText(version) || value(record.get("programVersion")).equals(version));
    }

    private ProgramConfig.DatasetSpec findDataset(ProgramConfig config, String key) {
        if (config.getWorkflow().getDatasets() == null) return null;
        for (ProgramConfig.DatasetSpec spec : config.getWorkflow().getDatasets()) if (key.equals(spec.getKey())) return spec;
        return null;
    }

    private ProgramConfig.WorkflowAction findAction(ProgramConfig config, String key) {
        if (config.getWorkflow().getActions() == null) return null;
        for (ProgramConfig.WorkflowAction action : config.getWorkflow().getActions()) if (key.equals(action.getKey())) return action;
        return null;
    }

    private List<Map<String, Object>> datasetSpecs(ProgramConfig config) {
        List<Map<String, Object>> result = new ArrayList<>();
        if (config.getWorkflow().getDatasets() == null) return result;
        for (ProgramConfig.DatasetSpec spec : config.getWorkflow().getDatasets()) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("key", spec.getKey()); item.put("label", spec.getLabel()); item.put("type", spec.getType());
            item.put("role", spec.getRole()); item.put("required", Boolean.TRUE.equals(spec.getRequired()));
            item.put("requiredColumns", spec.getRequiredColumns()); result.add(item);
        }
        return result;
    }

    private List<Map<String, Object>> actionSpecs(ProgramConfig config) {
        List<Map<String, Object>> result = new ArrayList<>();
        for (ProgramConfig.WorkflowAction action : config.getWorkflow().getActions()) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("key", action.getKey()); item.put("label", action.getLabel()); item.put("stage", action.getStage());
            item.put("inputs", action.getInputs()); item.put("resultType", action.getResultType()); result.add(item);
        }
        return result;
    }

    private Map<String, Object> publicDataset(Map<String, Object> stored) {
        Map<String, Object> result = new LinkedHashMap<>(stored);
        result.remove("storedName");
        return result;
    }

    private Map<String, Stamp> snapshotArtifacts(Path workspace) throws IOException {
        Map<String, Stamp> result = new HashMap<>();
        for (Path root : artifactRoots(workspace)) {
            if (!Files.isDirectory(root)) continue;
            try (Stream<Path> files = Files.walk(root)) {
                for (Path file : (Iterable<Path>) files::iterator) if (Files.isRegularFile(file)) {
                    result.put(file.toFile().getCanonicalPath(), new Stamp(Files.size(file), Files.getLastModifiedTime(file).toMillis()));
                }
            }
        }
        return result;
    }

    private List<Map<String, Object>> collectArtifacts(Path workspace, Map<String, Stamp> before) throws Exception {
        List<Map<String, Object>> artifacts = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (Path root : artifactRoots(workspace)) {
            if (!Files.isDirectory(root)) continue;
            try (Stream<Path> files = Files.walk(root)) {
                for (Path file : (Iterable<Path>) files::iterator) {
                    if (!Files.isRegularFile(file)) continue;
                    String canonical = file.toFile().getCanonicalPath();
                    if (!seen.add(canonical)) continue;
                    Stamp old = before.get(canonical);
                    long size = Files.size(file), modified = Files.getLastModifiedTime(file).toMillis();
                    if (old != null && old.size == size && old.modified == modified) continue;
                    Map<String, Object> artifact = new LinkedHashMap<>();
                    artifact.put("id", UUID.randomUUID().toString());
                    artifact.put("name", file.getFileName().toString());
                    artifact.put("relativePath", workspace.relativize(file).toString().replace(File.separatorChar, '/'));
                    artifact.put("size", size); artifact.put("modifiedAt", modified);
                    artifact.put("sha256", sha256(file));
                    artifacts.add(artifact);
                }
            }
        }
        artifacts.sort(Comparator.comparing(item -> value(item.get("relativePath"))));
        return artifacts;
    }

    private List<Path> artifactRoots(Path workspace) throws IOException {
        List<Path> roots = new ArrayList<>();
        roots.add(child(workspace, "output"));
        Path source = child(workspace, "source");
        if (Files.isDirectory(source)) {
            try (Stream<Path> dirs = Files.walk(source, 16)) {
                for (Path dir : (Iterable<Path>) dirs::iterator) if (Files.isDirectory(dir)
                        && ARTIFACT_DIRECTORY_NAMES.contains(dir.getFileName().toString().toLowerCase(Locale.ROOT))) roots.add(dir);
            }
        }
        return roots;
    }

    private boolean isAllowedArtifactPath(Path workspace, Path file) throws IOException {
        Path canonical = file.toFile().getCanonicalFile().toPath();
        for (Path root : artifactRoots(workspace)) {
            Path allowed = root.toFile().getCanonicalFile().toPath();
            if (canonical.startsWith(allowed)) return true;
        }
        return false;
    }

    private void finishArtifactsQuietly(Path workspace, Path taskDir, Map<String, Stamp> before) {
        try { writeJson(taskDir.resolve("artifacts.json"), collectArtifacts(workspace, before)); }
        catch (Exception ignored) { }
    }

    /** 清理工作目录下所有 0 字节的 .mat 文件（MATLAB save -v7.3 写入失败会留下空文件，导致后续 save 也失败） */
    private void cleanupZeroByteMatFiles(Path workingDirectory) {
        try {
            Path middleData = workingDirectory.resolve("MiddleData");
            if (!Files.isDirectory(middleData)) return;
            try (Stream<Path> files = Files.walk(middleData, 3)) {
                files.filter(Files::isRegularFile)
                     .filter(p -> p.getFileName().toString().endsWith(".mat"))
                     .filter(p -> {
                         try { return Files.size(p) == 0; }
                         catch (IOException e) { return false; }
                     })
                     .forEach(p -> {
                         try {
                             Files.delete(p);
                             log.info("已清理 0 字节 MAT 文件: {}", p);
                         } catch (IOException e) {
                             log.warn("清理 0 字节 MAT 文件失败: {}", p, e);
                         }
                     });
            }
        } catch (Exception e) {
            log.debug("清理 0 字节 MAT 文件时出错", e);
        }
    }

    private void addStatusLabel(Map<String, Object> record) {
        if (record == null) return;
        Object status = record.get("status");
        if (status != null) record.put("statusLabel", TaskStatus.label(String.valueOf(status)));
        Object reviewStatus = record.get("reviewStatus");
        if (reviewStatus != null) record.put("reviewStatusLabel", TaskStatus.label(String.valueOf(reviewStatus)));
        Object pubStatus = record.get("publicationStatus");
        if (pubStatus != null) record.put("publicationStatusLabel", TaskStatus.label(String.valueOf(pubStatus)));
    }

    private void updateTask(Path manifest, String status, String error, Long startedAt, boolean completed) throws IOException {
        long ts = extractTimestampFromTaskPath(manifest);
        WorkflowTaskEntity task = loadTaskFromIginx(ts);
        if (task == null) {
            // IGINX 中不存在，从 JSON 文件回退加载
            Map<String, Object> taskMap = readMap(manifest);
            task = new WorkflowTaskEntity();
            task.setTimestamp(ts);
            task.setTaskId(value(taskMap.get("id")));
            task.setWorkspaceId(value(taskMap.get("workspaceId")));
            task.setActionKey(value(taskMap.get("actionKey")));
            task.setEntryPoint(value(taskMap.get("entryPoint")));
            task.setStage(value(taskMap.get("stage")));
            task.setResultType(value(taskMap.get("resultType")));
            task.setStatus(value(taskMap.get("status")));
            task.setCreatedAt(longValue(taskMap.get("createdAt")));
            task.setStartedAt(longValue(taskMap.get("startedAt")));
            task.setFinishedAt(longValue(taskMap.get("finishedAt")));
            task.setLogPath(value(taskMap.get("logPath")));
            task.setStatusMessage(value(taskMap.get("statusMessage")));
            task.setReviewStatus(value(taskMap.get("reviewStatus")));
            task.setPublicationStatus(value(taskMap.get("publicationStatus")));
        }
        task.setStatus(status);
        if (startedAt != null) task.setStartedAt(startedAt);
        if (completed || isTerminal(status)) task.setFinishedAt(System.currentTimeMillis());
        if (error != null) task.setError(error);
        if (TaskStatus.COMPLETED.getValue().equals(status) && "estimation".equals(task.getResultType())) {
            task.setReviewStatus(TaskStatus.PENDING_REVIEW.getValue());
        }
        saveTaskToIginx(task);
    }

    private void updateTaskMessage(Path manifest, String message) {
        try {
            long ts = extractTimestampFromTaskPath(manifest);
            WorkflowTaskEntity task = loadTaskFromIginx(ts);
            if (task == null) return;
            task.setStatusMessage(message);
            saveTaskToIginx(task);
        } catch (Exception e) {
            log.debug("Could not persist workflow progress: {}", e.getMessage());
        }
    }

    private void writeTaskProgress(Path taskDir, String phase, String message) {
        try {
            Map<String, Object> progress = new LinkedHashMap<>();
            progress.put("phase", phase);
            progress.put("message", message);
            progress.put("updatedAt", System.currentTimeMillis());
            writeJson(child(taskDir, "task-progress.json"), progress);
        } catch (Exception e) {
            log.debug("Could not write task progress file: {}", e.getMessage());
        }
    }

    private void updateTaskQuietly(Path manifest, String status, String error) {
        try { updateTask(manifest, status, error, null, true); }
        catch (Exception e) { log.error("Could not persist workflow task status", e); }
    }

    private boolean isTerminal(String status) {
        return TaskStatus.isTerminal(status);
    }

    private void validateWorkflowFiles(Path workingDirectory, ProgramConfig config) throws IOException {
        List<String> missing = new ArrayList<>();
        for (ProgramConfig.WorkflowAction action : config.getWorkflow().getActions()) {
            Path entry = resolveInside(workingDirectory, action.getEntryPoint() + ".m", true);
            if (!Files.isRegularFile(entry)) missing.add(action.getEntryPoint() + ".m");
        }
        if (config.getWorkflow().getRequiredFiles() != null) {
            for (String required : config.getWorkflow().getRequiredFiles()) {
                Path file = resolveInside(workingDirectory, required, true);
                if (!Files.exists(file)) missing.add(required);
            }
        }
        if (!missing.isEmpty()) throw new IllegalArgumentException("Program package is missing required files: " + String.join(", ", missing));
    }

    private Map<String, String> requiredFileHashes(Path workingDirectory, ProgramConfig config) throws Exception {
        Map<String, String> hashes = new LinkedHashMap<>();
        if (config.getWorkflow().getRequiredFiles() != null) {
            for (String required : config.getWorkflow().getRequiredFiles()) {
                Path file = resolveInside(workingDirectory, required, true);
                if (Files.isRegularFile(file)) hashes.put(required, sha256(file));
            }
        }
        return hashes;
    }

    private String sha256Text(String value) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] bytes = digest.digest(value.getBytes(StandardCharsets.UTF_8));
        StringBuilder output = new StringBuilder();
        for (byte item : bytes) output.append(String.format("%02x", item));
        return output.toString();
    }

    private void installWorkflowAdapter(Path workingDirectory) throws IOException {
        Path target = child(workingDirectory, "dmg_run_workflow.m");
        try (InputStream input = ProgramWorkflowService.class.getResourceAsStream("/matlab/dmg_run_workflow.m")) {
            if (input == null) throw new IOException("缺少MATLAB工作流适配器资源");
            Files.copy(input, target, StandardCopyOption.REPLACE_EXISTING);
        }
        Path initTarget = child(workingDirectory, "dmg_init_project.m");
        try (InputStream input = ProgramWorkflowService.class.getResourceAsStream("/matlab/dmg_init_project.m")) {
            if (input == null) throw new IOException("缺少MATLAB项目初始化适配器资源");
            Files.copy(input, initTarget, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> readMap(Path path) throws IOException {
        return mapper.readValue(path.toFile(), LinkedHashMap.class);
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> readListOfMaps(Path path) throws IOException {
        if (!Files.isRegularFile(path)) return new ArrayList<>();
        return mapper.readValue(path.toFile(), List.class);
    }

    private void writeJson(Path path, Object value) throws IOException {
        Files.createDirectories(path.getParent());
        Path temporary = path.resolveSibling(path.getFileName() + ".tmp-" + UUID.randomUUID());
        mapper.writeValue(temporary.toFile(), value);
        try { Files.move(temporary, path, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE); }
        catch (AtomicMoveNotSupportedException e) { Files.move(temporary, path, StandardCopyOption.REPLACE_EXISTING); }
    }

    private Object lock(Path path) { return fileLocks.computeIfAbsent(path.toAbsolutePath().normalize().toString(), key -> new Object()); }
    private String text(JsonNode request, String field) { JsonNode node = request.get(field); return node == null ? "" : node.asText(""); }
    private String value(Object value) { return value == null ? "" : String.valueOf(value); }
    private long longValue(Object value) { return value instanceof Number ? ((Number) value).longValue() : 0L; }
    private void validateDatasetFile(ProgramConfig.DatasetSpec spec, MultipartFile file) throws Exception {
        if (file.getSize() > 2L * 1024L * 1024L * 1024L) {
            throw new IllegalArgumentException("Dataset file exceeds the 2GB limit");
        }
        String type = value(spec.getType()).toLowerCase(Locale.ROOT);
        String fileName = value(file.getOriginalFilename()).toLowerCase(Locale.ROOT);
        if ("xlsx".equals(type) && !(fileName.endsWith(".xlsx") || fileName.endsWith(".xls"))) {
            throw new IllegalArgumentException("Dataset must be an Excel file");
        }
        if ("csv".equals(type) && !fileName.endsWith(".csv")) {
            throw new IllegalArgumentException("Dataset must be a CSV file");
        }
        if ("xlsx".equals(type) && spec.getRequiredColumns() != null && !spec.getRequiredColumns().isEmpty()) {
            Set<String> columns = new LinkedHashSet<>();
            try (InputStream input = file.getInputStream(); Workbook workbook = WorkbookFactory.create(input)) {
                if (workbook.getNumberOfSheets() < 1) throw new IllegalArgumentException("Dataset workbook has no sheets");
                Sheet sheet = workbook.getSheetAt(0);
                Row header = sheet.getRow(sheet.getFirstRowNum());
                if (header == null) throw new IllegalArgumentException("Dataset workbook has no header row");
                DataFormatter formatter = new DataFormatter();
                for (int i = header.getFirstCellNum(); i < header.getLastCellNum(); i++) {
                    if (i >= 0) columns.add(formatter.formatCellValue(header.getCell(i)).trim());
                }
            }
            List<String> missing = new ArrayList<>();
            for (String required : spec.getRequiredColumns()) if (!columns.contains(required)) missing.add(required);
            if (!missing.isEmpty()) throw new IllegalArgumentException("Dataset is missing required columns: " + String.join(", ", missing));
        }
    }

    private String sha256(Path path) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = Files.newInputStream(path)) {
            byte[] buffer = new byte[65536];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        StringBuilder value = new StringBuilder();
        for (byte item : digest.digest()) value.append(String.format("%02x", item));
        return value.toString();
    }

    private String safeFileName(String value, String fallback) {
        String name = StringUtils.hasText(value) ? new File(value).getName() : fallback;
        name = name.replaceAll("[^A-Za-z0-9._-]", "_");
        return name.isEmpty() || ".".equals(name) || "..".equals(name) ? fallback : name;
    }
    private Map<String, Object> buildErrorDetail(Exception e, String stage, Path logFile) {
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("说明", safeError(e));
        detail.put("受影响阶段", stage != null ? stage : "未知");
        String matlabId = null;
        if (e.getStackTrace() != null && e.getStackTrace().length > 0) {
            for (StackTraceElement ste : e.getStackTrace()) {
                if (ste.getClassName() != null && ste.getClassName().contains("matlab")) {
                    matlabId = ste.getClassName() + "." + ste.getMethodName() + ":" + ste.getLineNumber();
                    break;
                }
            }
        }
        detail.put("MATLAB异常标识符", matlabId != null ? matlabId : "无");
        detail.put("完整日志路径", logFile != null ? logFile.toAbsolutePath().toString() : "无");
        String msg = e.getMessage() != null ? e.getMessage() : "";
        String suggestion;
        if (msg.contains("DLL") || msg.contains("dll") || msg.contains("native")) {
            suggestion = "DLL 共同工作失败，请检查 DLL 版本和工况参数，重试或联系算法维护人员";
        } else if (msg.contains("fingerprint") || msg.contains("hash") || msg.contains("指纹")) {
            suggestion = "结果指纹不兼容，请重新运行相关步骤";
        } else if (msg.contains("posterior") || msg.contains("后验") || msg.contains("sample")) {
            suggestion = "后验样本不足，不给出正式区间，保留诊断结果供参考";
        } else if (msg.contains("cancel") || msg.contains("取消")) {
            suggestion = "用户取消，当前 DLL 调用结束后已停止并保存检查点";
        } else if (msg.contains("test") || msg.contains("测试")) {
            suggestion = "测试数据不存在，已安全跳过测试验证";
        } else {
            suggestion = "请查看完整日志，检查输入数据和配置后重试";
        }
        detail.put("建议处置", suggestion);
        return detail;
    }

    private String safeError(Exception e) {
        String message = e.getMessage();
        if (!StringUtils.hasText(message)) message = e.getClass().getSimpleName();
        return message.length() > 2000 ? message.substring(0, 2000) : message;
    }

    private static final class Stamp {
        private final long size;
        private final long modified;
        private Stamp(long size, long modified) { this.size = size; this.modified = modified; }
    }

    public static final class ArtifactDownload {
        private final String fileName;
        private final byte[] bytes;
        private ArtifactDownload(String fileName, byte[] bytes) { this.fileName = fileName; this.bytes = bytes; }
        public String getFileName() { return fileName; }
        public byte[] getBytes() { return bytes; }
    }

    // ===================== IGINX 持久化 =====================

    /** 将工作区实体写入 IGINX */
    private void saveWorkspaceToIginx(WorkflowWorkspaceEntity entity) {
        try {
            List<Point> points = ConvertUtil.entityToPoints(entity, WF_WORKSPACE_PREFIX, entity.getTimestamp());
            iginxClient.getWriteClient().writePoints(points);
            log.info("工作区元数据已保存到 IGINX: id={}, timestamp={}", entity.getId(), entity.getTimestamp());
        } catch (Exception e) {
            log.error("保存工作区元数据到 IGINX 失败", e);
        }
    }

    /** 更新工作区实体到 IGINX（用原始时间戳覆盖写入） */
    private void updateWorkspaceInIginx(WorkflowWorkspaceEntity entity) {
        try {
            List<Point> points = ConvertUtil.entityToPoints(entity, WF_WORKSPACE_PREFIX, entity.getTimestamp());
            iginxClient.getWriteClient().writePoints(points);
            log.info("工作区元数据已更新到 IGINX: id={}, timestamp={}", entity.getId(), entity.getTimestamp());
        } catch (Exception e) {
            log.error("更新工作区元数据到 IGINX 失败", e);
        }
    }

    /** 将 IGINX 查询记录转换为 WorkflowWorkspaceEntity */
    private WorkflowWorkspaceEntity iginxRecordToWorkspaceEntity(Map<String, Object> record) {
        WorkflowWorkspaceEntity entity = new WorkflowWorkspaceEntity();
        for (Map.Entry<String, Object> entry : record.entrySet()) {
            String fullKey = entry.getKey();
            String fieldName = fullKey.substring(fullKey.lastIndexOf('.') + 1);
            Object value = entry.getValue();
            if (value instanceof byte[]) {
                value = ConvertUtil.bytesToString((byte[]) value);
            }
            switch (fieldName) {
                case "timestamp": entity.setTimestamp(value instanceof Number ? ((Number) value).longValue() : null); break;
                case "id": entity.setId(String.valueOf(value)); break;
                case "programName": entity.setProgramName(String.valueOf(value)); break;
                case "programVersion": entity.setProgramVersion(String.valueOf(value)); break;
                case "projectName": entity.setProjectName(String.valueOf(value)); break;
                case "jobName": entity.setJobName(String.valueOf(value)); break;
                case "notes": entity.setNotes(String.valueOf(value)); break;
                case "trainingDataFile": entity.setTrainingDataFile(String.valueOf(value)); break;
                case "testDataFile": entity.setTestDataFile(String.valueOf(value)); break;
                case "status": entity.setStatus(String.valueOf(value)); break;
                case "workingDirectory": entity.setWorkingDirectory(String.valueOf(value)); break;
                case "workspaceDir": entity.setWorkspaceDir(String.valueOf(value)); break;
                case "programFileMd5": entity.setProgramFileMd5(String.valueOf(value)); break;
                case "configSha256": entity.setConfigSha256(String.valueOf(value)); break;
                case "createdAt": entity.setCreatedAt(value instanceof Number ? ((Number) value).longValue() : null); break;
                case "updatedAt": entity.setUpdatedAt(value instanceof Number ? ((Number) value).longValue() : null); break;
                case "initStatus": entity.setInitStatus(String.valueOf(value)); break;
                case "initMessage": entity.setInitMessage(String.valueOf(value)); break;
                case "initRowCount": entity.setInitRowCount(value instanceof Number ? ((Number) value).intValue() : null); break;
                case "initGroupCount": entity.setInitGroupCount(value instanceof Number ? ((Number) value).intValue() : null); break;
                case "initDllHash": entity.setInitDllHash(String.valueOf(value)); break;
                case "initValid": entity.setInitValid(value instanceof Boolean ? (Boolean) value : Boolean.parseBoolean(String.valueOf(value))); break;
                case "initBaselineValid": entity.setInitBaselineValid(value instanceof Boolean ? (Boolean) value : Boolean.parseBoolean(String.valueOf(value))); break;
                case "initMissingColumns": entity.setInitMissingColumns(String.valueOf(value)); break;
                case "initStartedAt": entity.setInitStartedAt(String.valueOf(value)); break;
                case "initCompletedAt": entity.setInitCompletedAt(String.valueOf(value)); break;
                case "uploadedDatasets": entity.setUploadedDatasets(String.valueOf(value)); break;
                case "dataContract": entity.setDataContract(String.valueOf(value)); break;
                case "requiredFileHashes": entity.setRequiredFileHashes(String.valueOf(value)); break;
            }
        }
        return entity;
    }

    /** 将 WorkflowWorkspaceEntity 转换为界面返回的 Map */
    private Map<String, Object> workspaceEntityToMap(WorkflowWorkspaceEntity entity) {
        Map<String, Object> ws = new LinkedHashMap<>();
        ws.put("timestamp", entity.getTimestamp());
        ws.put("id", entity.getId());
        ws.put("programName", entity.getProgramName());
        ws.put("programVersion", entity.getProgramVersion());
        ws.put("projectName", entity.getProjectName());
        ws.put("jobName", entity.getJobName());
        ws.put("notes", entity.getNotes());
        ws.put("trainingDataFile", entity.getTrainingDataFile());
        ws.put("testDataFile", entity.getTestDataFile());
        ws.put("status", entity.getStatus());
        ws.put("workingDirectory", entity.getWorkingDirectory());
        ws.put("workspaceDir", entity.getWorkspaceDir());
        ws.put("programFileMd5", entity.getProgramFileMd5());
        ws.put("configSha256", entity.getConfigSha256());
        ws.put("createdAt", entity.getCreatedAt());
        ws.put("updatedAt", entity.getUpdatedAt());
        // 初始化摘要独立字段
        ws.put("initStatus", entity.getInitStatus());
        ws.put("initMessage", entity.getInitMessage());
        ws.put("initRowCount", entity.getInitRowCount());
        ws.put("initGroupCount", entity.getInitGroupCount());
        ws.put("initDllHash", entity.getInitDllHash());
        ws.put("initValid", entity.getInitValid());
        ws.put("initBaselineValid", entity.getInitBaselineValid());
        if (StringUtils.hasText(entity.getInitMissingColumns())) {
            ws.put("initMissingColumns", Arrays.asList(entity.getInitMissingColumns().split(",")));
        } else {
            ws.put("initMissingColumns", Collections.emptyList());
        }
        ws.put("initStartedAt", entity.getInitStartedAt());
        ws.put("initCompletedAt", entity.getInitCompletedAt());
        // JSON 字段反序列化
        if (StringUtils.hasText(entity.getUploadedDatasets())) {
            try { ws.put("uploadedDatasets", mapper.readValue(entity.getUploadedDatasets(), Object.class)); } catch (Exception ignored) {}
        }
        if (StringUtils.hasText(entity.getDataContract())) {
            try { ws.put("dataContract", mapper.readValue(entity.getDataContract(), Object.class)); } catch (Exception ignored) {}
        }
        if (StringUtils.hasText(entity.getRequiredFileHashes())) {
            try { ws.put("requiredFileHashes", mapper.readValue(entity.getRequiredFileHashes(), Object.class)); } catch (Exception ignored) {}
        }
        return ws;
    }

    /** 从 IGINX 查询工作区的 uploadedDatasets */
    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> queryUploadedDatasetsFromIginx(String workspaceId) {
        try {
            Map<String, Object> ws = queryWorkspaceFromIginxById(workspaceId);
            if (ws == null) return new ArrayList<>();
            Object uploaded = ws.get("uploadedDatasets");
            if (uploaded instanceof List) return (List<Map<String, Object>>) uploaded;
            if (uploaded instanceof String && StringUtils.hasText((String) uploaded)) {
                return mapper.readValue((String) uploaded, List.class);
            }
            return new ArrayList<>();
        } catch (Exception e) {
            log.error("从 IGINX 查询 uploadedDatasets 失败: workspaceId={}", workspaceId, e);
            return new ArrayList<>();
        }
    }

    /** 从 IGINX 查询工作区列表（SQL 模式） */
    private List<Map<String, Object>> queryWorkspacesFromIginx(String name, String version, String project) {
        try {
            StringBuilder sql = new StringBuilder("SELECT * FROM " + WF_WORKSPACE_PREFIX + " WHERE 1=1");
            if (StringUtils.hasText(name)) {
                sql.append(" AND programName = '").append(name).append("'");
            }
            if (StringUtils.hasText(version)) {
                sql.append(" AND programVersion = '").append(version).append("'");
            }
            if (StringUtils.hasText(project)) {
                sql.append(" AND projectName = '").append(project).append("'");
            }
            sql.append(" ORDER BY timestamp DESC;");
            log.info("执行SQL: {}", sql);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            if (records == null) return new ArrayList<>();
            List<Map<String, Object>> result = new ArrayList<>();
            for (Map<String, Object> record : records) {
                WorkflowWorkspaceEntity entity = iginxRecordToWorkspaceEntity(record);
                Map<String, Object> ws = workspaceEntityToMap(entity);
                addStatusLabel(ws);
                result.add(ws);
            }
            return result;
        } catch (Exception e) {
            log.error("从 IGINX 查询工作区列表失败", e);
            return new ArrayList<>();
        }
    }

    /** 从 IGINX 按 id 查询单个工作区 */
    private Map<String, Object> queryWorkspaceFromIginxById(String id) {
        try {
            String sql = String.format("SELECT * FROM %s WHERE id = '%s' ORDER BY timestamp DESC;",
                    WF_WORKSPACE_PREFIX, id);
            log.info("执行SQL: {}", sql);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            if (records == null || records.isEmpty()) return null;
            WorkflowWorkspaceEntity entity = iginxRecordToWorkspaceEntity(records.get(0));
            Map<String, Object> ws = workspaceEntityToMap(entity);
            addStatusLabel(ws);
            return ws;
        } catch (Exception e) {
            log.error("从 IGINX 查询工作区失败: id={}", id, e);
            return null;
        }
    }

    /** 将工作流任务实体写入 IGINX */
    private void saveTaskToIginx(WorkflowTaskEntity entity) {
        try {
            List<Point> points = ConvertUtil.entityToPoints(entity, WF_TASK_PREFIX, entity.getTimestamp());
            iginxClient.getWriteClient().writePoints(points);
            log.info("工作流任务记录已保存到 IGINX: taskId={}, timestamp={}", entity.getTaskId(), entity.getTimestamp());
        } catch (Exception e) {
            log.error("保存工作流任务记录到 IGINX 失败", e);
        }
    }

    /** 从 IGINX 加载任务实体 */
    private WorkflowTaskEntity loadTaskFromIginx(long timestamp) {
        try {
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(WorkflowTaskEntity.class, WF_TASK_PREFIX);
            IginXTable table = iginxClient.getQueryClient().query(
                SimpleQuery.builder()
                    .addMeasurements(new java.util.HashSet<>(measurements))
                    .startKey(timestamp - 1)
                    .endKey(timestamp + 1)
                    .build()
            );
            if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) return null;
            IginXRecord record = table.getRecords().get(0);
            WorkflowTaskEntity entity = new WorkflowTaskEntity();
            entity.setTimestamp(timestamp);
            for (String path : measurements) {
                Object value = record.getValue(path);
                if (value == null) continue;
                String fieldName = path.substring(path.lastIndexOf('.') + 1);
                String strValue = value instanceof byte[] ? ConvertUtil.bytesToString((byte[]) value) : value.toString();
                switch (fieldName) {
                    case "taskId": entity.setTaskId(strValue); break;
                    case "workspaceId": entity.setWorkspaceId(strValue); break;
                    case "actionKey": entity.setActionKey(strValue); break;
                    case "entryPoint": entity.setEntryPoint(strValue); break;
                    case "stage": entity.setStage(strValue); break;
                    case "resultType": entity.setResultType(strValue); break;
                    case "status": entity.setStatus(strValue); break;
                    case "createdAt": entity.setCreatedAt(value instanceof Number ? ((Number) value).longValue() : null); break;
                    case "startedAt": entity.setStartedAt(value instanceof Number ? ((Number) value).longValue() : null); break;
                    case "finishedAt": entity.setFinishedAt(value instanceof Number ? ((Number) value).longValue() : null); break;
                    case "logPath": entity.setLogPath(strValue); break;
                    case "statusMessage": entity.setStatusMessage(strValue); break;
                    case "reviewStatus": entity.setReviewStatus(strValue); break;
                    case "publicationStatus": entity.setPublicationStatus(strValue); break;
                    case "result": entity.setResult(strValue); break;
                }
            }
            return entity;
        } catch (Exception e) {
            log.error("从 IGINX 加载工作流任务失败: timestamp={}", timestamp, e);
            return null;
        }
    }

    /** 从 taskId 直接解析 timestamp（taskId 即为时间戳字符串） */
    private long taskTimestamp(String taskId) {
        try {
            return Long.parseLong(taskId);
        } catch (NumberFormatException e) {
            log.warn("taskId 不是有效时间戳: {}", taskId);
            return 0;
        }
    }

    /** 从任务路径提取 timestamp（taskDir 名为 taskId，即时间戳） */
    private long extractTimestampFromTaskPath(Path manifest) {
        Path taskDir = manifest.getParent();
        if (taskDir == null) return 0;
        String taskId = taskDir.getFileName().toString();
        return taskTimestamp(taskId);
    }

    /** 从 IGINX 查询工作区下的任务列表（SQL 模式） */
    private List<Map<String, Object>> queryTasksFromIginx(String workspaceId) {
        try {
            String sql = String.format("SELECT * FROM %s WHERE workspaceId = '%s' ORDER BY timestamp DESC;",
                    WF_TASK_PREFIX, workspaceId);
            log.info("执行SQL: {}", sql);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            if (records == null) return new ArrayList<>();
            List<Map<String, Object>> result = new ArrayList<>();
            for (Map<String, Object> record : records) {
                WorkflowTaskEntity entity = iginxRecordToTaskEntity(record);
                Map<String, Object> task = taskEntityToMap(entity);
                addStatusLabel(task);
                result.add(task);
            }
            return result;
        } catch (Exception e) {
            log.error("从 IGINX 查询任务列表失败: workspaceId={}", workspaceId, e);
            return new ArrayList<>();
        }
    }

    /** 将 IGINX 查询记录转换为 WorkflowTaskEntity */
    private WorkflowTaskEntity iginxRecordToTaskEntity(Map<String, Object> record) {
        WorkflowTaskEntity entity = new WorkflowTaskEntity();
        for (Map.Entry<String, Object> entry : record.entrySet()) {
            String fullKey = entry.getKey();
            String fieldName = fullKey.substring(fullKey.lastIndexOf('.') + 1);
            Object value = entry.getValue();
            if (value instanceof byte[]) {
                value = ConvertUtil.bytesToString((byte[]) value);
            }
            switch (fieldName) {
                case "timestamp": entity.setTimestamp(value instanceof Number ? ((Number) value).longValue() : null); break;
                case "taskId": entity.setTaskId(String.valueOf(value)); break;
                case "workspaceId": entity.setWorkspaceId(String.valueOf(value)); break;
                case "actionKey": entity.setActionKey(String.valueOf(value)); break;
                case "entryPoint": entity.setEntryPoint(String.valueOf(value)); break;
                case "stage": entity.setStage(String.valueOf(value)); break;
                case "resultType": entity.setResultType(String.valueOf(value)); break;
                case "status": entity.setStatus(String.valueOf(value)); break;
                case "createdAt": entity.setCreatedAt(value instanceof Number ? ((Number) value).longValue() : null); break;
                case "startedAt": entity.setStartedAt(value instanceof Number ? ((Number) value).longValue() : null); break;
                case "finishedAt": entity.setFinishedAt(value instanceof Number ? ((Number) value).longValue() : null); break;
                case "logPath": entity.setLogPath(String.valueOf(value)); break;
                case "statusMessage": entity.setStatusMessage(String.valueOf(value)); break;
                case "reviewStatus": entity.setReviewStatus(String.valueOf(value)); break;
                case "publicationStatus": entity.setPublicationStatus(String.valueOf(value)); break;
                case "result": entity.setResult(String.valueOf(value)); break;
            }
        }
        return entity;
    }

    /** 将 WorkflowTaskEntity 转换为界面返回的 Map */
    private Map<String, Object> taskEntityToMap(WorkflowTaskEntity entity) {
        Map<String, Object> task = new LinkedHashMap<>();
        task.put("id", entity.getTaskId());
        task.put("taskId", entity.getTaskId());
        task.put("workspaceId", entity.getWorkspaceId());
        task.put("actionKey", entity.getActionKey());
        task.put("entryPoint", entity.getEntryPoint());
        task.put("stage", entity.getStage());
        task.put("resultType", entity.getResultType());
        task.put("status", entity.getStatus());
        task.put("createdAt", entity.getCreatedAt());
        task.put("startedAt", entity.getStartedAt());
        task.put("finishedAt", entity.getFinishedAt());
        task.put("logPath", entity.getLogPath());
        task.put("statusMessage", entity.getStatusMessage());
        task.put("reviewStatus", entity.getReviewStatus());
        task.put("publicationStatus", entity.getPublicationStatus());
        if (StringUtils.hasText(entity.getResult())) {
            try { task.put("result", mapper.readValue(entity.getResult(), Object.class)); } catch (Exception ignored) {}
        }
        return task;
    }

    /** 将测量数据行批量写入 IGINX（用实体 + entityToPoints） */
    @SuppressWarnings("unchecked")
    private void saveMeasureDataToIginx(String workspaceId, List<Map<String, Object>> measureRows) {
        if (measureRows == null || measureRows.isEmpty()) return;
        try {
            List<Point> allPoints = new ArrayList<>();
            for (int i = 0; i < measureRows.size(); i++) {
                Map<String, Object> row = measureRows.get(i);
                long ts = i;
                WorkflowMeasureDataEntity entity = new WorkflowMeasureDataEntity();
                entity.setTimestamp(ts);
                entity.setWorkspaceId(workspaceId);
                entity.setPointId(value(row.get("point_id")));
                entity.setRowIndex(i);
                entity.setNp_mean(toDouble(row.get("Np_mean")));
                entity.setNg_mean(toDouble(row.get("Ng_mean")));
                entity.setWf_mean(toDouble(row.get("Wf_mean")));
                entity.setMkp_mean(toDouble(row.get("Mkp_mean")));
                entity.setMkg_mean(toDouble(row.get("Mkg_mean")));
                entity.setTt1_mean(toDouble(row.get("Tt1_mean")));
                entity.setPt2_mean(toDouble(row.get("Pt2_mean")));
                entity.setPt3_mean(toDouble(row.get("Pt3_mean")));
                entity.setTt3_mean(toDouble(row.get("Tt3_mean")));
                entity.setTt45_mean(toDouble(row.get("Tt45_mean")));
                entity.setPt45_mean(toDouble(row.get("Pt45_mean")));
                entity.setPamb_mean(toDouble(row.get("Pamb_mean")));
                entity.setTamb_mean(toDouble(row.get("Tamb_mean")));
                entity.setAltitude_mean(toDouble(row.get("Altitude_mean")));
                entity.setMach_mean(toDouble(row.get("Mach_mean")));
                allPoints.addAll(ConvertUtil.entityToPoints(entity, WF_MEASURE_PREFIX, ts));
            }
            iginxClient.getWriteClient().writePoints(allPoints);
            log.info("测量数据已保存到 IGINX: workspaceId={}, 行数={}", workspaceId, measureRows.size());
        } catch (Exception e) {
            log.error("保存测量数据到 IGINX 失败", e);
        }
    }

    /** 将调度变量行批量写入 IGINX（用实体 + entityToPoints） */
    @SuppressWarnings("unchecked")
    private void saveScheduleVarsToIginx(String workspaceId, List<Map<String, Object>> scheduleRows) {
        if (scheduleRows == null || scheduleRows.isEmpty()) return;
        try {
            List<Point> allPoints = new ArrayList<>();
            for (int i = 0; i < scheduleRows.size(); i++) {
                Map<String, Object> row = scheduleRows.get(i);
                long ts = i;
                WorkflowScheduleVarEntity entity = new WorkflowScheduleVarEntity();
                entity.setTimestamp(ts);
                entity.setWorkspaceId(workspaceId);
                entity.setPointId(value(row.get("point_id")));
                entity.setRowIndex(i);
                entity.setDataRole(value(row.get("dataRole")));
                entity.setTrainingGroup(value(row.get("trainingGroup")));
                entity.setAcRelativeCorrectedSpeed(toDouble(row.get("acRelativeCorrectedSpeed")));
                entity.setInletCorrectedMassFlow(toDouble(row.get("inletCorrectedMassFlow")));
                entity.setBurnerInletCorrectedMassFlow(toDouble(row.get("burnerInletCorrectedMassFlow")));
                entity.setGtTotalPressureRatio(toDouble(row.get("gtTotalPressureRatio")));
                entity.setGtPtDuctCorrectedMassFlow(toDouble(row.get("gtPtDuctCorrectedMassFlow")));
                entity.setPtTotalPressureRatio(toDouble(row.get("ptTotalPressureRatio")));
                entity.setPtNozzleDuctCorrectedMassFlow(toDouble(row.get("ptNozzleDuctCorrectedMassFlow")));
                entity.setMeasuredFuelNormalizedCoordinate(toDouble(row.get("measuredFuelNormalizedCoordinate")));
                entity.setAcCorrectedSpeedDll(toDouble(row.get("acCorrectedSpeedDll")));
                Object converged = row.get("converged");
                if (converged instanceof Boolean) entity.setConverged((Boolean) converged);
                else if (converged instanceof String) entity.setConverged(Boolean.parseBoolean((String) converged));
                entity.setMaxModelResidual(toDouble(row.get("maxModelResidual")));
                allPoints.addAll(ConvertUtil.entityToPoints(entity, WF_SCHEDULE_PREFIX, ts));
            }
            iginxClient.getWriteClient().writePoints(allPoints);
            log.info("调度变量已保存到 IGINX: workspaceId={}, 行数={}", workspaceId, scheduleRows.size());
        } catch (Exception e) {
            log.error("保存调度变量到 IGINX 失败", e);
        }
    }

    /** 从 IGINX 查询测量数据行（SQL 模式） */
    private List<Map<String, Object>> queryMeasureDataFromIginx(String workspaceId) {
        try {
            String sql = String.format("SELECT * FROM %s WHERE workspaceId = '%s' ORDER BY timestamp;",
                    WF_MEASURE_PREFIX, workspaceId);
            log.info("执行SQL: {}", sql);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            if (records == null) return new ArrayList<>();
            List<Map<String, Object>> result = new ArrayList<>();
            for (Map<String, Object> record : records) {
                WorkflowMeasureDataEntity entity = iginxRecordToMeasureEntity(record);
                result.add(measureEntityToMap(entity));
            }
            return result;
        } catch (Exception e) {
            log.error("从 IGINX 查询测量数据失败: workspaceId={}", workspaceId, e);
            return new ArrayList<>();
        }
    }

    /** 从 IGINX 查询调度变量行（SQL 模式） */
    private List<Map<String, Object>> queryScheduleVarsFromIginx(String workspaceId) {
        try {
            String sql = String.format("SELECT * FROM %s WHERE workspaceId = '%s' ORDER BY timestamp;",
                    WF_SCHEDULE_PREFIX, workspaceId);
            log.info("执行SQL: {}", sql);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            if (records == null) return new ArrayList<>();
            List<Map<String, Object>> result = new ArrayList<>();
            for (Map<String, Object> record : records) {
                WorkflowScheduleVarEntity entity = iginxRecordToScheduleEntity(record);
                result.add(scheduleEntityToMap(entity));
            }
            return result;
        } catch (Exception e) {
            log.error("从 IGINX 查询调度变量失败: workspaceId={}", workspaceId, e);
            return new ArrayList<>();
        }
    }

    /** 将 IGINX 记录转换为测量数据实体 */
    private WorkflowMeasureDataEntity iginxRecordToMeasureEntity(Map<String, Object> record) {
        WorkflowMeasureDataEntity entity = new WorkflowMeasureDataEntity();
        for (Map.Entry<String, Object> entry : record.entrySet()) {
            String fieldName = entry.getKey().substring(entry.getKey().lastIndexOf('.') + 1);
            Object value = entry.getValue();
            if (value instanceof byte[]) value = ConvertUtil.bytesToString((byte[]) value);
            switch (fieldName) {
                case "timestamp": entity.setTimestamp(value instanceof Number ? ((Number) value).longValue() : null); break;
                case "workspaceId": entity.setWorkspaceId(String.valueOf(value)); break;
                case "pointId": entity.setPointId(String.valueOf(value)); break;
                case "rowIndex": entity.setRowIndex(value instanceof Number ? ((Number) value).intValue() : null); break;
                case "Np_mean": entity.setNp_mean(toDouble(value)); break;
                case "Ng_mean": entity.setNg_mean(toDouble(value)); break;
                case "Wf_mean": entity.setWf_mean(toDouble(value)); break;
                case "Mkp_mean": entity.setMkp_mean(toDouble(value)); break;
                case "Mkg_mean": entity.setMkg_mean(toDouble(value)); break;
                case "Tt1_mean": entity.setTt1_mean(toDouble(value)); break;
                case "Pt2_mean": entity.setPt2_mean(toDouble(value)); break;
                case "Pt3_mean": entity.setPt3_mean(toDouble(value)); break;
                case "Tt3_mean": entity.setTt3_mean(toDouble(value)); break;
                case "Tt45_mean": entity.setTt45_mean(toDouble(value)); break;
                case "Pt45_mean": entity.setPt45_mean(toDouble(value)); break;
                case "Pamb_mean": entity.setPamb_mean(toDouble(value)); break;
                case "Tamb_mean": entity.setTamb_mean(toDouble(value)); break;
                case "Altitude_mean": entity.setAltitude_mean(toDouble(value)); break;
                case "Mach_mean": entity.setMach_mean(toDouble(value)); break;
            }
        }
        return entity;
    }

    /** 将 IGINX 记录转换为调度变量实体 */
    private WorkflowScheduleVarEntity iginxRecordToScheduleEntity(Map<String, Object> record) {
        WorkflowScheduleVarEntity entity = new WorkflowScheduleVarEntity();
        for (Map.Entry<String, Object> entry : record.entrySet()) {
            String fieldName = entry.getKey().substring(entry.getKey().lastIndexOf('.') + 1);
            Object value = entry.getValue();
            if (value instanceof byte[]) value = ConvertUtil.bytesToString((byte[]) value);
            switch (fieldName) {
                case "timestamp": entity.setTimestamp(value instanceof Number ? ((Number) value).longValue() : null); break;
                case "workspaceId": entity.setWorkspaceId(String.valueOf(value)); break;
                case "pointId": entity.setPointId(String.valueOf(value)); break;
                case "rowIndex": entity.setRowIndex(value instanceof Number ? ((Number) value).intValue() : null); break;
                case "dataRole": entity.setDataRole(String.valueOf(value)); break;
                case "trainingGroup": entity.setTrainingGroup(String.valueOf(value)); break;
                case "acRelativeCorrectedSpeed": entity.setAcRelativeCorrectedSpeed(toDouble(value)); break;
                case "inletCorrectedMassFlow": entity.setInletCorrectedMassFlow(toDouble(value)); break;
                case "burnerInletCorrectedMassFlow": entity.setBurnerInletCorrectedMassFlow(toDouble(value)); break;
                case "gtTotalPressureRatio": entity.setGtTotalPressureRatio(toDouble(value)); break;
                case "gtPtDuctCorrectedMassFlow": entity.setGtPtDuctCorrectedMassFlow(toDouble(value)); break;
                case "ptTotalPressureRatio": entity.setPtTotalPressureRatio(toDouble(value)); break;
                case "ptNozzleDuctCorrectedMassFlow": entity.setPtNozzleDuctCorrectedMassFlow(toDouble(value)); break;
                case "measuredFuelNormalizedCoordinate": entity.setMeasuredFuelNormalizedCoordinate(toDouble(value)); break;
                case "acCorrectedSpeedDll": entity.setAcCorrectedSpeedDll(toDouble(value)); break;
                case "converged": entity.setConverged(value instanceof Boolean ? (Boolean) value : Boolean.parseBoolean(String.valueOf(value))); break;
                case "maxModelResidual": entity.setMaxModelResidual(toDouble(value)); break;
            }
        }
        return entity;
    }

    /** 测量数据实体转 Map */
    private Map<String, Object> measureEntityToMap(WorkflowMeasureDataEntity e) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("point_id", e.getPointId());
        m.put("rowIndex", e.getRowIndex());
        m.put("Np_mean", e.getNp_mean());
        m.put("Ng_mean", e.getNg_mean());
        m.put("Wf_mean", e.getWf_mean());
        m.put("Mkp_mean", e.getMkp_mean());
        m.put("Mkg_mean", e.getMkg_mean());
        m.put("Tt1_mean", e.getTt1_mean());
        m.put("Pt2_mean", e.getPt2_mean());
        m.put("Pt3_mean", e.getPt3_mean());
        m.put("Tt3_mean", e.getTt3_mean());
        m.put("Tt45_mean", e.getTt45_mean());
        m.put("Pt45_mean", e.getPt45_mean());
        m.put("Pamb_mean", e.getPamb_mean());
        m.put("Tamb_mean", e.getTamb_mean());
        m.put("Altitude_mean", e.getAltitude_mean());
        m.put("Mach_mean", e.getMach_mean());
        return m;
    }

    /** 调度变量实体转 Map */
    private Map<String, Object> scheduleEntityToMap(WorkflowScheduleVarEntity e) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("point_id", e.getPointId());
        m.put("rowIndex", e.getRowIndex());
        m.put("dataRole", e.getDataRole());
        m.put("trainingGroup", e.getTrainingGroup());
        m.put("acRelativeCorrectedSpeed", e.getAcRelativeCorrectedSpeed());
        m.put("inletCorrectedMassFlow", e.getInletCorrectedMassFlow());
        m.put("burnerInletCorrectedMassFlow", e.getBurnerInletCorrectedMassFlow());
        m.put("gtTotalPressureRatio", e.getGtTotalPressureRatio());
        m.put("gtPtDuctCorrectedMassFlow", e.getGtPtDuctCorrectedMassFlow());
        m.put("ptTotalPressureRatio", e.getPtTotalPressureRatio());
        m.put("ptNozzleDuctCorrectedMassFlow", e.getPtNozzleDuctCorrectedMassFlow());
        m.put("measuredFuelNormalizedCoordinate", e.getMeasuredFuelNormalizedCoordinate());
        m.put("acCorrectedSpeedDll", e.getAcCorrectedSpeedDll());
        m.put("converged", e.getConverged());
        m.put("maxModelResidual", e.getMaxModelResidual());
        return m;
    }

    /** 安全转换为 Double */
    private Double toDouble(Object value) {
        if (value == null) return null;
        if (value instanceof Number) return ((Number) value).doubleValue();
        String str = value instanceof byte[] ? ConvertUtil.bytesToString((byte[]) value) : String.valueOf(value);
        if ("—".equals(str) || "NaN".equalsIgnoreCase(str) || str.isEmpty()) return null;
        try {
            return Double.parseDouble(str);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /** 删除工作区在 IGINX 中的所有数据 */
    private void deleteWorkspaceFromIginx(String workspaceId, long workspaceTimestamp) {
        try {
            // 删除工作区元数据
            List<String> wsMeasurements = ConvertUtil.iginxFieldNamesConvert(WorkflowWorkspaceEntity.class, WF_WORKSPACE_PREFIX);
            iginxClient.getDeleteClient().deleteMeasurementsData(wsMeasurements, workspaceTimestamp - 1, workspaceTimestamp + 1);
            // 删除该工作区的所有任务
            deleteRowsByWorkspaceId(WF_TASK_PREFIX, WorkflowTaskEntity.class, workspaceId);
            // 删除测量数据和调度变量
            deleteRowsByWorkspaceId(WF_MEASURE_PREFIX, WorkflowMeasureDataEntity.class, workspaceId);
            deleteRowsByWorkspaceId(WF_SCHEDULE_PREFIX, WorkflowScheduleVarEntity.class, workspaceId);
            log.info("工作区 IGINX 数据已删除: workspaceId={}", workspaceId);
        } catch (Exception e) {
            log.error("删除工作区 IGINX 数据失败: workspaceId={}", workspaceId, e);
        }
    }

    /** 按 workspaceId 删除某张表的所有行 */
    private void deleteRowsByWorkspaceId(String prefix, Class<?> entityClass, String workspaceId) {
        try {
            String sql = String.format("SELECT timestamp FROM %s WHERE workspaceId = '%s';", prefix, workspaceId);
            SessionExecuteSqlResult res = iginxSession.executeSql(sql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            if (records == null || records.isEmpty()) return;
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(entityClass, prefix);
            for (Map<String, Object> r : records) {
                Object tsObj = r.values().iterator().next();
                if (tsObj instanceof Number) {
                    long ts = ((Number) tsObj).longValue();
                    iginxClient.getDeleteClient().deleteMeasurementsData(measurements, ts - 1, ts + 1);
                }
            }
        } catch (Exception e) {
            log.error("按 workspaceId 删除行失败: prefix={}, workspaceId={}", prefix, workspaceId, e);
        }
    }
}
