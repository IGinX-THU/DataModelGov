package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXHeader;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.alibaba.fastjson2.JSONArray;
import com.tsinghua.dto.DataQueryRequest;
import com.tsinghua.dto.InputBindDto;
import com.tsinghua.dto.OutputBindDto;
import com.tsinghua.dto.RunTaskQueryRequest;
import com.tsinghua.dto.RunTaskRequest;
import com.tsinghua.entity.AssociationRulesEntity;
import com.tsinghua.entity.ModelMetaEntity;
import com.tsinghua.entity.RunTaskEntity;
import com.tsinghua.enums.TaskStatus;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import org.xhtmlrenderer.pdf.ITextRenderer;

import java.io.*;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.stream.Collectors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

@Slf4j
@Service
public class RunTaskService {

    private static final String DATA_PREFIX = "relational_system.association_job";

    @Autowired
    private Session iginxSession;

    @Lazy
    @Autowired
    private AssociationRulesService associationRulesService;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private ModelFileService modelFileService;

    @Autowired
    private DataTableService dataTableService;

    /**
     * 分页查询运行任务
     */
    public List<RunTaskEntity> queryTasks(RunTaskQueryRequest request) {
        try {
            // 构建基础SQL
            StringBuilder sql = new StringBuilder("SELECT * FROM relational_system.association_job WHERE 1=1");
            
            // 添加筛选条件
            if (request.getName() != null && !request.getName().trim().isEmpty()) {
                sql.append(" AND name LIKE '^.*").append(request.getName().trim()).append(".*'");
            }
            if (request.getStatus() != null && !request.getStatus().trim().isEmpty()) {
                sql.append(" AND status = '").append(request.getStatus().trim()).append("'");
            }
            if (request.getRuleId() != null) {
                sql.append(" AND ruleId = ").append(request.getRuleId());
            }
            if (request.getStartTime() != null) {
                sql.append(" AND timestamp >= ").append(request.getStartTime());
            }
            if (request.getEndTime() != null) {
                sql.append(" AND timestamp <= ").append(request.getEndTime());
            }
            
            // 添加排序和分页
            sql.append(" ORDER BY timestamp DESC");
            sql.append(" LIMIT ").append(request.getPageSize());
            sql.append(" OFFSET ").append((request.getPageNum() - 1) * request.getPageSize());
            sql.append(";");
            
            log.info("执行SQL: {}", sql);
            
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            
            // 转换为RunTaskEntity列表
            List<RunTaskEntity> result = records.stream().map(record -> {
                RunTaskEntity entity = new RunTaskEntity();
                record.forEach((k, v) -> {
                    String fieldName = k.replace(DATA_PREFIX + ".", "");
                    ConvertUtil.setEntityField(entity, DATA_PREFIX, fieldName, v);
                });
                return entity;
            }).collect(Collectors.toList());
            
            log.info("查询结果: records={}", result.size());
            return result;
        } catch (Exception e) {
            log.error("查询失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 查询运行任务总数
     */
    public Object countTasks(RunTaskQueryRequest request) {
        try {
            // 构建COUNT查询SQL
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM relational_system.association_job WHERE 1=1");
            
            // 添加筛选条件
            if (request.getName() != null && !request.getName().trim().isEmpty()) {
                sql.append(" AND name LIKE '%").append(request.getName().trim()).append("%'");
            }
            if (request.getStatus() != null && !request.getStatus().trim().isEmpty()) {
                sql.append(" AND status = '").append(request.getStatus().trim()).append("'");
            }
            if (request.getRuleId() != null) {
                sql.append(" AND ruleId = ").append(request.getRuleId());
            }
            if (request.getStartTime() != null) {
                sql.append(" AND timestamp >= ").append(request.getStartTime());
            }
            if (request.getEndTime() != null) {
                sql.append(" AND timestamp <= ").append(request.getEndTime());
            }
            sql.append(";");
            
            log.info("执行COUNT SQL: {}", sql);
            
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            
            return res.getValues().get(0).get(0);
        } catch (Exception e) {
            log.error("查询失败", e);
            return 0;
        }
    }

    /**
     * 查询运行任务详情
     * 参考queryMeta逻辑，只用timestamp作为唯一标识
     */
    public RunTaskEntity queryTask(Long timestamp) {
        try {
            String sql = "select * from %s where timestamp = %s;";
            String metaBasePath = DATA_PREFIX;
            SessionExecuteSqlResult res = iginxSession.executeSql(String.format(sql, metaBasePath, timestamp));
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            if (records.isEmpty()) {
                return null;
            }

            RunTaskEntity entity = new RunTaskEntity();
            Map<String, Object> rs = records.get(0);
            // 使用ConvertUtil的通用方法设置字段值
            rs.forEach((k, v) -> {
                String fieldName = k.replace(DATA_PREFIX + ".", "");
                ConvertUtil.setEntityField(entity, DATA_PREFIX, fieldName, v);
            });
            return entity;
        } catch (Exception e) {
            log.error("查询运行任务失败", e);
            return null;
        }
    }

    /**
     * 删除运行任务
     * 参考deleteModel逻辑，只用timestamp作为唯一标识
     */
    public void deleteTask(Long timestamp) {
        try {
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(RunTaskEntity.class, DATA_PREFIX);
            // 删除指定时间戳的数据
            iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp - 1, timestamp + 1);
            log.info("已删除运行任务: timestamp: {}", timestamp);
        } catch (Exception e) {
            log.error("删除运行任务失败", e);
            throw new RuntimeException("删除运行任务失败: " + e.getMessage(), e);
        }
    }


    /**
     * 校验任务的唯一性
     * 防止完全相同的任务重复提交
     */
    public boolean validateTaskUniqueness(RunTaskRequest request) {
        try {
            // 构建查询SQL：检查是否存在完全相同的任务
            String sql = String.format(
                "SELECT COUNT(1) FROM %s WHERE ruleId = %d AND startTime = %d AND endTime = %d OR name = '%s';",
                DATA_PREFIX,
                request.getRuleId(),
                request.getStartTime(),
                request.getEndTime(),
                request.getName()
            );
            
            log.info("执行唯一性校验SQL: {}", sql);
            
            SessionExecuteSqlResult result = iginxSession.executeSql(sql);
            
            List<List<Object>> data = result.getValues();
            if (!data.isEmpty() && !data.get(0).isEmpty()) {
                Object countObj = data.get(0).get(0);
                if (countObj instanceof Number) {
                    int count = ((Number) countObj).intValue();
                    return count == 0;
                }
            }
            return true; // 如果查询失败，默认允许通过
        } catch (Exception e) {
            log.error("校验任务唯一性失败", e);
            return true; // 查询失败时默认允许通过
        }
    }

    /**
     * 停止运行中的任务
     * 执行kill命令强制销毁对应的进程
     */
    public void stopTask(Long timestamp) throws Exception {
        try {
            // 1. 查询任务信息
            RunTaskEntity task = queryTask(timestamp);
            if (task == null) {
                throw new RuntimeException("未找到指定的任务: " + timestamp);
            }
            
            // 2. 检查任务状态
            if (task.getStatus() != TaskStatus.RUNNING) {
                // 如果任务不在运行状态，直接标记为已停止
                log.info("任务不在运行状态，直接标记为已停止: {}", task.getStatus());
                task.setStatus(TaskStatus.STOPPED);
                saveTask(task);
                log.info("任务 {} 已标记为已停止", timestamp);
                return;
            }
            
            // 3. 检查是否有保存的进程ID
            if (task.getProcessId() == null || task.getProcessId() == 0) {
                throw new RuntimeException("任务没有保存的进程ID，无法精确停止");
            }
            
            long processId = task.getProcessId();
            log.info("开始停止任务: timestamp={}, name={}, processId={}", 
                    timestamp, task.getName(), processId);
            
            // 4. 验证进程是否仍在运行
            if (!isProcessRunning(processId)) {
                log.warn("进程 {} 不存在或已结束，任务可能已经停止", processId);
                // 更新任务状态为STOPPED
                task.setStatus(TaskStatus.STOPPED);
                saveTask(task);
                return;
            }
            
            // 5. 使用进程ID精确终止进程 - 确保物理释放所有计算资源
            log.info("发现目标进程 PID: {}, 开始强制终止并释放所有计算资源...", processId);
            
            // 使用强制终止命令确保彻底释放CPU/内存/显存
            ProcessBuilder killBuilder = new ProcessBuilder();
            killBuilder.command("taskkill", "/f", "/pid", String.valueOf(processId));
            Process killProcess = killBuilder.start();
            int killExitCode = killProcess.waitFor();
            
            // 额外确保：再次尝试终止（处理顽固进程）
            if (killExitCode != 0) {
                log.warn("第一次终止失败，尝试更强力的终止方式...");
                try {
                    // 尝试使用wmic强制终止
                    ProcessBuilder wmicKillBuilder = new ProcessBuilder(
                        "wmic", "process", "where", "ProcessId=" + processId, "delete"
                    );
                    Process wmicKillProcess = wmicKillBuilder.start();
                    int wmicExitCode = wmicKillProcess.waitFor();
                    log.info("WMIC终止结果: {}", wmicExitCode);
                } catch (Exception wmicException) {
                    log.error("WMIC终止失败: {}", wmicException.getMessage());
                }
            }
            
            // 等待进程完全退出并验证资源释放
            Thread.sleep(1000); // 等待1秒确保进程完全退出
            if (!isProcessRunning(processId)) {
                log.info("进程 {} 已被成功终止，计算资源已释放", processId);
            } else {
                log.error("进程 {} 仍在运行，资源可能未完全释放", processId);
                throw new RuntimeException("进程终止失败");
            }
            
            // 6. 记录停止日志到内存和文件
            String currentLog = task.getProcessLog() != null ? task.getProcessLog() : "";
            String stopLog = "\n进程手动终止: PID=" + processId + 
                           ", 终止时间=" + System.currentTimeMillis() +
                           ", 退出码=" + killExitCode + "\n";
            String updatedLog = currentLog + stopLog;
            task.setProcessLog(updatedLog);
            
            // 写入停止日志到文件
            try {
                Path taskDir = Paths.get("tasks", String.valueOf(timestamp));
                Path logFile = taskDir.resolve("task.log");
                Files.write(logFile, stopLog.getBytes(), StandardOpenOption.APPEND);
            } catch (IOException e) {
                log.warn("无法写入停止日志到文件: {}", e.getMessage());
            }
            
            // 7. 更新任务状态为STOPPED
            task.setStatus(TaskStatus.STOPPED);
            saveTask(task);
            
            log.info("任务 {} 停止成功", timestamp);
            
        } catch (Exception e) {
            log.error("停止任务失败: timestamp={}", timestamp, e);
            throw new RuntimeException("停止任务失败: " + e.getMessage(), e);
        }
    }

    /**
     * 验证进程是否仍在运行
     */
    private boolean isProcessRunning(long pid) {
        try {
            ProcessBuilder builder = new ProcessBuilder(
                "tasklist", "/fi", "PID", "eq", String.valueOf(pid), "/fo", "list");
            Process process = builder.start();
            
            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            String line;
            boolean found = false;
            
            while ((line = reader.readLine()) != null) {
                if (line.contains(String.valueOf(pid))) {
                    found = true;
                    break;
                }
            }
            
            process.waitFor();
            process.destroy();
            
            return found;
            
        } catch (Exception e) {
            log.warn("检查进程状态失败: PID={}, 错误: {}", pid, e.getMessage());
            return false;
        }
    }

    /**
     * 验证进程是否在指定任务目录中运行
     */
    private boolean isProcessRunningInTaskDirectory(String pid, Path taskDir) {
        try {
            // 使用 wmic 命令获取进程的命令行参数
            ProcessBuilder wmibuilder = new ProcessBuilder(
                "wmic", "process", "where", "ProcessId=" + pid, "get", "CommandLine");
            
            Process wmiProcess = wmibuilder.start();
            BufferedReader reader = new BufferedReader(new InputStreamReader(wmiProcess.getInputStream()));
            
            String line;
            boolean foundCommandLine = false;
            
            while ((line = reader.readLine()) != null) {
                if (!line.contains("CommandLine")) {
                    continue; // 跳过标题行
                }
                
                // 检查命令行是否包含任务目录路径
                if (line.contains(taskDir.toString())) {
                    foundCommandLine = true;
                    break;
                }
            }
            
            wmiProcess.waitFor();
            wmiProcess.destroy();
            
            return foundCommandLine;
            
        } catch (Exception e) {
            log.warn("验证进程工作目录失败: PID={}, 错误: {}", pid, e.getMessage());
            return true; // 如果无法验证，默认认为是目标进程
        }
    }

    /**
     * 获取任务日志
     * 优先从数据库获取，如果不存在则从文件读取
     */
    public String getTaskLog(Long timestamp) throws Exception {
        try {
            // 1. 先从数据库获取
            RunTaskEntity task = queryTask(timestamp);
            if (task != null && task.getProcessLog() != null && !task.getProcessLog().isEmpty()) {
                return task.getProcessLog();
            }
            
            // 2. 如果数据库中没有，尝试从文件读取
            Path taskDir = Paths.get("tasks", String.valueOf(timestamp));
            Path logFile = taskDir.resolve("task.log");
            
            if (Files.exists(logFile)) {
                byte[] logBytes = Files.readAllBytes(logFile);
                return new String(logBytes, StandardCharsets.UTF_8);
            }
            
            return "暂无日志信息";
            
        } catch (Exception e) {
            log.error("获取任务日志失败: timestamp={}", timestamp, e);
            throw new RuntimeException("获取任务日志失败: " + e.getMessage());
        }
    }

    public RunTaskEntity runTask(RunTaskRequest runTaskRequest) {
        try {
            // 0. 校验任务时间段的唯一性
            if (!validateTaskUniqueness(runTaskRequest)) {
                throw new RuntimeException("任务已存在！");
            }

            // 1. 查询关联规则信息
            AssociationRulesEntity associationRulesEntity = associationRulesService.queryRule(runTaskRequest.getRuleId());
            if (associationRulesEntity == null) {
                throw new RuntimeException("未找到关联规则: " + runTaskRequest.getRuleId());
            }

            long timestamp = System.currentTimeMillis();
            RunTaskEntity runTaskEntity = ConvertUtil.entityConvert(runTaskRequest, RunTaskEntity.class);
            runTaskEntity.setTimestamp(timestamp);
            runTaskEntity.setStatus(TaskStatus.PENDING);

            // 解析输入输出绑定
            List<InputBindDto> inputs = JSONArray.parseArray(associationRulesEntity.getInputsBind(), InputBindDto.class);
            List<OutputBindDto> outputs = JSONArray.parseArray(associationRulesEntity.getOutputsBind(), OutputBindDto.class);
            
            runTaskEntity.setInputMeasurements(JSONArray.toJSONString(inputs.stream().map(inputBindDto ->
                    String.format("%s.%s", associationRulesEntity.getTableName(), inputBindDto.getSourceField())).collect(Collectors.toList())));
            runTaskEntity.setOutputMeasurements(JSONArray.toJSONString(outputs.stream().map(outputBindDto ->
                    String.format("%s.%s", runTaskEntity.getOutputTable(), outputBindDto.getResultTarget())).collect(Collectors.toList())));
            saveTask(runTaskEntity);

            // 2. 创建任务目录 (相对于项目根目录的tasks文件夹下)
            Path taskDir = Paths.get("job", String.valueOf(timestamp));
            Files.createDirectories(taskDir);
            log.info("创建任务目录: {}", taskDir);

            // 3. 下载模型文件
            downloadModel(associationRulesEntity, taskDir);

            // 4. 导出数据
            downloadData(associationRulesEntity, inputs, taskDir, runTaskEntity);

            // 5. 执行命令
            if (associationRulesEntity.getCmd() != null && !associationRulesEntity.getCmd().trim().isEmpty()) {
                executeCommand(associationRulesEntity, runTaskEntity, taskDir, outputs);
            } else {
                log.warn("未设置运行命令，任务状态保持为PENDING");
            }
            
            // 返回创建的任务实体
            return runTaskEntity;

        } catch (Exception e) {
            log.error("运行任务失败", e);
            // 更新任务状态为失败
            try {
                RunTaskEntity runTaskEntity = ConvertUtil.entityConvert(runTaskRequest, RunTaskEntity.class);
                runTaskEntity.setStatus(TaskStatus.FAILED);
                saveTask(runTaskEntity);
            } catch (Exception saveException) {
                log.error("保存失败状态时发生错误", saveException);
            }
            throw new RuntimeException("运行任务失败: " + e.getMessage(), e);
        }
    }

    private void extractArchive(Path archiveFile, Path extractDir) {
        try {
            if (archiveFile.toString().toLowerCase().endsWith(".zip")) {
                // 使用Java内置的ZipInputStream解压ZIP文件
                try (java.util.zip.ZipInputStream zis = new java.util.zip.ZipInputStream(new FileInputStream(archiveFile.toFile()))) {
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

    private void exportDataToFile(DataQueryRequest request, Path csvFile, List<InputBindDto> inputs, String tableName) throws IOException {
        // 查询数据
        IginXTable table = dataTableService.queryIginXTable(request);

        try (PrintWriter writer = new PrintWriter(new FileWriter(csvFile.toFile()))) {
            // 直接一行一行写入表头和数据（参考DataTableService.exportData逻辑）
            IginXHeader header = table.getHeader();
            if (header.hasTimestamp()) {
                writer.print("key,");
            }
            
            // 根据InputBindDto映射关系写入表头
            for (InputBindDto input : inputs) {
                writer.print(input.getTargetField() + ","); // 使用targetField作为列名
            }
            writer.println();
            writer.flush();
            
            // 写入数据
            List<IginXRecord> records = table.getRecords();
            for (IginXRecord record : records) {
                if (header.hasTimestamp()) {
                    writer.print(record.getKey() + ",");
                }
                
                // 根据InputBindDto映射关系写入数据
                for (InputBindDto input : inputs) {
                    String sourceField = String.format("%s.%s", tableName, input.getSourceField());
                    Object value = record.getValue(sourceField);
                    
                    // 根据operator和conversionValue对数据进行计算
                    Object convertedValue = ConvertUtil.convertValue(value, input.getOperator(), input.getConversionValue());
                    
                    if (convertedValue instanceof byte[]) {
                        writer.print(ConvertUtil.bytesToString((byte[]) convertedValue));
                    } else {
                        writer.print(convertedValue);
                    }
                    writer.print(",");
                }
                writer.println();
                writer.flush();
            }
        }
    }

    public void saveTask(RunTaskEntity runTaskEntity) {
        List<Point> metaPoints = new ArrayList<>();
        long timestamp;
        if (runTaskEntity.getTimestamp() != null) {
            timestamp = runTaskEntity.getTimestamp();
        } else {
            timestamp = System.currentTimeMillis();
            runTaskEntity.setTimestamp(timestamp);
        }

        String metaBasePath = DATA_PREFIX;

        // 创建各个字段的数据点
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "name", runTaskEntity.getName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "startTime", runTaskEntity.getStartTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "endTime", runTaskEntity.getEndTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "ruleId", runTaskEntity.getRuleId(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "ruleName", runTaskEntity.getRuleName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "inputMeasurements", runTaskEntity.getInputMeasurements(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "outputMeasurements", runTaskEntity.getOutputMeasurements(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "outputTable", runTaskEntity.getOutputTable(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "status", runTaskEntity.getStatus(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "timestamp", runTaskEntity.getTimestamp(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "processId", runTaskEntity.getProcessId(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "processLog", runTaskEntity.getProcessLog(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "modelName", runTaskEntity.getModelName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "modelVersion", runTaskEntity.getModelVersion(), timestamp));

        // 批量写入元数据
        iginxClient.getWriteClient().writePoints(metaPoints.stream().filter(Objects::nonNull).collect(Collectors.toList()));
        log.info("任务已保存。名称: {}, 时间戳: {}", runTaskEntity.getName(), timestamp);
    }

    private void downloadModel(AssociationRulesEntity associationRulesEntity, Path taskDir) throws Exception {
        if (associationRulesEntity.getModelName() == null || associationRulesEntity.getModelVersion() == null) {
            throw new RuntimeException("模型名称或版本为空");
        }

        log.info("开始下载模型: {} v{}", associationRulesEntity.getModelName(), associationRulesEntity.getModelVersion());
        
        // 获取模型元数据以获取正确的文件名
        ModelMetaEntity modelMeta = modelFileService.queryMeta(associationRulesEntity.getModelName(), associationRulesEntity.getModelVersion());
        if (modelMeta == null) {
            throw new RuntimeException("未找到模型元数据: " + associationRulesEntity.getModelName() + " v" + associationRulesEntity.getModelVersion());
        }
        
        byte[] modelData = modelFileService.downloadModel(associationRulesEntity.getModelName(), associationRulesEntity.getModelVersion());
        String fileName = modelMeta.getFileName();
        if (fileName == null || fileName.trim().isEmpty()) {
            throw new RuntimeException("模型文件名为空: " + associationRulesEntity.getModelName() + " v" + associationRulesEntity.getModelVersion());
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
    }

    private void downloadData(AssociationRulesEntity associationRulesEntity, List<InputBindDto> inputs, Path taskDir, RunTaskEntity runTaskEntity) throws Exception {
        if (associationRulesEntity.getTableName() == null || inputs == null || inputs.isEmpty()) {
            throw new RuntimeException("数据表名或输入映射为空");
        }

        DataQueryRequest dataRequest = new DataQueryRequest();
        dataRequest.setPaths(inputs.stream().map(inputBindDto ->
                String.format("%s.%s", associationRulesEntity.getTableName(), inputBindDto.getSourceField()))
                .collect(Collectors.toList()));
        dataRequest.setStartTime(runTaskEntity.getStartTime());
        dataRequest.setEndTime(runTaskEntity.getEndTime());
        
        // 构建CSV文件路径
        String inputCsvFileName = associationRulesEntity.getInputCsvName();
        if (inputCsvFileName == null || inputCsvFileName.trim().isEmpty()) {
            throw new RuntimeException("输入CSV文件名为空");
        }
        Path csvFile = taskDir.resolve(inputCsvFileName);
        
        // 导出数据到文件
        exportDataToFile(dataRequest, csvFile, inputs, associationRulesEntity.getTableName());
        log.info("数据已导出到: {}", csvFile);
    }

    private void executeCommand(AssociationRulesEntity associationRulesEntity, RunTaskEntity runTaskEntity, Path taskDir, List<OutputBindDto> outputs) throws Exception {
        // 更新状态为RUNNING
        runTaskEntity.setStatus(TaskStatus.RUNNING);
        saveTask(runTaskEntity);
        
        // 在任务目录中执行命令
        ProcessBuilder processBuilder = new ProcessBuilder();
        processBuilder.directory(taskDir.toFile());
        
        // 解析命令（支持空格分隔的参数）
        String[] cmdArray = associationRulesEntity.getCmd().split("\\s+");
        processBuilder.command(cmdArray);
        
        log.info("执行命令: {} 在目录: {}", associationRulesEntity.getCmd(), taskDir);
        
        Process process = processBuilder.start();
        
        // 记录进程ID和日志
        long processId = 0;
        StringBuilder processLogBuilder = new StringBuilder();
        
        // 创建日志文件
        Path logFile = taskDir.resolve("task.log");
        
        try {
            // 获取进程ID - 尝试多种方式
            processId = 0;
            
            // 方法1: 尝试反射获取pid字段
            try {
                Field pidField = process.getClass().getDeclaredField("pid");
                pidField.setAccessible(true);
                processId = pidField.getLong(process);
                log.info("方法1成功获取进程ID: {}", processId);
            } catch (Exception e1) {
                log.info("方法1失败: {}", e1.getMessage());
                
                // 方法2: 尝试其他可能的字段名
                try {
                    Field handleField = process.getClass().getDeclaredField("handle");
                    handleField.setAccessible(true);
                    Object handle = handleField.get(process);
                    log.info("获取到handle: {} (类型: {})", handle, handle.getClass().getName());
                    
                    // handle直接就是Long类型的PID
                    if (handle instanceof Long) {
                        processId = (Long) handle;
                        log.info("方法2成功获取进程ID: {}", processId);
                    } else {
                        // 如果handle不是Long，尝试从handle中获取PID
                        try {
                            Method getPidMethod = handle.getClass().getMethod("getPid");
                            processId = (Long) getPidMethod.invoke(handle);
                            log.info("方法2a成功获取进程ID: {}", processId);
                        } catch (Exception e2a) {
                            log.info("方法2a失败: {}", e2a.getMessage());
                            
                            // 尝试其他方法名
                            try {
                                Method getPidMethod2 = handle.getClass().getMethod("pid");
                                processId = (Long) getPidMethod2.invoke(handle);
                                log.info("方法2b成功获取进程ID: {}", processId);
                            } catch (Exception e2b) {
                                log.info("方法2b失败: {}", e2b.getMessage());
                            }
                        }
                    }
                } catch (Exception e2) {
                    log.info("方法2失败: {}", e2.getMessage());
                }
            }
            
            // 如果都没成功，尝试使用系统命令获取
            if (processId == 0) {
                try {
                    // 在Windows上可以使用wmic获取当前进程的父进程ID
                    ProcessBuilder psBuilder = new ProcessBuilder("wmic", "process", "where", "name='python3'", "get", "ProcessId");
                    Process psProcess = psBuilder.start();
                    BufferedReader psReader = new BufferedReader(new InputStreamReader(psProcess.getInputStream()));
                    String line;
                    while ((line = psReader.readLine()) != null) {
                        if (line.matches("\\d+")) {
                            processId = Long.parseLong(line.trim());
                            log.info("方法3成功获取进程ID: {}", processId);
                            break;
                        }
                    }
                    psProcess.waitFor();
                } catch (Exception e3) {
                    log.info("方法3失败: {}", e3.getMessage());
                }
            }

            // 保存进程ID到任务实体
            runTaskEntity.setProcessId(processId);
            
            log.info("任务进程ID: {}, 任务时间戳: {}", processId, runTaskEntity.getTimestamp());
            String startLog = "进程启动: PID=" + processId +
                           ", 命令=" + associationRulesEntity.getCmd() +
                           ", 目录=" + taskDir.toString() +
                           ", 时间=" + System.currentTimeMillis() + "\n";
            processLogBuilder.append(startLog);
            
            // 写入日志文件
            Files.write(logFile, startLog.getBytes(), 
                       StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            
        } catch (Exception e) {
            log.warn("无法获取进程ID: {}", e.getMessage());
            String warnLog = "警告: 无法获取进程ID\n";
            processLogBuilder.append(warnLog);
            try {
                Files.write(logFile, warnLog.getBytes(), 
                           StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            } catch (IOException ioException) {
                log.warn("无法写入日志文件: {}", ioException.getMessage());
            }
        }
        
        // 异步执行进程监控和日志记录
        long finalProcessId = processId;
        CompletableFuture.runAsync(() -> {
            try {
                // 在监控开始时再次尝试获取进程ID
                if (finalProcessId == 0) {
                    log.info("监控开始，尝试重新获取进程ID...");
                    try {
                        // 方法1: 直接反射pid字段
                        Field pidField = process.getClass().getDeclaredField("pid");
                        pidField.setAccessible(true);
                        long retryProcessId = pidField.getLong(process);
                        if (retryProcessId > 0) {
                            // 保存进程ID到任务实体
                            runTaskEntity.setProcessId(retryProcessId);
                            log.info("监控方法1成功获取进程ID: {}", retryProcessId);
                            processLogBuilder.append("[INFO] 任务进程ID: " + retryProcessId + "\n");
                        }
                    } catch (Exception retryException1) {
                        log.info("监控方法1失败: {}", retryException1.getMessage());
                        
                        // 方法2: 尝试通过handle获取
                        try {
                            Field handleField = process.getClass().getDeclaredField("handle");
                            handleField.setAccessible(true);
                            Object handle = handleField.get(process);
                            log.info("监控获取到handle: {} (类型: {})", handle, handle.getClass().getName());
                            
                            // handle直接就是Long类型的PID
                            if (handle instanceof Long) {
                                long retryProcessId2 = (Long) handle;
                                runTaskEntity.setProcessId(retryProcessId2);
                                log.info("监控方法2成功获取进程ID: {}", retryProcessId2);
                                processLogBuilder.append("[INFO] 任务进程ID: " + retryProcessId2 + "\n");
                            } else {
                                // 如果handle不是Long，尝试从handle中获取PID
                                try {
                                    Method getPidMethod = handle.getClass().getMethod("getPid");
                                    long retryProcessId2 = (Long) getPidMethod.invoke(handle);
                                    runTaskEntity.setProcessId(retryProcessId2);
                                    log.info("监控方法2a成功获取进程ID: {}", retryProcessId2);
                                    processLogBuilder.append("[INFO] 任务进程ID: " + retryProcessId2 + "\n");
                                } catch (Exception retryException2a) {
                                    log.info("监控方法2a失败: {}", retryException2a.getMessage());
                                    
                                    // 尝试其他方法名
                                    try {
                                        Method getPidMethod2 = handle.getClass().getMethod("pid");
                                        long retryProcessId2b = (Long) getPidMethod2.invoke(handle);
                                        runTaskEntity.setProcessId(retryProcessId2b);
                                        log.info("监控方法2b成功获取进程ID: {}", retryProcessId2b);
                                        processLogBuilder.append("[INFO] 任务进程ID: " + retryProcessId2b + "\n");
                                    } catch (Exception retryException2b) {
                                        log.info("监控方法2b失败: {}", retryException2b.getMessage());
                                    }
                                }
                            }
                        } catch (Exception retryException2) {
                            log.info("监控方法2失败: {}", retryException2.getMessage());
                        }
                    }
                } else {
                    log.info("进程ID已存在: {}", finalProcessId);
                }
                
                // 读取进程输出和错误流，同时记录到内存和文件
                try (BufferedReader outputReader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                     BufferedReader errorReader = new BufferedReader(new InputStreamReader(process.getErrorStream()))) {
                    
                    String line;
                    
                    // 处理标准输出
                    while ((line = outputReader.readLine()) != null) {
                        String outputLine = "[OUT] " + line + "\n";
                        processLogBuilder.append(outputLine);
                        
                        // 实时写入日志文件
                        try {
                            Files.write(logFile, outputLine.getBytes(), StandardOpenOption.APPEND);
                        } catch (IOException e) {
                            log.warn("无法写入输出日志: {}", e.getMessage());
                        }
                    }
                    
                    // 处理错误输出
                    while ((line = errorReader.readLine()) != null) {
                        String errorLine = "[ERR] " + line + "\n";
                        processLogBuilder.append(errorLine);
                        
                        // 实时写入日志文件
                        try {
                            Files.write(logFile, errorLine.getBytes(), StandardOpenOption.APPEND);
                        } catch (IOException e) {
                            log.warn("无法写入错误日志: {}", e.getMessage());
                        }
                    }
                }
                
                int exitCode = process.waitFor();
                
                // 记录退出码和最终状态
                String endLog = "进程结束: 退出码=" + exitCode + 
                               ", 时间=" + System.currentTimeMillis() + "\n";
                processLogBuilder.append(endLog);
                
                // 写入最终状态到日志文件
                try {
                    Files.write(logFile, endLog.getBytes(), StandardOpenOption.APPEND);
                } catch (IOException e) {
                    log.warn("无法写入结束日志: {}", e.getMessage());
                }
                
                // 更新任务状态和日志
                runTaskEntity.setProcessLog(processLogBuilder.toString());
                if (exitCode == 0) {
                    log.info("命令执行成功，退出码: {}", exitCode);
                    runTaskEntity.setStatus(TaskStatus.SUCCESS);

                    // 处理输出CSV文件
                    try {
                        processOutputCsv(associationRulesEntity, taskDir, outputs, runTaskEntity);
                    } catch (Exception outputException) {
                        log.error("处理输出CSV文件失败: {}", outputException.getMessage(), outputException);
                        // 不影响任务成功状态，只记录错误
                    }
                } else {
                    log.error("命令执行失败，退出码: {}", exitCode);
                    runTaskEntity.setStatus(TaskStatus.FAILED);
                }
                
                saveTask(runTaskEntity);
                
            } catch (Exception e) {
                log.error("异步进程监控失败: PID={}", finalProcessId, e);
                // 更新任务状态为失败
                runTaskEntity.setStatus(TaskStatus.FAILED);
                String errorLog = "\n进程监控异常: " + e.getMessage() + "\n";
                runTaskEntity.setProcessLog(processLogBuilder.toString() + errorLog);
                
                // 即使saveTask失败，也要确保状态更新
                try {
                    saveTask(runTaskEntity);
                } catch (Exception saveException) {
                    log.error("保存任务状态失败: {}", saveException.getMessage(), saveException);
                    // 如果保存失败，至少记录到日志
                    log.error("任务状态应该为: {}, 进程ID: {}", TaskStatus.FAILED, finalProcessId);
                }
            }
        });
        
        log.info("任务已启动，进程监控将在后台异步执行");
    }

    /**
     * 处理输出CSV文件，将数据写入到对应的测点
     */
    private void processOutputCsv(AssociationRulesEntity associationRulesEntity, Path taskDir,
                                  List<OutputBindDto> outputs, RunTaskEntity runTaskEntity) throws Exception {
        if (associationRulesEntity.getOutputCsvName() == null || outputs == null || outputs.isEmpty()) {
            log.info("输出CSV文件名或输出映射为空，跳过输出处理");
            return;
        }

        // 构建输出CSV文件路径
        Path outputCsvFile = taskDir.resolve(associationRulesEntity.getOutputCsvName());

        if (!Files.exists(outputCsvFile)) {
            log.warn("输出CSV文件不存在: {}", outputCsvFile);
            return;
        }

        log.info("开始处理输出CSV文件: {}", outputCsvFile);

        // 复制输出CSV文件到同目录
        String modifiedCsvFileName = associationRulesEntity.getOutputCsvName().replace(".csv", "_bind.csv");
        Path modifiedCsvFile = taskDir.resolve(modifiedCsvFileName);
        Files.copy(outputCsvFile, modifiedCsvFile, StandardCopyOption.REPLACE_EXISTING);

        // 读取CSV内容并修改表头
        List<String> lines = Files.readAllLines(modifiedCsvFile, StandardCharsets.UTF_8);
        if (!lines.isEmpty()) {
            // 修改表头：将原列名(modelOutput)换成新列名(resultTarget)
            String originalHeader = lines.get(0);
            String[] originalColumns = originalHeader.split(",");

            // 构建新的表头映射
            Map<String, String> columnMapping = new HashMap<>();
            for (OutputBindDto output : outputs) {
                columnMapping.put(output.getModelOutput(), output.getResultTarget());
            }

            // 替换表头中的列名
            String[] newColumns = new String[originalColumns.length];
            for (int i = 0; i < originalColumns.length; i++) {
                String originalCol = originalColumns[i].trim();
                newColumns[i] = columnMapping.getOrDefault(originalCol, originalCol);
            }

            // 构建新表头
            StringBuilder newHeader = new StringBuilder();
            for (int i = 0; i < newColumns.length; i++) {
                newHeader.append(newColumns[i]);
                if (i < newColumns.length - 1) {
                    newHeader.append(",");
                }
            }

            // 替换表头
            lines.set(0, newHeader.toString());

            // 写回文件
            Files.write(modifiedCsvFile, lines, StandardCharsets.UTF_8);
        }

        long recordsNum = dataTableService.importCsvFile(modifiedCsvFile, runTaskEntity.getOutputTable(), modifiedCsvFileName);

        log.info("输出CSV文件导入完成，记录数: {}", recordsNum);

        log.info("输出CSV处理完成，处理了 {} 个输出映射", outputs.size());
    }

    /**
     * 上传任务报告文件到任务目录
     */
    public String uploadReport(MultipartFile file, Long timestamp) throws Exception {
        try {
            // 获取任务目录 (job/{timestamp})
            Path taskDir = Paths.get("job", String.valueOf(timestamp));
            
            if (!Files.exists(taskDir)) {
                throw new RuntimeException("任务目录不存在: " + taskDir);
            }
            
            // 保存原始HTML文件
            String originalFileName = file.getOriginalFilename();
            if (originalFileName == null || originalFileName.trim().isEmpty()) {
                originalFileName = "任务分析报告.html";
            }
            
            Path htmlFile = taskDir.resolve(originalFileName);
            Files.copy(file.getInputStream(), htmlFile, StandardCopyOption.REPLACE_EXISTING);
            
            // 尝试将HTML转换为PDF
            try {
                String pdfFileName = originalFileName.replace(".html", ".pdf");
                Path pdfFile = taskDir.resolve(pdfFileName);
                
                // 使用简单的HTML转PDF方法（这里可以集成更专业的PDF库如iText或Flying Saucer）
                convertHtmlToPdf(htmlFile, pdfFile);
                
                log.info("HTML报告已转换为PDF: {}", pdfFile);
                
            } catch (Exception pdfError) {
                log.warn("HTML转PDF失败，保留HTML文件: {}", pdfError.getMessage());
            }
            
            log.info("报告文件已上传到: {}", htmlFile);
            return htmlFile.toString();
            
        } catch (Exception e) {
            log.error("上传报告文件失败", e);
            throw new RuntimeException("上传报告文件失败: " + e.getMessage(), e);
        }
    }

    /**
     * 使用Flying Saucer进行专业的HTML转PDF - Java 8兼容的经典方案
     */
    private void convertHtmlToPdf(Path htmlFile, Path pdfFile) throws Exception {
        try {
            // 读取HTML内容
            String htmlContent;
            try (FileInputStream fis = new FileInputStream(htmlFile.toFile());
                 BufferedReader reader = new BufferedReader(new InputStreamReader(fis, StandardCharsets.UTF_8))) {
                
                StringBuilder htmlBuilder = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    htmlBuilder.append(line).append("\n");
                }
                htmlContent = htmlBuilder.toString();
            }
            
            // 确保HTML是完整的格式
            htmlContent = ensureCompleteHtml(htmlContent);
            
            // 使用Flying Saucer转换HTML为PDF
            ITextRenderer renderer = new ITextRenderer();
            
            // 设置文档内容
            renderer.setDocumentFromString(htmlContent);
            
            // 布局文档
            renderer.layout();
            
            // 创建PDF文件
            try (FileOutputStream fos = new FileOutputStream(pdfFile.toFile())) {
                renderer.createPDF(fos);
            }
            
            log.info("使用Flying Saucer转换HTML转PDF成功: {} -> {}", htmlFile, pdfFile);
            
        } catch (Exception e) {
            log.error("Flying Saucer转换失败，使用备用方案: {}", e.getMessage());
            // 如果Flying Saucer失败，使用自定义PDF生成
            try {
                String htmlContent = new String(Files.readAllBytes(htmlFile), StandardCharsets.UTF_8);
                createCustomPdf(htmlContent, pdfFile);
            } catch (Exception ignored) {
                // 最终备用方案
                createSimplePdf(htmlFile, pdfFile);
            }
        }
    }
    
    /**
     * 自定义PDF生成方法 - 生成标准PDF格式
     */
    private void createCustomPdf(String htmlContent, Path pdfFile) throws Exception {
        try (FileOutputStream fos = new FileOutputStream(pdfFile.toFile());
             OutputStreamWriter osw = new OutputStreamWriter(fos, StandardCharsets.ISO_8859_1);
             PrintWriter writer = new PrintWriter(osw)) {
            
            // 解析HTML内容并生成PDF
            String textContent = extractTextFromHtml(htmlContent);
            String[] lines = textContent.split("\n");
            
            // 生成标准PDF格式
            writer.println("%PDF-1.4");
            
            List<String> objects = new ArrayList<>();
            
            // PDF对象
            objects.add("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
            objects.add("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
            
            // 页面内容
            StringBuilder content = new StringBuilder();
            content.append("BT\n/F1 12 Tf\n");
            
            float y = 750;
            for (String line : lines) {
                if (y < 50) break;
                
                String cleanLine = line.trim();
                if (!cleanLine.isEmpty()) {
                    cleanLine = extractTextFromHtml(cleanLine);
                    cleanLine = cleanLine.length() > 80 ? cleanLine.substring(0, 80) + "..." : cleanLine;
                    
                    // 转义PDF特殊字符
                    cleanLine = cleanLine.replace("\\", "\\\\")
                                          .replace("(", "\\(")
                                          .replace(")", "\\)");
                    
                    if (!cleanLine.trim().isEmpty()) {
                        content.append("50 ").append(y).append(" Td\n(").append(cleanLine).append(") Tj\n");
                        y -= 15;
                    }
                }
            }
            
            content.append("ET\n");
            
            objects.add("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n");
            objects.add("4 0 obj\n<< /Length " + content.length() + " >>\nstream\n" + content + "\nendstream\nendobj\n");
            objects.add("5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n");
            
            // 写入对象
            long offset = 15; // PDF头长度
            StringBuilder xref = new StringBuilder("xref\n0 " + (objects.size() + 1) + "\n0000000000 65535 f \n");
            
            for (String obj : objects) {
                xref.append(String.format("%010d 00000 n \n", offset));
                offset += obj.length();
                writer.print(obj);
            }
            
            // 写入交叉引用表和尾部
            writer.println(xref.toString());
            writer.println("trailer");
            writer.println("<< /Size " + (objects.size() + 1) + " /Root 1 0 R >>");
            writer.println("startxref");
            writer.println(offset);
            writer.println("%%EOF");
        }
        
        log.info("自定义PDF生成成功: {}", pdfFile);
    }
    
    /**
     * 确保HTML是完整的格式
     */
    private String ensureCompleteHtml(String html) {
        // 如果HTML不完整，添加必要的结构
        if (!html.contains("<!DOCTYPE")) {
            html = "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">\n" + html;
        }
        
        if (!html.contains("<html")) {
            html = html.replaceFirst("<!DOCTYPE html[^>]*>", "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">");
            html = html.replace("<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">", 
                "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">\n<html>\n<head>\n<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\"></meta>\n<title>任务分析报告</title>\n" +
                "<style type=\"text/css\">\n" +
                "body { font-family: Arial, sans-serif; margin: 20px; }\n" +
                "h1 { color: #333; font-size: 24px; }\n" +
                "h2 { color: #666; font-size: 20px; }\n" +
                "h3 { color: #999; font-size: 18px; }\n" +
                "table { border-collapse: collapse; width: 100%; margin: 10px 0; }\n" +
                "th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }\n" +
                "th { background-color: #f2f2f2; }\n" +
                "p { margin: 10px 0; line-height: 1.6; }\n" +
                "</style>\n</head>\n<body>\n") + 
                html + "\n</body>\n</html>";
        }
        
        return html;
    }
    
    /**
     * 创建增强的PDF，解析HTML结构
     */
    private void createEnhancedPdf(Path htmlFile, Path pdfFile) throws Exception {
        // 读取HTML内容
        String htmlContent;
        try (FileInputStream fis = new FileInputStream(htmlFile.toFile());
             BufferedReader reader = new BufferedReader(new InputStreamReader(fis, StandardCharsets.UTF_8))) {
            
            StringBuilder htmlBuilder = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                htmlBuilder.append(line).append("\n");
            }
            htmlContent = htmlBuilder.toString();
        }
        
        // 先移除CSS样式，避免干扰
        htmlContent = removeCssAndScripts(htmlContent);
        
        // 解析HTML结构
        List<PdfElement> elements = parseHtmlToPdfElements(htmlContent);
        
        // 创建PDF
        try (FileOutputStream fos = new FileOutputStream(pdfFile.toFile())) {
            // PDF文件头
            String pdfHeader = "%PDF-1.4\n";
            fos.write(pdfHeader.getBytes(StandardCharsets.ISO_8859_1));
            
            // PDF对象
            List<String> objects = new ArrayList<>();
            
            // 添加目录对象
            objects.add("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
            
            // 添加页面对象
            objects.add("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
            
            // 添加页面内容
            String pageContent = generateSimplePageContent(elements);
            objects.add("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n");
            
            // 添加内容流
            objects.add("4 0 obj\n<< /Length " + pageContent.length() + " >>\nstream\n" + pageContent + "\nendstream\nendobj\n");
            
            // 添加字体对象
            objects.add("5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n");
            
            // 计算偏移量并写入对象
            long offset = pdfHeader.length();
            StringBuilder xref = new StringBuilder("xref\n0 " + (objects.size() + 1) + "\n0000000000 65535 f \n");
            
            for (String obj : objects) {
                xref.append(String.format("%010d 00000 n \n", offset));
                offset += obj.length();
                fos.write(obj.getBytes(StandardCharsets.ISO_8859_1));
            }
            
            // 写入交叉引用表和尾部
            String trailer = "trailer\n<< /Size " + (objects.size() + 1) + " /Root 1 0 R >>\nstartxref\n" + offset + "\n%%EOF\n";
            fos.write(xref.toString().getBytes(StandardCharsets.ISO_8859_1));
            fos.write(trailer.getBytes(StandardCharsets.ISO_8859_1));
        }
        
        log.info("创建增强PDF完成: {} -> {}", htmlFile, pdfFile);
    }
    
    /**
     * 移除CSS和JavaScript
     */
    private String removeCssAndScripts(String html) {
        // 移除<style>标签及其内容
        html = html.replaceAll("(?s)<style.*?</style>", "");
        // 移除<script>标签及其内容
        html = html.replaceAll("(?s)<script.*?</script>", "");
        // 移除CSS链接
        html = html.replaceAll("<link[^>]*>", "");
        // 移除内联样式
        html = html.replaceAll("style=\"[^\"]*\"", "");
        html = html.replaceAll("style='[^']*'", "");
        
        return html;
    }
    
    /**
     * 生成简化的页面内容
     */
    private String generateSimplePageContent(List<PdfElement> elements) {
        StringBuilder content = new StringBuilder();
        content.append("BT\n"); // 开始文本
        content.append("/F1 12 Tf\n"); // 设置字体
        
        float y = 750; // 起始Y坐标
        float x = 50;  // 起始X坐标
        
        for (PdfElement element : elements) {
            if (y < 50) break; // 防止超出页面
            
            String text = element.text;
            if (text == null || text.trim().isEmpty()) continue;
            
            // 清理文本，移除特殊字符
            text = cleanTextForPdf(text);
            
            // 进一步简化文本，只保留基本ASCII和中文
            text = simplifyText(text);
            
            // 限制长度
            if (text.length() > 60) {
                text = text.substring(0, 60) + "...";
            }
            
            // 如果文本为空，跳过
            if (text.trim().isEmpty()) continue;
            
            // 设置位置
            content.append(x).append(" ").append(y).append(" Td\n");
            
            // 根据类型调整字体大小
            switch (element.type) {
                case "heading1":
                    content.append("/F1 16 Tf\n");
                    y -= 20;
                    break;
                case "heading2":
                    content.append("/F1 14 Tf\n");
                    y -= 18;
                    break;
                case "heading3":
                    content.append("/F1 13 Tf\n");
                    y -= 16;
                    break;
                default:
                    content.append("/F1 12 Tf\n");
                    y -= 14;
                    break;
            }
            
            // 写入文本
            content.append("(").append(text).append(") Tj\n");
        }
        
        content.append("ET\n"); // 结束文本
        return content.toString();
    }
    
    /**
     * 简化文本，只保留安全字符
     */
    private String simplifyText(String text) {
        if (text == null) return "";
        
        // 只保留ASCII字符、数字、基本标点和中文
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            
            // ASCII可打印字符
            if (c >= 32 && c <= 126) {
                result.append(c);
            }
            // 中文字符范围
            else if (c >= '\u4E00' && c <= '\u9FFF') {
                result.append(c);
            }
            // 其他字符用空格替换
            else {
                result.append(' ');
            }
        }
        
        return result.toString();
    }
    
    /**
     * 清理文本用于PDF
     */
    private String cleanTextForPdf(String text) {
        if (text == null) return "";
        
        // 移除HTML标签
        text = text.replaceAll("<[^>]*>", "");
        
        // 替换HTML实体
        text = text.replace("&nbsp;", " ")
                  .replace("&lt;", "<")
                  .replace("&gt;", ">")
                  .replace("&amp;", "&")
                  .replace("&quot;", "\"")
                  .replace("&#39;", "'")
                  .replace("&apos;", "'");
        
        // 移除多余空格和换行
        text = text.replaceAll("\\s+", " ").trim();
        
        // 转义PDF特殊字符
        text = text.replace("\\", "\\\\")
                  .replace("(", "\\(")
                  .replace(")", "\\)");
        
        return text;
    }
    
    /**
     * 解析HTML为PDF元素
     */
    private List<PdfElement> parseHtmlToPdfElements(String html) {
        List<PdfElement> elements = new ArrayList<>();
        
        // 简单的HTML解析
        String[] lines = html.split("\n");
        for (String line : lines) {
            line = line.trim();
            if (line.isEmpty()) continue;
            
            if (line.contains("<h1>")) {
                String text = extractTextFromTag(line, "h1");
                elements.add(new PdfElement(text, "heading1"));
            } else if (line.contains("<h2>")) {
                String text = extractTextFromTag(line, "h2");
                elements.add(new PdfElement(text, "heading2"));
            } else if (line.contains("<h3>")) {
                String text = extractTextFromTag(line, "h3");
                elements.add(new PdfElement(text, "heading3"));
            } else if (line.contains("<p>")) {
                String text = extractTextFromTag(line, "p");
                elements.add(new PdfElement(text, "paragraph"));
            } else if (line.contains("<table")) {
                // 简单的表格处理
                elements.add(new PdfElement("[表格]", "table"));
            } else if (line.contains("<img")) {
                elements.add(new PdfElement("[图片]", "image"));
            } else if (!line.startsWith("<")) {
                // 纯文本
                elements.add(new PdfElement(line, "text"));
            }
        }
        
        return elements;
    }
    
    /**
     * 从标签中提取文本
     */
    private String extractTextFromTag(String line, String tag) {
        String pattern = "<" + tag + ".*?>(.*?)</" + tag + ">";
        java.util.regex.Pattern p = java.util.regex.Pattern.compile(pattern, java.util.regex.Pattern.DOTALL);
        java.util.regex.Matcher m = p.matcher(line);
        if (m.find()) {
            return extractTextFromHtml(m.group(1));
        }
        return "";
    }
    
    /**
     * PDF元素类
     */
    private static class PdfElement {
        String text;
        String type;
        
        PdfElement(String text, String type) {
            this.text = text;
            this.type = type;
        }
    }
    
    /**
     * 备用的简单PDF创建方法
     */
    private void createSimplePdf(Path htmlFile, Path pdfFile) throws Exception {
        // 读取HTML内容
        String htmlContent;
        try (FileInputStream fis = new FileInputStream(htmlFile.toFile());
             BufferedReader reader = new BufferedReader(new InputStreamReader(fis, StandardCharsets.UTF_8))) {
            
            StringBuilder htmlBuilder = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                htmlBuilder.append(line).append("\n");
            }
            htmlContent = htmlBuilder.toString();
        }
        
        // 提取HTML中的文本内容
        String textContent = extractTextFromHtml(htmlContent);
        
        // 创建基本的PDF文件
        try (FileOutputStream fos = new FileOutputStream(pdfFile.toFile())) {
            // PDF文件头
            String pdfHeader = "%PDF-1.4\n";
            fos.write(pdfHeader.getBytes(StandardCharsets.ISO_8859_1));
            
            // 创建一个简单的PDF对象
            String catalog = "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n";
            String pages = "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n";
            String page = "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n";
            
            // 将文本内容转换为PDF流
            String pdfText = convertTextToPdfStream(textContent);
            String content = "4 0 obj\n<< /Length " + pdfText.length() + " >>\nstream\n" + pdfText + "\nendstream\nendobj\n";
            
            // 字体对象（简单使用内置字体）
            String font = "5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n";
            
            // 交叉引用表
            String xref = "xref\n0 6\n0000000000 65535 f \n";
            long offset1 = pdfHeader.length();
            xref += String.format("%010d 00000 n \n", offset1);
            long offset2 = offset1 + catalog.length();
            xref += String.format("%010d 00000 n \n", offset2);
            long offset3 = offset2 + pages.length();
            xref += String.format("%010d 00000 n \n", offset3);
            long offset4 = offset3 + page.length();
            xref += String.format("%010d 00000 n \n", offset4);
            long offset5 = offset4 + content.length();
            xref += String.format("%010d 00000 n \n", offset5);
            
            // PDF尾部
            String trailer = "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n" + (offset5 + font.length()) + "\n%%EOF\n";
            
            // 写入所有PDF对象
            fos.write(catalog.getBytes(StandardCharsets.ISO_8859_1));
            fos.write(pages.getBytes(StandardCharsets.ISO_8859_1));
            fos.write(page.getBytes(StandardCharsets.ISO_8859_1));
            fos.write(content.getBytes(StandardCharsets.ISO_8859_1));
            fos.write(font.getBytes(StandardCharsets.ISO_8859_1));
            fos.write(xref.getBytes(StandardCharsets.ISO_8859_1));
            fos.write(trailer.getBytes(StandardCharsets.ISO_8859_1));
        }
        
        log.info("使用备用方案创建简单PDF: {} -> {}", htmlFile, pdfFile);
    }
    
    /**
     * 将文本内容转换为PDF流格式
     */
    private String convertTextToPdfStream(String text) {
        StringBuilder pdfStream = new StringBuilder();
        pdfStream.append("BT\n/F1 12 Tf\n50 750 Td\n"); // 开始文本，设置字体和位置
        
        // 简单的文本换行处理
        String[] lines = text.split("\n");
        for (int i = 0; i < lines.length && i < 60; i++) { // 限制行数避免超出页面
            String line = lines[i].trim();
            if (!line.isEmpty()) {
                // 转义PDF特殊字符
                line = line.replace("\\", "\\\\")
                          .replace("(", "\\(")
                          .replace(")", "\\)");
                
                // 限制每行长度
                if (line.length() > 80) {
                    line = line.substring(0, 80) + "...";
                }
                
                pdfStream.append("(").append(line).append(") Tj\n");
                pdfStream.append("0 -12 Td\n"); // 换行
            }
        }
        
        pdfStream.append("ET\n"); // 结束文本
        return pdfStream.toString();
    }

    /**
     * 从HTML中提取纯文本内容
     */
    private String extractTextFromHtml(String html) {
        // 简单的HTML标签移除
        String text = html.replaceAll("<[^>]*>", "");
        text = text.replaceAll("&nbsp;", " ");
        text = text.replaceAll("&lt;", "<");
        text = text.replaceAll("&gt;", ">");
        text = text.replaceAll("&amp;", "&");
        text = text.replaceAll("&quot;", "\"");
        text = text.replaceAll("&#39;", "'");
        
        // 移除多余的空白字符
        text = text.replaceAll("\\s+", " ").trim();
        
        return text;
    }

    /**
     * 打包并下载任务文件
     */
    public ResponseEntity<Resource> packageAndDownload(Long timestamp) throws Exception {
        try {
            // 获取任务目录
            Path taskDir = Paths.get("job", String.valueOf(timestamp));
            
            if (!Files.exists(taskDir)) {
                throw new RuntimeException("任务目录不存在: " + taskDir);
            }
            
            // 创建真正的临时目录
            Path tempDir = Files.createTempDirectory("task-download-");
            String zipFileName = String.format("task_%s_%d.zip", timestamp, System.currentTimeMillis());
            Path zipFile = tempDir.resolve(zipFileName);
            
            // 创建ZIP文件
            try (ZipOutputStream zipOut = new ZipOutputStream(Files.newOutputStream(zipFile))) {
                // 添加任务目录中的所有文件
                Files.walk(taskDir)
                    .filter(path -> !Files.isDirectory(path))
                    .forEach(path -> {
                        try {
                            String entryName = taskDir.relativize(path).toString().replace("\\", "/");
                            ZipEntry zipEntry = new ZipEntry(entryName);
                            zipOut.putNextEntry(zipEntry);
                            Files.copy(path, zipOut);
                            zipOut.closeEntry();
                        } catch (Exception e) {
                            log.warn("跳过文件 {}: {}", path, e.getMessage());
                        }
                    });
            }
            
            log.info("任务文件已打包到: {}", zipFile);
            
            // 创建资源并返回下载响应
            Resource resource = new org.springframework.core.io.PathResource(zipFile);
            String fileName = "task_" + timestamp + "_" + System.currentTimeMillis() + ".zip";
            
            // 设置下载完成后删除临时文件的钩子
            resource.getFile().deleteOnExit();
            tempDir.toFile().deleteOnExit();
            
            return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + fileName + "\"")
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body(resource);
                
        } catch (Exception e) {
            log.error("打包下载失败", e);
            throw new RuntimeException("打包下载失败: " + e.getMessage(), e);
        }
    }

}
