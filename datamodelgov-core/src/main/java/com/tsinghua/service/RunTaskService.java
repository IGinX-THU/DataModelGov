package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXHeader;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.alibaba.fastjson2.JSONArray;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.auth.util.VisibilitySqlUtil;
import com.tsinghua.dto.DataQueryRequest;
import com.tsinghua.dto.InputBindDto;
import com.tsinghua.dto.OutputBindDto;
import com.tsinghua.dto.RunTaskQueryRequest;
import com.tsinghua.dto.RunTaskRequest;
import com.tsinghua.dto.TimeRangeRequest;
import com.tsinghua.dto.TimeRangeResponse;
import com.tsinghua.entity.AssociationRulesEntity;
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
import org.springframework.util.CollectionUtils;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import com.itextpdf.html2pdf.HtmlConverter;
import com.itextpdf.kernel.pdf.PdfDocument;
import com.itextpdf.kernel.pdf.PdfWriter;
import com.itextpdf.layout.Document;
import com.itextpdf.layout.element.IElement;
import com.itextpdf.layout.element.IBlockElement;
import java.util.List;

import com.tsinghua.auth.util.AuthUtil;

import java.awt.image.BufferedImage;
import java.io.*;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.Base64;
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
    private DataPermissionService dataPermissionService;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private AlgorithmFileService algorithmFileService;

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

            if (!AuthUtil.isAdmin()) {
                List<String> tables = dataPermissionService.getCurrentUserAccessibleTables();
                List<String> modelTables = tables.stream()
                        .filter(table -> table.startsWith("models_system"))
                        .collect(Collectors.toList());
                VisibilitySqlUtil.generateModelVisibilityFilter(modelTables, sql);
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

            if (!AuthUtil.isAdmin()) {
                List<String> tables = dataPermissionService.getCurrentUserAccessibleTables();
                List<String> modelTables = tables.stream()
                        .filter(table -> table.startsWith("models_system"))
                        .collect(Collectors.toList());
                VisibilitySqlUtil.generateModelVisibilityFilter(modelTables, sql);
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
     * 同时删除任务文件目录
     */
    public void deleteTask(Long timestamp) {
        try {
            // 1. 删除数据库中的数据
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(RunTaskEntity.class, DATA_PREFIX);
            // 删除指定时间戳的数据
            iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp - 1, timestamp + 1);
            log.info("已删除运行任务数据库数据: timestamp: {}", timestamp);
            
            // 2. 删除任务文件目录
            Path taskDir = Paths.get("job", String.valueOf(timestamp));
            if (Files.exists(taskDir)) {
                try {
                    // 转换为File对象并递归删除
                    File dir = taskDir.toFile();
                    if (deleteDirectory(dir)) {
                        log.info("已删除任务目录: {}", taskDir);
                    } else {
                        log.warn("删除任务目录部分失败: {}", taskDir);
                    }
                } catch (Exception e) {
                    log.error("删除任务目录失败: {}, 错误: {}", taskDir, e.getMessage());
                    // 不抛出异常，允许数据库删除成功
                }
            } else {
                log.info("任务目录不存在，跳过删除: {}", taskDir);
            }
            
            log.info("任务删除完成: timestamp: {}", timestamp);
        } catch (Exception e) {
            log.error("删除运行任务失败", e);
            throw new RuntimeException("删除运行任务失败: " + e.getMessage(), e);
        }
    }

    /**
     * 递归删除目录及其所有内容
     */
    private boolean deleteDirectory(File directory) {
        if (!directory.exists()) {
            return true;
        }
        
        if (!directory.isDirectory()) {
            return directory.delete();
        }
        
        File[] files = directory.listFiles();
        if (files != null) {
            for (File file : files) {
                if (!deleteDirectory(file)) {
                    return false;
                }
            }
        }
        
        return directory.delete();
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
            if (!TaskStatus.RUNNING.getValue().equals(task.getStatus())) {
                // 如果任务不在运行状态，直接标记为已停止
                log.info("任务不在运行状态，直接标记为已停止: {}", task.getStatus());
                task.setStatus(TaskStatus.STOPPED.getValue());
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
                task.setStatus(TaskStatus.STOPPED.getValue());
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
                Path taskDir = Paths.get("job", String.valueOf(timestamp));
                Path logFile = taskDir.resolve("task.log");
                Files.write(logFile, stopLog.getBytes(), StandardOpenOption.APPEND);
            } catch (IOException e) {
                log.warn("无法写入停止日志到文件: {}", e.getMessage());
            }
            
            // 7. 更新任务状态为STOPPED
            task.setStatus(TaskStatus.STOPPED.getValue());
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
            Path taskDir = Paths.get("job", String.valueOf(timestamp));
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
        RunTaskEntity runTaskEntity = ConvertUtil.entityConvert(runTaskRequest, RunTaskEntity.class);
        try {
            // 0. 校验任务时间段的唯一性
            if (!validateTaskUniqueness(runTaskRequest)) {
                throw new RuntimeException("任务已存在！");
            }

            // 1. 查询关联规则信息
            AssociationRulesEntity associationRulesEntity = associationRulesService.queryRule(runTaskRequest.getRuleId());
            if (associationRulesEntity == null || !associationRulesEntity.getStatus()) {
                throw new RuntimeException("未找到关联规则或已禁用: " + runTaskRequest.getRuleId());
            }

            long timestamp = System.currentTimeMillis();
            runTaskEntity.setTimestamp(timestamp);
            runTaskEntity.setStatus(TaskStatus.PENDING.getValue());
            runTaskEntity.setStartTime(Optional.ofNullable(runTaskRequest.getStartTime()).orElse(0L));
            runTaskEntity.setEndTime(Optional.ofNullable(runTaskRequest.getEndTime()).orElse(timestamp));

            // 解析输入输出绑定
            List<InputBindDto> inputs = JSONArray.parseArray(associationRulesEntity.getInputsBind(), InputBindDto.class);
            List<OutputBindDto> outputs = JSONArray.parseArray(associationRulesEntity.getOutputsBind(), OutputBindDto.class);
            
            runTaskEntity.setInputMeasurements(JSONArray.toJSONString(inputs.stream().map(inputBindDto ->
                    String.format("%s.%s", associationRulesEntity.getTableName(), inputBindDto.getSourceField())).collect(Collectors.toList())));
            runTaskEntity.setOutputMeasurements(JSONArray.toJSONString(outputs.stream().map(outputBindDto ->
                    String.format("%s.%s", runTaskEntity.getOutputTable(), outputBindDto.getResultTarget())).collect(Collectors.toList())));
            runTaskEntity.setOwner(AuthUtil.getCurrentUsername());
            saveTask(runTaskEntity);

            // 2. 创建任务目录 (相对于项目根目录的tasks文件夹下)
            Path taskDir = Paths.get("job", String.valueOf(timestamp));
            Files.createDirectories(taskDir);
            log.info("创建任务目录: {}", taskDir);

            // 3. 下载算法文件
            algorithmFileService.extractAlgorithmFile(associationRulesEntity.getAlgorithmName(), associationRulesEntity.getAlgorithmVersion(), taskDir);

            // 4. 导出数据
            downloadData(associationRulesEntity, inputs, taskDir, runTaskEntity);

            // 5. 执行命令
            if (associationRulesEntity.getCmd() != null && !associationRulesEntity.getCmd().trim().isEmpty()) {
                executeCommand(associationRulesEntity, runTaskEntity, taskDir, outputs);
            } else {
                log.warn("未设置运行命令，任务状态保持为PENDING");
            }

        } catch (Exception e) {
            log.error("运行任务失败", e);
            // 更新任务状态为失败
            runTaskEntity.setStatus(TaskStatus.FAILED.getValue());
            runTaskEntity.setProcessLog(e.getMessage());
            saveTask(runTaskEntity);
        }
        // 返回创建的任务实体
        return runTaskEntity;
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
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "algorithmName", runTaskEntity.getAlgorithmName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "algorithmVersion", runTaskEntity.getAlgorithmVersion(), timestamp));

        // 批量写入元数据
        iginxClient.getWriteClient().writePoints(metaPoints.stream().filter(Objects::nonNull).collect(Collectors.toList()));
        log.info("任务已保存。名称: {}, 时间戳: {}", runTaskEntity.getName(), timestamp);
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
        runTaskEntity.setStatus(TaskStatus.RUNNING.getValue());
        saveTask(runTaskEntity);
        
        // 在任务目录中执行命令
        ProcessBuilder processBuilder = new ProcessBuilder();
        processBuilder.directory(taskDir.toFile());

        // 解析命令（支持空格分隔的参数）
        // 根据操作系统类型处理编码问题
        String[] cmdArray;
        String osName = System.getProperty("os.name", "").toLowerCase();
        if (osName.contains("windows")) {
            // Windows上使用chcp 65001设置控制台代码页为UTF-8，确保中文输出正常
            cmdArray = new String[]{"cmd", "/c", "chcp 65001 && " + associationRulesEntity.getCmd()};
        } else {
            // Linux/Mac默认使用UTF-8编码，直接执行原命令
            cmdArray = associationRulesEntity.getCmd().split("\\s+");
        }
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
                // 由于已经通过chcp 65001设置了控制台代码页为UTF-8，cmd输出现在是UTF-8编码
                try (BufferedReader outputReader = new BufferedReader(new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8));
                     BufferedReader errorReader = new BufferedReader(new InputStreamReader(process.getErrorStream(), StandardCharsets.UTF_8))) {

                    String line;

                    // 处理标准输出
                    while ((line = outputReader.readLine()) != null) {
                        String outputLine = "[OUT] " + line + "\n";
                        processLogBuilder.append(outputLine);

                        // 实时写入日志文件，使用UTF-8编码
                        try {
                            Files.write(logFile, outputLine.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND);
                        } catch (IOException e) {
                            log.warn("无法写入输出日志: {}", e.getMessage());
                        }
                    }

                    // 处理错误输出
                    while ((line = errorReader.readLine()) != null) {
                        String errorLine = "[ERR] " + line + "\n";
                        processLogBuilder.append(errorLine);

                        // 实时写入日志文件，使用UTF-8编码
                        try {
                            Files.write(logFile, errorLine.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND);
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
                    runTaskEntity.setStatus(TaskStatus.SUCCESS.getValue());

                    // 处理输出CSV文件
                    try {
                        processOutputCsv(associationRulesEntity, taskDir, outputs, runTaskEntity);
                    } catch (Exception outputException) {
                        log.error("处理输出CSV文件失败: {}", outputException.getMessage(), outputException);
                        // 不影响任务成功状态，只记录错误
                    }
                } else {
                    log.error("命令执行失败，退出码: {}", exitCode);
                    runTaskEntity.setStatus(TaskStatus.FAILED.getValue());
                    String errorLog = "\n命令执行失败，退出码: " + exitCode+ "\n";
                    runTaskEntity.setProcessLog(processLogBuilder.toString() + errorLog);
                }
                
                saveTask(runTaskEntity);
                
            } catch (Exception e) {
                log.error("异步进程监控失败: PID={}", finalProcessId, e);
                // 更新任务状态为失败
                runTaskEntity.setStatus(TaskStatus.FAILED.getValue());
                String errorLog = "\n进程监控异常: " + e.getMessage() + "\n";
                runTaskEntity.setProcessLog(processLogBuilder.toString() + errorLog);
                
                // 即使saveTask失败，也要确保状态更新
                try {
                    saveTask(runTaskEntity);
                } catch (Exception saveException) {
                    log.error("保存任务状态失败: {}", saveException.getMessage(), saveException);
                    // 如果保存失败，至少记录到日志
                    log.error("任务状态应该为: {}, 进程ID: {}", TaskStatus.FAILED.getValue(), finalProcessId);
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

        long recordsNum = dataTableService.importCsvFile(modifiedCsvFile, runTaskEntity.getOutputTable(), modifiedCsvFileName, null, runTaskEntity.getOwner());

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

                 // 使用HTML转PDF方法
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
     * 使用 iText 7 + html2pdf 进行纯Java的HTML转PDF转换
     * 完美支持中文、ECharts图表、CSS样式等，无需外部依赖
     */
    private void convertHtmlToPdf(Path htmlFile, Path pdfFile) throws Exception {
        log.info("开始使用 iText 7 + html2pdf 进行HTML转PDF转换: {} -> {}", htmlFile, pdfFile);
        
        try {
            // 1. 读取并预处理HTML内容
            String htmlContent = readFileContent(htmlFile);
            htmlContent = preprocessHtmlForIText7(htmlContent);
            
            // 2. 确保输出目录存在
            Path parentDir = pdfFile.getParent();
            if (parentDir != null && !Files.exists(parentDir)) {
                Files.createDirectories(parentDir);
            }
            
            // 3. 创建PDF输出流
            try (FileOutputStream fos = new FileOutputStream(pdfFile.toFile())) {
                // 4. 创建PdfWriter和PdfDocument
                PdfWriter writer = new PdfWriter(fos);
                PdfDocument pdfDocument = new PdfDocument(writer);
                
                // 5. 创建Document
                Document document = new Document(pdfDocument);
                
                // 6. 设置文档属性
                pdfDocument.setDefaultPageSize(com.itextpdf.kernel.geom.PageSize.A4);
                
                // 7. 转换HTML到PDF
                com.itextpdf.html2pdf.ConverterProperties properties = 
                    new com.itextpdf.html2pdf.ConverterProperties();
                properties.setBaseUri(htmlFile.getParent().toUri().toString());
                
                // 方法1：使用DefaultFontProvider
                try {
                    com.itextpdf.html2pdf.resolver.font.DefaultFontProvider fontProvider = 
                        new com.itextpdf.html2pdf.resolver.font.DefaultFontProvider(false, false, false);
                    
                    // 添加系统中文字体
                    try {
                        fontProvider.addFont("C:/Windows/Fonts/simsun.ttc");
                        log.debug("成功添加宋体字体");
                    } catch (Exception e) {
                        log.debug("添加宋体字体失败: {}", e.getMessage());
                    }
                    
                    try {
                        fontProvider.addFont("C:/Windows/Fonts/msyh.ttc");
                        log.debug("成功添加微软雅黑字体");
                    } catch (Exception e) {
                        log.debug("添加微软雅黑字体失败: {}", e.getMessage());
                    }
                    
                    try {
                        fontProvider.addFont("C:/Windows/Fonts/simhei.ttf");
                        log.debug("成功添加黑体字体");
                    } catch (Exception e) {
                        log.debug("添加黑体字体失败: {}", e.getMessage());
                    }
                    
                    properties.setFontProvider(fontProvider);
                    log.debug("使用DefaultFontProvider字体提供程序");
                } catch (Exception e) {
                    log.warn("字体提供程序设置失败: {}", e.getMessage());
                    // 继续使用默认字体提供程序
                }
                
                HtmlConverter.convertToPdf(htmlContent, pdfDocument, properties);
                
                // 8. 关闭文档
                document.close();
            }
            
            // 9. 验证PDF文件是否生成成功
            if (Files.exists(pdfFile) && Files.size(pdfFile) > 0) {
                log.info("iText 7 HTML转PDF转换成功: {} -> {} (大小: {} bytes)", 
                         htmlFile, pdfFile, Files.size(pdfFile));
            } else {
                throw new RuntimeException("PDF文件生成失败或为空");
            }
            
        } catch (Exception e) {
            log.error("iText 7 HTML转PDF转换失败: {}", e.getMessage(), e);
            throw new Exception("HTML转PDF转换失败: " + e.getMessage(), e);
        }
    }
    
    /**
     * 为 iText 7 预处理HTML内容
     */
    private String preprocessHtmlForIText7(String html) {
        // 1. 确保HTML是完整的格式
        html = ensureCompleteHtmlForIText7(html);
        
        // 2. 添加中文字体支持
        html = addChineseFontSupportForIText7(html);
        
        // 3. 优化ECharts图表渲染
        html = optimizeEChartsForIText7(html);
        
        // 4. 添加PDF打印样式
        html = addPrintStylesForIText7(html);
        
        return html;
    }
    
    /**
     * 确保HTML适合 iText 7
     */
    private String ensureCompleteHtmlForIText7(String html) {
        // 如果HTML不包含DOCTYPE，添加标准HTML5 DOCTYPE
        if (!html.contains("<!DOCTYPE")) {
            html = "<!DOCTYPE html>\n" + html;
        }
        
        // 如果没有html标签，包装成完整HTML
        if (!html.contains("<html")) {
            html = html.replaceFirst("<!DOCTYPE[^>]*>", "<!DOCTYPE html>");
            html = "<html>\n<head>\n" +
                   "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\"/>\n" +
                   "<meta charset=\"UTF-8\"/>\n" +
                   "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\"/>\n" +
                   "<title>任务分析报告</title>\n" +
                   getIText7CssStyles() +
                   "</head>\n<body style=\"font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;\">\n" + html + "\n</body>\n</html>";
        }
        
        return html;
    }
    
    /**
     * 获取 iText 7 优化的CSS样式
     */
    private String getIText7CssStyles() {
        return "<style type=\"text/css\">\n" +
               "@page {\n" +
               "  size: A4;\n" +
               "  margin: 2cm;\n" +
               "}\n" +
               "@media print {\n" +
               "  body { font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif !important; }\n" +
               "  .no-print { display: none !important; }\n" +
               "  .chart-container { page-break-inside: avoid; }\n" +
               "  table { page-break-inside: avoid; }\n" +
               "  h1, h2, h3, h4, h5, h6 { page-break-after: avoid; }\n" +
               "}\n" +
               "body {\n" +
               "  font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;\n" +
               "  font-size: 12px;\n" +
               "  line-height: 1.6;\n" +
               "  color: #333;\n" +
               "  margin: 0;\n" +
               "  padding: 20px;\n" +
               "}\n" +
               "h1, h2, h3, h4, h5, h6 {\n" +
               "  font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;\n" +
               "  font-weight: bold;\n" +
               "  margin: 20px 0 10px 0;\n" +
               "  page-break-after: avoid;\n" +
               "}\n" +
               "h1 { font-size: 24px; color: #2c3e50; }\n" +
               "h2 { font-size: 20px; color: #34495e; }\n" +
               "h3 { font-size: 18px; color: #7f8c8d; }\n" +
               "table {\n" +
               "  border-collapse: collapse;\n" +
               "  width: 100%;\n" +
               "  max-width: 100%;\n" +
               "  margin: 10px 0;\n" +
               "  page-break-inside: avoid;\n" +
               "  font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;\n" +
               "  table-layout: fixed;\n" +
               "}\n" +
               "th, td {\n" +
               "  border: 1px solid #ddd;\n" +
               "  padding: 8px;\n" +
               "  text-align: left;\n" +
               "  font-size: 11px;\n" +
               "  font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;\n" +
               "  word-wrap: break-word;\n" +
               "  min-width: 0;\n" +
               "}\n" +
               "th {\n" +
               "  background-color: #f2f2f2;\n" +
               "  font-weight: bold;\n" +
               "}\n" +
               "p {\n" +
               "  margin: 10px 0;\n" +
               "  text-align: justify;\n" +
               "  font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;\n" +
               "}\n" +
               ".chart-container {\n" +
               "  page-break-inside: avoid;\n" +
               "  margin: 20px 0;\n" +
               "  text-align: center;\n" +
               "}\n" +
               ".chart-container canvas,\n" +
               ".chart-container img {\n" +
               "  max-width: 100%;\n" +
               "  height: auto;\n" +
               "}\n" +
               ".no-print {\n" +
               "  display: none;\n" +
               "}\n" +
               ".page-break {\n" +
               "  page-break-before: always;\n" +
               "}\n" +
               "/* 强制所有元素使用中文字体 */\n" +
               "* {\n" +
               "  font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif !important;\n" +
               "}\n" +
               "</style>\n" +
               "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\"/>\n";
    }
    
    /**
     * 添加中文字体支持
     */
    private String addChineseFontSupportForIText7(String html) {
        // 使用更精确的正则表达式替换所有字体设置
        html = html.replaceAll("font-family\\s*:\\s*[^;\"}]*", "font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif");
        
        // 添加强制中文字体的样式
        String forceChineseStyle = "<style>\n" +
                                "@font-face {\n" +
                                "  font-family: 'SimSun';\n" +
                                "  src: local('SimSun'), local('宋体');\n" +
                                "}\n" +
                                "@font-face {\n" +
                                "  font-family: 'Microsoft YaHei';\n" +
                                "  src: local('Microsoft YaHei'), local('微软雅黑');\n" +
                                "}\n" +
                                "@font-face {\n" +
                                "  font-family: 'SimHei';\n" +
                                "  src: local('SimHei'), local('黑体');\n" +
                                "}\n" +
                                "body, div, span, p, h1, h2, h3, h4, h5, h6, table, th, td {\n" +
                                "  font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif !important;\n" +
                                "}\n" +
                                "</style>\n";
        
        if (html.contains("</head>")) {
            html = html.replace("</head>", forceChineseStyle + "</head>");
        }
        
        // 确保HTML头部有UTF-8编码声明
        if (!html.contains("charset=UTF-8")) {
            html = html.replace("<head>", 
                "<head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\"/>");
        }
        
        return html;
    }
    
    /**
     * 优化ECharts图表以适配PDF
     */
    private String optimizeEChartsForIText7(String html) {
        // 将canvas转换为img标签，确保图表能正确显示
        java.util.regex.Pattern canvasPattern = java.util.regex.Pattern.compile(
            "<canvas[^>]*id=[\"']([^\"']+)[\"'][^>]*></canvas>", 
            java.util.regex.Pattern.CASE_INSENSITIVE
        );
        
        java.util.regex.Matcher matcher = canvasPattern.matcher(html);
        StringBuffer result = new StringBuffer();
        
        while (matcher.find()) {
            String canvasId = matcher.group(1);
            // 将canvas转换为img标签，使用占位符图片
            String imgTag = "<div class='chart-container'><img src='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' alt='Chart " + canvasId + "' style='border: 1px solid #ddd;'/></div>";
            matcher.appendReplacement(result, imgTag);
        }
        matcher.appendTail(result);
        
        return result.toString();
    }
    
    /**
     * 添加打印样式
     */
    private String addPrintStylesForIText7(String html) {
        String printStyles = "<style type=\"text/css\" media=\"print\">\n" +
                             "body { font-family: 'SimSun', 'Microsoft YaHei', Arial, sans-serif !important; }\n" +
                             ".no-print { display: none !important; }\n" +
                             ".chart-container { page-break-inside: avoid !important; }\n" +
                             "table { page-break-inside: avoid !important; }\n" +
                             "h1, h2, h3, h4, h5, h6 { page-break-after: avoid !important; }\n" +
                             "</style>\n";
        
        if (html.contains("</head>")) {
            html = html.replace("</head>", printStyles + "</head>");
        }
        
        return html;
    }
    
    /**
     * 读取文件内容
     */
    private String readFileContent(Path file) throws IOException {
        StringBuilder content = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(file.toFile()), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                content.append(line).append("\n");
            }
        }
        return content.toString();
    }
    
    /**
     * 从HTML中提取纯文本内容
     */
    private String extractTextFromHtml(String html) {
        // 移除HTML标签
        String text = html.replaceAll("<[^>]*>", "");
        
        // 替换HTML实体
        text = text.replace("&nbsp;", " ")
                  .replace("&lt;", "<")
                  .replace("&gt;", ">")
                  .replace("&amp;", "&")
                  .replace("&quot;", "\"")
                  .replace("&#39;", "'")
                  .replace("&apos;", "'");
        
        // 移除多余的空白字符
        text = text.replaceAll("\\s+", " ").trim();
        
        return text;
    }

    /**
     * 打包并下载任务文件
     */
    public ResponseEntity<Resource> packageAndDownload(Long timestamp) throws Exception {
        try {
            // 获取任务信息
            RunTaskEntity task = queryTask(timestamp);
            if (task == null) {
                throw new RuntimeException("未找到指定的任务: " + timestamp);
            }
            
            // 获取关联规则信息
            AssociationRulesEntity associationRules = associationRulesService.queryRule(task.getRuleId());
            if (associationRules == null) {
                throw new RuntimeException("未找到关联规则: " + task.getRuleId());
            }
            
            // 获取任务目录
            Path taskDir = Paths.get("job", String.valueOf(timestamp));
            
            if (!Files.exists(taskDir)) {
                throw new RuntimeException("任务目录不存在: " + taskDir);
            }
            
            // 创建真正的临时目录
            Path tempDir = Files.createTempDirectory("task-download-");
            String zipFileName = String.format("task_%s_%d.zip", timestamp, System.currentTimeMillis());
            Path zipFile = tempDir.resolve(zipFileName);
            
            // 收集文件信息用于生成manifest
            List<Map<String, Object>> fileInfoList = new ArrayList<>();
            
            // 创建ZIP文件
            try (ZipOutputStream zipOut = new ZipOutputStream(Files.newOutputStream(zipFile))) {
                // 按目录结构组织文件到ZIP中
                Files.walk(taskDir)
                    .filter(path -> !Files.isDirectory(path))
                    .forEach(path -> {
                        try {
                            // 确定文件在ZIP中的路径
                            String relativePath = taskDir.relativize(path).toString().replace("\\", "/");
                            String zipEntryPath = categorizeFileForZip(relativePath, associationRules);
                            
                            ZipEntry zipEntry = new ZipEntry(zipEntryPath);
                            zipOut.putNextEntry(zipEntry);
                            
                            // 计算文件MD5
                            String md5 = calculateMD5(path);
                            long fileSize = Files.size(path);
                            String lastModified = new Date(Files.getLastModifiedTime(path).toMillis()).toString();
                            
                            // 收集文件信息
                            Map<String, Object> fileInfo = new HashMap<>();
                            fileInfo.put("fileName", zipEntryPath);
                            fileInfo.put("originalPath", relativePath);
                            fileInfo.put("fileSize", fileSize);
                            fileInfo.put("md5", md5);
                            fileInfo.put("lastModified", lastModified);
                            fileInfoList.add(fileInfo);
                            
                            Files.copy(path, zipOut);
                            zipOut.closeEntry();
                            
                            log.debug("已添加文件到ZIP: {} -> {} (MD5: {}, 大小: {} bytes)", relativePath, zipEntryPath, md5, fileSize);
                        } catch (Exception e) {
                            log.warn("跳过文件 {}: {}", path, e.getMessage());
                        }
                    });
                
                // 生成manifest.json
                Map<String, Object> manifest = new HashMap<>();
                manifest.put("exportTime", new Date().toString());
                manifest.put("exportedBy", AuthUtil.getCurrentUsername());
                manifest.put("taskTimestamp", timestamp);
                manifest.put("taskName", task.getName());
                manifest.put("taskStatus", task.getStatus());
                manifest.put("dataStartTime", task.getStartTime());
                manifest.put("dataEndTime", task.getEndTime());
                manifest.put("ruleName", task.getRuleName());
                manifest.put("algorithmName", task.getAlgorithmName());
                manifest.put("algorithmVersion", task.getAlgorithmVersion());
                manifest.put("totalFiles", fileInfoList.size());
                manifest.put("files", fileInfoList);
                
                // 将manifest转换为JSON字符串
                String manifestJson = generateManifestJson(manifest);
                
                // 添加manifest.json到ZIP根目录
                ZipEntry manifestEntry = new ZipEntry("manifest.json");
                zipOut.putNextEntry(manifestEntry);
                zipOut.write(manifestJson.getBytes(StandardCharsets.UTF_8));
                zipOut.closeEntry();
                
                log.info("已添加manifest.json到ZIP包，包含{}个文件信息", fileInfoList.size());
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

    /**
     * 根据关联规则信息确定文件在ZIP中的分类路径
     */
    private String categorizeFileForZip(String relativePath, AssociationRulesEntity associationRules) {
        String fileName = relativePath.substring(relativePath.lastIndexOf('/') + 1);
        
        // 1. 输入数据文件 - 根据inputCsvName确定
        if (associationRules.getInputCsvName() != null && fileName.equals(associationRules.getInputCsvName())) {
            return "data/" + relativePath;
        }
        
        // 2. 输出结果文件 - 根据outputCsvName确定
        if (associationRules.getOutputCsvName() != null && fileName.equals(associationRules.getOutputCsvName())) {
            return "result/" + relativePath;
        }
        
        // 3. 代码生成的结果文件 - _bind.csv文件
        if (associationRules.getOutputCsvName() != null) {
            String outputBindName = associationRules.getOutputCsvName().replace(".csv", "_bind.csv");
            if (fileName.equals(outputBindName)) {
                return "result/" + relativePath;
            }
        }
        
        // 4. 日志文件 - task.log
        if (fileName.equals("task.log")) {
            return "result/" + relativePath;
        }
        
        // 5. 报告文件 - .html, .pdf文件
        if (fileName.toLowerCase().endsWith(".html") || fileName.toLowerCase().endsWith(".pdf")) {
            return "result/" + relativePath;
        }
        
        // 6. 剩余所有文件都归类为模型文件
        return "model/" + relativePath;
    }

    /**
     * 计算文件的MD5校验码
     */
    private String calculateMD5(Path file) throws Exception {
        java.security.MessageDigest md = java.security.MessageDigest.getInstance("MD5");
        
        try (FileInputStream fis = new FileInputStream(file.toFile())) {
            byte[] buffer = new byte[8192];
            int bytesRead;
            
            while ((bytesRead = fis.read(buffer)) != -1) {
                md.update(buffer, 0, bytesRead);
            }
        }
        
        byte[] digest = md.digest();
        
        // 将字节数组转换为十六进制字符串
        StringBuilder sb = new StringBuilder();
        for (byte b : digest) {
            sb.append(String.format("%02x", b));
        }
        
        return sb.toString();
    }

    /**
     * 生成manifest JSON字符串
     */
    private String generateManifestJson(Map<String, Object> manifest) {
        StringBuilder json = new StringBuilder();
        json.append("{\n");
        
        boolean first = true;
        for (Map.Entry<String, Object> entry : manifest.entrySet()) {
            if (!first) {
                json.append(",\n");
            }
            first = false;
            
            json.append("  \"").append(entry.getKey()).append("\": ");
            Object value = entry.getValue();
            
            if (value instanceof String) {
                json.append("\"").append(escapeJson((String) value)).append("\"");
            } else if (value instanceof List) {
                json.append(generateJsonArray((List<?>) value));
            } else {
                json.append("\"").append(value != null ? value.toString() : "").append("\"");
            }
        }
        
        json.append("\n}");
        return json.toString();
    }
    
    /**
     * 生成JSON数组
     */
    private String generateJsonArray(List<?> list) {
        StringBuilder array = new StringBuilder();
        array.append("[\n");
        
        for (int i = 0; i < list.size(); i++) {
            if (i > 0) {
                array.append(",\n");
            }
            
            Object item = list.get(i);
            if (item instanceof Map) {
                array.append(generateJsonObject((Map<?, ?>) item, 4)); // 4个空格缩进
            } else {
                array.append("\"").append(item != null ? item.toString() : "").append("\"");
            }
        }
        
        array.append("\n]");
        return array.toString();
    }
    
    /**
     * 生成JSON对象
     */
    private String generateJsonObject(Map<?, ?> map, int indent) {
        StringBuilder obj = new StringBuilder();
        String indentStr = repeatString(" ", indent);
        String indentStr2 = repeatString(" ", indent + 2);
        
        obj.append("{\n");
        
        boolean first = true;
        for (Map.Entry<?, ?> entry : map.entrySet()) {
            if (!first) {
                obj.append(",\n");
            }
            first = false;
            
            obj.append(indentStr2).append("\"").append(entry.getKey()).append("\": ");
            Object value = entry.getValue();
            
            if (value instanceof String) {
                obj.append("\"").append(escapeJson((String) value)).append("\"");
            } else {
                obj.append("\"").append(value != null ? value.toString() : "").append("\"");
            }
        }
        
        obj.append("\n").append(indentStr).append("}");
        return obj.toString();
    }
    
    /**
     * 重复字符串（Java 8兼容版本）
     */
    private String repeatString(String str, int count) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < count; i++) {
            sb.append(str);
        }
        return sb.toString();
    }
    
    /**
     * 转义JSON字符串中的特殊字符
     */
    private String escapeJson(String str) {
        if (str == null) {
            return "";
        }
        
        return str.replace("\\", "\\\\")
                  .replace("\"", "\\\"")
                  .replace("\n", "\\n")
                  .replace("\r", "\\r")
                  .replace("\t", "\\t");
    }
    
    /**
     * 检查指定规则是否有正在运行的任务
     * @param ruleId 规则ID
     * @return true如果有正在运行的任务，false如果没有
     */
    public boolean hasRunningTaskForRule(Long ruleId) {
        try {
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM relational_system.association_job WHERE ruleId = ");
            sql.append(ruleId).append(" AND (status = 'pending' OR status = 'running');");
            log.info("检查规则运行状态SQL: {}, ruleId: {}", sql, ruleId);
            
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());

            List<List<Object>> data = res.getValues();
            if (!data.isEmpty() && !data.get(0).isEmpty()) {
                Object countObj = data.get(0).get(0);
                if (countObj instanceof Number) {
                    int count = ((Number) countObj).intValue();
                    return count > 0;
                }
            }
            return false;
        } catch (Exception e) {
            log.error("检查规则运行状态失败", e);
            return false;
        }
    }

    /**
     * 获取数据表的时间范围（最小和最大key值）
     * @param request 时间范围查询请求
     * @return 时间范围响应
     */
    public TimeRangeResponse getTimeRange(TimeRangeRequest request) throws Exception {
        TimeRangeResponse response = new TimeRangeResponse();

        String tableName = request.getTableName();
        List<String> fieldList = request.getInputsBind().stream().map(InputBindDto::getSourceField).collect(Collectors.toList());
        String field = CollectionUtils.isEmpty(fieldList)? "*" : StringUtils.collectionToCommaDelimitedString(fieldList);
        log.info("查询数据表时间范围,数据表: {},字段: {},", tableName,field);

        // 构建SQL查询获取最小和最大时间戳
        String minSql = "SELECT %s FROM %s where 1=1 limit 1;";

        SessionExecuteSqlResult minResult = iginxSession.executeSql(String.format(minSql, field, tableName));
        Long minKey = minResult.getKeys()[0];

        String maxSql = "SELECT %s FROM %s where 1=1 order by key desc limit 1;";
        SessionExecuteSqlResult maxResult = iginxSession.executeSql(String.format(maxSql, field, tableName));
        Long maxKey = maxResult.getKeys()[0];

        response.setMinKey(minKey);
        response.setMaxKey(maxKey);
        log.info("时间范围查询结果: minKey={}, maxKey={}", minKey, maxKey);
        
        return response;
    }

}
