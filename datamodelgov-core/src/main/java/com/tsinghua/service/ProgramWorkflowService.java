package com.tsinghua.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.ProgramEntity;
import com.tsinghua.matlab.MatlabFunctionRunner;
import com.tsinghua.program.config.ProgramConfig;
import com.tsinghua.program.config.ProgramConfigMapper;
import com.tsinghua.util.ArchiveUtil;
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
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;
import java.util.stream.Stream;

/** Minimal persistent backend for config-driven MATLAB workflows. */
@Slf4j
@Service
public class ProgramWorkflowService {

    private static final Pattern SAFE_ID = Pattern.compile("^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$");
    private static final Pattern SAFE_KEY = Pattern.compile("^[A-Za-z][A-Za-z0-9_-]*$");
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
    private final Map<String, Object> fileLocks = new ConcurrentHashMap<>();
    private final Map<String, Object> workspaceExecutionLocks = new ConcurrentHashMap<>();

    @Autowired
    private ProgramService programService;

    @PostConstruct
    public void recoverInterruptedTasks() {
        Path root = new File("project").toPath();
        if (!Files.isDirectory(root)) return;
        try (Stream<Path> files = Files.walk(root)) {
            for (Path file : (Iterable<Path>) files::iterator) {
                if (!"task.json".equals(file.getFileName().toString()) || !Files.isRegularFile(file)
                        || !file.toString().contains("program-workflows")) continue;
                try {
                    Map<String, Object> task = readMap(file);
                    String status = value(task.get("status"));
                    if ("QUEUED".equals(status) || "RUNNING".equals(status) || "CANCEL_REQUESTED".equals(status)) {
                        updateTask(file, "FAILED", "服务重启导致任务中断", null, true);
                    }
                } catch (Exception e) {
                    log.warn("恢复工作流任务状态失败: {}", file, e);
                }
            }
        } catch (IOException e) {
            log.warn("扫描历史工作流任务失败", e);
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
                                                 String jobName, String trainingDataFile, String testDataFile) throws Exception {
        requireSafeQueryValue(name, "name");
        requireSafeQueryValue(version, "version");
        String project = effectiveProject(projectName);
        ProgramEntity entity = requireWorkflowProgram(name, version, project);
        ProgramConfig config = parseWorkflowConfig(entity);

        String id = safeJobName(jobName);
        Path root = workflowRoot(project);
        Path workspace = child(root, id);
        if (Files.isDirectory(workspace)) {
            throw new IllegalArgumentException("项目名称已存在: " + jobName + "，请使用其他名称");
        }
        Path source = child(workspace, "source");
        Path datasets = child(workspace, "datasets");
        Path tasks = child(workspace, "tasks");
        Path output = child(workspace, "output");
        Files.createDirectories(source);
        Files.createDirectories(datasets);
        Files.createDirectories(tasks);
        Files.createDirectories(output);

        String archiveName = safeFileName(entity.getFileName(), "program.zip");
        if (!ArchiveUtil.isSupportedArchive(archiveName)) {
            throw new IllegalArgumentException("Program archive has an unsupported file extension");
        }
        Path archive = child(workspace, archiveName);
        Files.write(archive, programService.downloadProgram(name, version, project));
        try {
            ArchiveUtil.extractArchive(archive.toFile(), source.toFile());
        } finally {
            Files.deleteIfExists(archive);
        }

        String configuredWorkingDirectory = config.getRuntime().getWorkingDirectory().trim();
        Path workingDirectory = resolveInside(source, configuredWorkingDirectory, true);
        if (!Files.isDirectory(workingDirectory)) {
            throw new IllegalArgumentException("runtime.workingDirectory does not exist in the program archive");
        }
        validateWorkflowFiles(workingDirectory, config);
        installWorkflowAdapter(workingDirectory);

        // 从程序包的 TestData 目录复制用户选中的数据文件到 workspace/datasets
        Path testDataDir = child(workingDirectory, "TestData");
        List<Map<String, Object>> uploadedDatasets = new ArrayList<>();

        if (StringUtils.hasText(trainingDataFile)) {
            Path src = child(testDataDir, safeFileName(trainingDataFile, "training.xlsx"));
            if (!Files.isRegularFile(src)) {
                throw new IllegalArgumentException("训练数据文件不存在于程序包: " + trainingDataFile);
            }
            String storedName = "trainingData-" + safeFileName(trainingDataFile, "training.xlsx");
            Path dest = child(datasets, storedName);
            Files.copy(src, dest, StandardCopyOption.REPLACE_EXISTING);
            Map<String, Object> dsRecord = new LinkedHashMap<>();
            dsRecord.put("datasetKey", "trainingData");
            dsRecord.put("fileName", trainingDataFile);
            dsRecord.put("storedName", storedName);
            dsRecord.put("size", Files.size(dest));
            dsRecord.put("sha256", sha256(dest));
            dsRecord.put("uploadedAt", System.currentTimeMillis());
            uploadedDatasets.add(dsRecord);
        } else {
            throw new IllegalArgumentException("请选择训练数据文件");
        }

        if (StringUtils.hasText(testDataFile)) {
            Path src = child(testDataDir, safeFileName(testDataFile, "test.xlsx"));
            if (!Files.isRegularFile(src)) {
                throw new IllegalArgumentException("测试数据文件不存在于程序包: " + testDataFile);
            }
            String storedName = "testData-" + safeFileName(testDataFile, "test.xlsx");
            Path dest = child(datasets, storedName);
            Files.copy(src, dest, StandardCopyOption.REPLACE_EXISTING);
            Map<String, Object> dsRecord = new LinkedHashMap<>();
            dsRecord.put("datasetKey", "testData");
            dsRecord.put("fileName", testDataFile);
            dsRecord.put("storedName", storedName);
            dsRecord.put("size", Files.size(dest));
            dsRecord.put("sha256", sha256(dest));
            dsRecord.put("uploadedAt", System.currentTimeMillis());
            uploadedDatasets.add(dsRecord);
        }

        // 校验训练数据合同
        Path trainingPath = child(datasets, uploadedDatasets.stream()
                .filter(d -> "trainingData".equals(d.get("datasetKey")))
                .findFirst().map(d -> String.valueOf(d.get("storedName"))).orElse(""));
        Map<String, Object> dataContract = validateDataContract(trainingPath);
        if (!Boolean.TRUE.equals(dataContract.get("valid"))) {
            throw new IllegalArgumentException("训练数据合同校验失败: 缺少字段 " +
                    String.join(", ", (List<String>) dataContract.get("missingColumns")));
        }

        // MATLAB 初始化与零修正回放：计算全部调度变量
        Map<String, Object> initResult = runMatlabInit(workingDirectory, trainingDataFile, workspace);

        long now = System.currentTimeMillis();
        Map<String, Object> record = new LinkedHashMap<>();
        record.put("id", id);
        record.put("programName", name);
        record.put("programVersion", version);
        record.put("projectName", project);
        record.put("jobName", jobName != null ? jobName : "");
        record.put("trainingDataFile", trainingDataFile);
        record.put("testDataFile", testDataFile != null ? testDataFile : "");
        record.put("status", "READY");
        record.put("workingDirectory", source.relativize(workingDirectory).toString().replace(File.separatorChar, '/'));
        String configJson = ProgramConfigMapper.stringify(config);
        record.put("programFileMd5", entity.getFileMd5());
        record.put("configSha256", sha256Text(configJson));
        record.put("requiredFileHashes", requiredFileHashes(workingDirectory, config));
        record.put("createdAt", now);
        record.put("updatedAt", now);
        record.put("datasets", datasetSpecs(config));
        record.put("actions", actionSpecs(config));
        record.put("dataContract", dataContract);
        record.put("initResult", initResult);
        writeJson(child(workspace, "workspace.json"), record);
        Files.write(child(workspace, "program-config.json"), configJson.getBytes(StandardCharsets.UTF_8));
        writeJson(child(workspace, "datasets.json"), uploadedDatasets);
        record.put("uploadedDatasets", uploadedDatasets);
        return record;
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
        Path root = workflowRoot(project);
        if (!Files.isDirectory(root)) return Collections.emptyList();
        List<Map<String, Object>> result = new ArrayList<>();
        try (Stream<Path> paths = Files.list(root)) {
            for (Path path : (Iterable<Path>) paths::iterator) {
                if (!Files.isDirectory(path) || !SAFE_WORKSPACE_DIR.matcher(path.getFileName().toString()).matches()) continue;
                Path manifest = child(path, "workspace.json");
                if (!Files.isRegularFile(manifest)) continue;
                Map<String, Object> workspace = readMap(manifest);
                if (matchesProgram(workspace, name, version, project)) result.add(workspace);
            }
        }
        result.sort((a, b) -> Long.compare(longValue(b.get("createdAt")), longValue(a.get("createdAt"))));
        return result;
    }

    public Map<String, Object> getWorkspace(String id, String name, String version, String projectName) throws Exception {
        Path workspace = requireWorkspace(id, name, version, projectName);
        Map<String, Object> record = readMap(child(workspace, "workspace.json"));
        record.put("uploadedDatasets", readListOfMaps(child(workspace, "datasets.json")));
        return record;
    }

    public void deleteWorkspace(String id, String name, String version, String projectName) throws Exception {
        Path workspace = requireWorkspace(id, name, version, projectName);
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

        Path index = child(workspace, "datasets.json");
        synchronized (lock(index)) {
            List<Map<String, Object>> records = readListOfMaps(index);
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
            writeJson(index, records);
            return publicDataset(record);
        }
    }

    public List<Map<String, Object>> listDatasets(String workspaceId, String name, String version,
                                                   String projectName) throws Exception {
        Path workspace = requireWorkspace(workspaceId, name, version, projectName);
        List<Map<String, Object>> records = readListOfMaps(child(workspace, "datasets.json"));
        List<Map<String, Object>> result = new ArrayList<>();
        for (Map<String, Object> record : records) result.add(publicDataset(record));
        return result;
    }

    public Map<String, Object> createTask(JsonNode request, String name, String version, String projectName) throws Exception {
        if (request == null || !request.isObject()) throw new IllegalArgumentException("Task request must be a JSON object");
        String workspaceId = text(request, "workspaceId");
        String actionKey = text(request, "actionKey");
        Path workspace = requireWorkspace(workspaceId, name, version, projectName);
        ProgramConfig config = configForWorkspace(workspace);
        ProgramConfig.WorkflowAction action = findAction(config, actionKey);
        if (action == null) throw new IllegalArgumentException("actionKey is not declared by the program config");

        Object[] arguments = resolveArguments(workspace, config, action, request.get("inputs"));
        String taskId = UUID.randomUUID().toString();
        Path taskDir = child(child(workspace, "tasks"), taskId);
        Files.createDirectories(taskDir);
        Map<String, Object> task = new LinkedHashMap<>();
        task.put("id", taskId);
        task.put("workspaceId", workspaceId);
        task.put("actionKey", action.getKey());
        task.put("entryPoint", action.getEntryPoint());
        task.put("stage", action.getStage());
        task.put("resultType", action.getResultType());
        task.put("status", "QUEUED");
        task.put("createdAt", System.currentTimeMillis());
        task.put("cancelRequested", false);
        task.put("logPath", "tasks/" + taskId + "/run.log");
        writeJson(child(taskDir, "task.json"), task);
        executor.submit(() -> {
            Object executionLock = workspaceExecutionLocks.computeIfAbsent(workspace.toString(), key -> new Object());
            synchronized (executionLock) {
                runTask(workspace, taskDir, task, action, arguments);
            }
        });
        return task;
    }

    public List<Map<String, Object>> listTasks(String workspaceId, String name, String version,
                                               String projectName) throws Exception {
        Path workspace = requireWorkspace(workspaceId, name, version, projectName);
        Path tasks = child(workspace, "tasks");
        List<Map<String, Object>> result = new ArrayList<>();
        if (!Files.isDirectory(tasks)) return result;
        try (Stream<Path> paths = Files.list(tasks)) {
            for (Path task : (Iterable<Path>) paths::iterator) {
                if (!Files.isDirectory(task) || !SAFE_ID.matcher(task.getFileName().toString()).matches()) continue;
                Path manifest = child(task, "task.json");
                if (Files.isRegularFile(manifest)) result.add(readMap(manifest));
            }
        }
        result.sort((a, b) -> Long.compare(longValue(b.get("createdAt")), longValue(a.get("createdAt"))));
        return result;
    }

    public Map<String, Object> getTask(String taskId, String name, String version, String projectName) throws Exception {
        Path task = requireTask(taskId, name, version, projectName);
        return readMap(child(task, "task.json"));
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
        Path manifest = child(taskDir, "task.json");
        Map<String, Object> task;
        synchronized (lock(manifest)) {
            task = readMap(manifest);
            String status = value(task.get("status"));
            if (!isTerminal(status)) {
                task.put("cancelRequested", true);
                task.put("status", "CANCEL_REQUESTED");
                task.put("updatedAt", System.currentTimeMillis());
                writeJson(manifest, task);
            }
        }
        Files.write(child(taskDir, "cancel.flag"), new byte[]{1});
        MatlabFunctionRunner runner = running.get(taskId);
        if (runner != null) runner.requestCancel();
        return task;
    }

    public Map<String, Object> getResult(String taskId, String name, String version, String projectName) throws Exception {
        Path task = requireTask(taskId, name, version, projectName);
        Path result = child(task, "result.json");
        if (!Files.isRegularFile(result)) throw new IllegalStateException("Task result is not available");
        return readMap(result);
    }

    public Map<String, Object> reviewResult(String taskId, JsonNode request, String name, String version,
                                            String projectName) throws Exception {
        Path taskDir = requireTask(taskId, name, version, projectName);
        Path manifest = child(taskDir, "task.json");
        String decision = request == null ? "" : text(request, "decision").toUpperCase(Locale.ROOT);
        if (!"APPROVED".equals(decision) && !"REJECTED".equals(decision)) {
            throw new IllegalArgumentException("decision must be APPROVED or REJECTED");
        }
        synchronized (lock(manifest)) {
            Map<String, Object> task = readMap(manifest);
            if (!"SUCCEEDED".equals(task.get("status"))) throw new IllegalStateException("Only successful results can be reviewed");
            String notes = request == null ? "" : text(request, "notes");
            if (notes.length() > 2000) throw new IllegalArgumentException("Review notes are too long");
            task.put("reviewStatus", decision);
            task.put("reviewNotes", notes);
            task.put("reviewedBy", AuthUtil.getCurrentUsername());
            task.put("reviewedAt", System.currentTimeMillis());
            writeJson(manifest, task);
            return task;
        }
    }

    public Map<String, Object> publishResult(String taskId, String name, String version,
                                             String projectName) throws Exception {
        Path taskDir = requireTask(taskId, name, version, projectName);
        Path manifest = child(taskDir, "task.json");
        synchronized (lock(manifest)) {
            Map<String, Object> task = readMap(manifest);
            if (!"SUCCEEDED".equals(task.get("status"))) throw new IllegalStateException("Only successful results can be published");
            if (!"APPROVED".equals(task.get("reviewStatus"))) throw new IllegalStateException("Result must be approved before publication");
            if (!"estimation".equals(task.get("resultType"))) throw new IllegalStateException("Only identified model results can be published");
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
            Path workspace = taskDir.getParent().getParent();
            Map<String, Object> publication = new LinkedHashMap<>();
            publication.put("taskId", taskId);
            publication.put("actionKey", task.get("actionKey"));
            publication.put("publishedBy", AuthUtil.getCurrentUsername());
            publication.put("publishedAt", System.currentTimeMillis());
            publication.put("status", "PUBLISHED");
            synchronized (lock(child(workspace, "published-model.json"))) {
                writeJson(child(workspace, "published-model.json"), publication);
            }
            task.put("publicationStatus", "PUBLISHED");
            task.put("publishedBy", publication.get("publishedBy"));
            task.put("publishedAt", publication.get("publishedAt"));
            writeJson(manifest, task);
            return publication;
        }
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
        MatlabFunctionRunner runner = null;
        Map<String, Stamp> before = Collections.emptyMap();
        try {
            before = snapshotArtifacts(workspace);
            updateTask(manifest, "RUNNING", null, System.currentTimeMillis(), false);
            Path workingDirectory = resolveInside(workspace.resolve("source"),
                    value(readMap(workspace.resolve("workspace.json")).get("workingDirectory")), true);
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
            runner = new MatlabFunctionRunner(workingDirectory.toFile(), "dmg_run_workflow", adapterArguments,
                    taskDir.resolve("run.log").toFile(), programService.enginePool(), new MatlabFunctionRunner.ProgressCancellationSink() {
                private long lastUpdate;
                @Override public void onProgress(String message) {
                    long now = System.currentTimeMillis();
                    if (!message.startsWith("[stdout]") || now - lastUpdate >= 1000L) {
                        lastUpdate = now;
                        updateTaskMessage(manifest, message);
                    }
                }
                @Override public boolean isCancellationRequested() {
                    try { return Boolean.TRUE.equals(readMap(manifest).get("cancelRequested")); }
                    catch (Exception e) { return false; }
                }
            });
            running.put(taskId, runner);
            if (Boolean.TRUE.equals(readMap(manifest).get("cancelRequested"))) runner.requestCancel();
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
            updateTask(manifest, "SUCCEEDED", null, null, true);
        } catch (CancellationException e) {
            finishArtifactsQuietly(workspace, taskDir, before);
            updateTaskQuietly(manifest, "CANCELLED", e.getMessage());
        } catch (Exception e) {
            finishArtifactsQuietly(workspace, taskDir, before);
            try {
                if (Boolean.TRUE.equals(readMap(manifest).get("cancelRequested"))) {
                    updateTaskQuietly(manifest, "CANCELLED", "任务已在当前MATLAB安全点取消");
                } else {
                    log.error("MATLAB workflow task {} failed", taskId, e);
                    updateTaskQuietly(manifest, "FAILED", safeError(e));
                }
            } catch (Exception statusError) {
                log.error("MATLAB workflow task {} failed", taskId, e);
                updateTaskQuietly(manifest, "FAILED", safeError(e));
            }
        } finally {
            running.remove(taskId);
        }
    }

    private Object[] resolveArguments(Path workspace, ProgramConfig config, ProgramConfig.WorkflowAction action,
                                      JsonNode inputs) throws Exception {
        List<String> ordered = action.getInputs() == null ? Collections.emptyList() : action.getInputs();
        List<Map<String, Object>> uploaded = readListOfMaps(child(workspace, "datasets.json"));
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
        Path manifest = child(workspace, "workspace.json");
        if (!Files.isRegularFile(manifest)) throw new IllegalArgumentException("Workspace does not exist");
        if (!matchesProgram(readMap(manifest), name, version, project)) throw new SecurityException("Workspace does not belong to this program context");
        return workspace;
    }

    private Path requireTask(String taskId, String name, String version, String projectName) throws Exception {
        requireId(taskId, "taskId");
        String project = effectiveProject(projectName);
        Path root = workflowRoot(project);
        if (!Files.isDirectory(root)) throw new IllegalArgumentException("Task does not exist");
        try (Stream<Path> workspaces = Files.list(root)) {
            for (Path workspace : (Iterable<Path>) workspaces::iterator) {
                if (!Files.isDirectory(workspace) || !SAFE_WORKSPACE_DIR.matcher(workspace.getFileName().toString()).matches()) continue;
                Path workspaceManifest = child(workspace, "workspace.json");
                if (!Files.isRegularFile(workspaceManifest) || !matchesProgram(readMap(workspaceManifest), name, version, project)) continue;
                Path task = child(child(workspace, "tasks"), taskId);
                if (Files.isRegularFile(child(task, "task.json"))) return task;
            }
        }
        throw new IllegalArgumentException("Task does not exist");
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

    private void updateTask(Path manifest, String status, String error, Long startedAt, boolean completed) throws IOException {
        synchronized (lock(manifest)) {
            Map<String, Object> task = readMap(manifest);
            task.put("status", status);
            task.put("updatedAt", System.currentTimeMillis());
            if (startedAt != null) task.put("startedAt", startedAt);
            if (completed || isTerminal(status)) task.put("completedAt", System.currentTimeMillis());
            if (error != null) task.put("error", error);
            writeJson(manifest, task);
        }
    }

    private void updateTaskMessage(Path manifest, String message) {
        try {
            synchronized (lock(manifest)) {
                Map<String, Object> task = readMap(manifest);
                task.put("statusMessage", message);
                task.put("updatedAt", System.currentTimeMillis());
                writeJson(manifest, task);
            }
        } catch (Exception e) {
            log.debug("Could not persist workflow progress: {}", e.getMessage());
        }
    }

    private void updateTaskQuietly(Path manifest, String status, String error) {
        try { updateTask(manifest, status, error, null, true); }
        catch (Exception e) { log.error("Could not persist workflow task status", e); }
    }

    private boolean isTerminal(String status) {
        return "SUCCEEDED".equals(status) || "FAILED".equals(status) || "CANCELLED".equals(status);
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
}
