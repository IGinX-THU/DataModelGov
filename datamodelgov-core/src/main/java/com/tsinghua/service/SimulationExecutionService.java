package com.tsinghua.service;

import com.tsinghua.entity.SimulationArchiveEntity;
import com.tsinghua.entity.SimulationExecutionEntity;
import com.tsinghua.model.Result;
import com.tsinghua.util.ConvertUtil;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import cn.edu.tsinghua.iginx.session_v2.query.*;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsinghua.dto.InputBindDto;
import com.tsinghua.dto.OutputBindDto;
import com.tsinghua.entity.AlgorithmMetaEntity;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.scheduling.support.CronExpression;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * 仿真执行服务
 * 负责管理仿真的运行和调度
 * 支持全量执行、选择性执行、时间窗口覆盖、定期运行
 */
@Slf4j
@Service
public class SimulationExecutionService {

    @Autowired
    private SimulationArchiveService simulationArchiveService;

    @Autowired
    private DirectedGraphExecutionEngine executionEngine;

    @Autowired
    private OutputApiSenderService outputApiSenderService;

    @Autowired
    private AlgorithmExecutionService algorithmExecutionService;

    @Autowired
    private ApiOutputSenderService apiOutputSenderService;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private Session iginxSession;

    @Autowired
    private AlgorithmFileService algorithmFileService;

    private static final String DATA_PREFIX = "relational_system.simulation_job";

    // 存储正在运行的仿真任务
    private final Map<Long, SimulationExecutionEntity> runningSimulations = new ConcurrentHashMap<>();

    /**
     * 运行仿真（全量执行）
     */
    public Result<Void> runSimulation(Long createTime) {
        return runSimulation(createTime, null);
    }

    /**
     * 运行仿真（支持选择性执行，每个节点使用自己的时间窗口）
     * @param createTime 仿真档案创建时间（作为ID）
     * @param selectedNodeIds 选中的节点ID列表（null表示全量执行）
     */
    public Result<Void> runSimulation(Long createTime, List<String> selectedNodeIds) {
        try {
            SimulationArchiveEntity archive = simulationArchiveService.queryArchive(createTime);
            if (archive == null) {
                return Result.error("仿真档案不存在");
            }

            if (archive.getIsRunning() != null && archive.getIsRunning()) {
                return Result.error("仿真正在运行中");
            }

            // 标记为运行中
            archive.setIsRunning(true);
            archive.setLastExecutionTime(System.currentTimeMillis());
            simulationArchiveService.saveArchive(archive);

            // 创建执行记录
            SimulationExecutionEntity execution = new SimulationExecutionEntity();
            execution.setTimestamp(System.currentTimeMillis());
            execution.setArchiveId(createTime);
            execution.setArchiveName(archive.getName());
            execution.setStartTime(System.currentTimeMillis());
            execution.setStatus("running");
            runningSimulations.put(execution.getTimestamp(), execution);

            // 异步执行仿真
            new Thread(() -> {
                try {
                    Map<String, Object> executionResult = executionEngine.executeGraph(
                        archive, selectedNodeIds, archive.getProjectName());

                    // 更新执行状态
                    execution.setEndTime(System.currentTimeMillis());
                    execution.setStatus(Boolean.TRUE.equals(executionResult.get("success")) ? "completed" : "failed");
                    execution.setResult(executionResult);

                    // 提取首节点输入路径和末节点输出路径（用于分析时查询IginX数据）
                    extractMeasurementsFromGraph(archive, executionResult, execution);

                    // 保存执行记录（包含新提取的测点路径）
                    saveExecution(execution);

                    // 更新档案信息
                    archive.setIsRunning(false);
                    archive.setExecutionCount((archive.getExecutionCount() == null ? 0 : archive.getExecutionCount()) + 1);
                    simulationArchiveService.saveArchive(archive);

                    // 如果配置了输出API，发送结果（JSON格式）
                    if (archive.getOutputApiConfig() != null && !archive.getOutputApiConfig().isEmpty()) {
                        try {
                            // 构建简单的JSON结果：包含节点信息和CSV文本
                            Map<String, Object> apiResult = new HashMap<>();
                            apiResult.put("archiveName", archive.getName());
                            apiResult.put("createTime", archive.getCreateTime());
                            apiResult.put("timestamp", System.currentTimeMillis());

                            // 提取节点CSV结果，直接作为字符串数组
                            List<String> dataList = new ArrayList<>();
                            if (executionResult.containsKey("results")) {
                                Map<String, Object> results = (Map<String, Object>) executionResult.get("results");
                                for (Map.Entry<String, Object> entry : results.entrySet()) {
                                    Map<String, Object> nodeResult = (Map<String, Object>) entry.getValue();
                                    if (nodeResult.containsKey("outputCsv")) {
                                        String nodeCsv = (String) nodeResult.get("outputCsv");
                                        if (nodeCsv != null && !nodeCsv.isEmpty()) {
                                            dataList.add(nodeCsv);
                                        }
                                    }
                                }
                            }
                            apiResult.put("data", dataList);

                            boolean sent = outputApiSenderService.sendResult(archive.getOutputApiConfig(), apiResult);
                            log.info("输出API发送结果: {}", sent ? "成功" : "失败");
                        } catch (Exception apiEx) {
                            log.error("输出API发送失败", apiEx);
                        }
                    }

                    // 保存执行记录到数据库
                    saveExecution(execution);

                    log.info("仿真执行完成: {}", createTime);
                } catch (Exception e) {
                    log.error("仿真执行失败: {}", createTime, e);
                    execution.setEndTime(System.currentTimeMillis());
                    execution.setStatus("failed");
                    execution.setError(e.getMessage());

                    archive.setIsRunning(false);
                    try {
                        simulationArchiveService.saveArchive(archive);
                    } catch (Exception saveEx) {
                        log.error("保存档案状态失败", saveEx);
                    }

                    // 保存执行记录到数据库
                    saveExecution(execution);
                }
            }).start();

            return Result.success("仿真已开始运行");

        } catch (Exception e) {
            log.error("运行仿真失败", e);
            return Result.error("运行失败: " + e.getMessage());
        }
    }

    /**
     * 停止仿真
     */
    public Result<Void> stopSimulation(Long createTime) {
        try {
            SimulationArchiveEntity archive = simulationArchiveService.queryArchive(createTime);
            if (archive == null) {
                return Result.error("仿真档案不存在");
            }

            if (archive.getIsRunning() == null || !archive.getIsRunning()) {
                return Result.error("仿真未在运行中");
            }

            // 停止执行引擎
            executionEngine.stopExecution();

            // 更新档案状态
            archive.setIsRunning(false);
            simulationArchiveService.saveArchive(archive);

            // 移除运行中的记录
            runningSimulations.remove(createTime);

            return Result.success("仿真已停止");

        } catch (Exception e) {
            log.error("停止仿真失败", e);
            return Result.error("停止失败: " + e.getMessage());
        }
    }

    /**
     * 获取仿真执行状态
     */
    public Result<Map<String, Object>> getExecutionStatus(Long createTime) {
        try {
            SimulationArchiveEntity archive = simulationArchiveService.queryArchive(createTime);
            if (archive == null) {
                Map<String, Object> errorData = new HashMap<>();
                errorData.put("error", "仿真档案不存在");
                return Result.success(errorData);
            }

            // 查找最新的执行记录
            SimulationExecutionEntity execution = null;
            for (SimulationExecutionEntity running : runningSimulations.values()) {
                if (running.getArchiveId().equals(createTime)) {
                    execution = running;
                    break;
                }
            }

            // 如果内存中没有，尝试从数据库加载最新的执行记录
            if (execution == null) {
                List<SimulationExecutionEntity> executions = queryExecutions(
                    archive.getName(), null, null, null, 1, 1);
                if (executions != null && !executions.isEmpty()) {
                    execution = executions.get(0);
                }
            }

            Map<String, Object> data = new HashMap<>();
            data.put("isRunning", archive.getIsRunning() != null && archive.getIsRunning());
            data.put("lastExecutionTime", archive.getLastExecutionTime());
            data.put("executionCount", archive.getExecutionCount());
            data.put("execution", execution);

            return Result.success(data);

        } catch (Exception e) {
            log.error("获取执行状态失败", e);
            Map<String, Object> errorData = new HashMap<>();
            errorData.put("error", "获取失败: " + e.getMessage());
            return Result.success(errorData);
        }
    }

    /**
     * 获取仿真执行日志
     */
    public Result<Map<String, Object>> getExecutionLog(Long timestamp) {
        try {
            SimulationExecutionEntity execution = null;
            
            // 如果内存中有，直接使用
            if (runningSimulations.containsKey(timestamp)) {
                execution = runningSimulations.get(timestamp);
            } else {
                // 否则从数据库加载
                execution = loadExecution(timestamp);
            }

            Map<String, Object> data = new HashMap<>();

            if (execution != null && execution.getResult() instanceof Map) {
                Map<String, Object> result = (Map<String, Object>) execution.getResult();
                Map<String, Object> results = (Map<String, Object>) result.get("results");
                if (results != null) {
                    Map<String, String> nodeLogs = new LinkedHashMap<>();
                    for (Map.Entry<String, Object> entry : results.entrySet()) {
                        if (entry.getValue() instanceof Map) {
                            Map<String, Object> nodeResult = (Map<String, Object>) entry.getValue();
                            String processLog = (String) nodeResult.getOrDefault("processLog", "");
                            String error = (String) nodeResult.getOrDefault("error", "");
                            String log = processLog;
                            if (error != null && !error.isEmpty()) {
                                log += "\n错误: " + error;
                            }
                            nodeLogs.put(entry.getKey(), log);
                        }
                    }
                    data.put("nodeLogs", nodeLogs);
                    data.put("status", execution.getStatus());
                }
            } else {
                data.put("status", "unknown");
                data.put("nodeLogs", new HashMap<>());
            }

            return Result.success(data);
        } catch (Exception e) {
            log.error("获取执行日志失败", e);
            return new Result<>(500, "获取执行日志失败: " + e.getMessage(), null);
        }
    }

    /**
     * 定时任务：检查并执行定时仿真
     * 每分钟检查一次，根据cron表达式判断是否需要执行
     * 只查询 status=true 的档案进行调度
     */
    @Scheduled(cron = "0 * * * * ?")
    public void checkScheduledSimulations() {
        try {
            // 查询所有启用状态（status=true）的仿真档案
            List<SimulationArchiveEntity> archives = simulationArchiveService.queryArchives(
                null, null, null, true, 1, 1000);

            if (archives == null || archives.isEmpty()) return;

            LocalDateTime now = LocalDateTime.now();

            for (SimulationArchiveEntity archive : archives) {
                // 跳过正在运行的
                if (archive.getIsRunning() != null && archive.getIsRunning()) continue;

                // 检查cron表达式
                String scheduleCron = archive.getScheduleCron();
                if (scheduleCron == null || scheduleCron.trim().isEmpty()) continue;

                try {
                    CronExpression cronExpression = CronExpression.parse(scheduleCron);
                    LocalDateTime nextExecution = cronExpression.next(now.minusMinutes(1));
                    if (nextExecution != null && !nextExecution.isAfter(now)) {
                        log.info("定时触发仿真: {} (cron: {})", archive.getName(), scheduleCron);
                        runSimulation(archive.getCreateTime());
                    }
                } catch (Exception e) {
                    log.warn("解析cron表达式失败: {} - {}", scheduleCron, e.getMessage());
                }
            }
        } catch (Exception e) {
            log.error("检查定时仿真失败", e);
        }
    }

    /**
     * 分页查询仿真执行记录
     */
    public List<SimulationExecutionEntity> queryExecutions(String archiveName, String status, Long startTime, Long endTime, int pageNum, int pageSize) {
        try {
            StringBuilder sql = new StringBuilder("SELECT * FROM " + DATA_PREFIX + " WHERE 1=1");

            if (archiveName != null && !archiveName.trim().isEmpty()) {
                sql.append(" AND archiveName LIKE '^.*").append(archiveName.trim()).append(".*'");
            }
            if (status != null && !status.trim().isEmpty()) {
                sql.append(" AND status = '").append(status.trim()).append("'");
            }
            if (startTime != null) {
                sql.append(" AND startTime >= ").append(startTime);
            }
            if (endTime != null) {
                sql.append(" AND startTime <= ").append(endTime);
            }

            sql.append(" ORDER BY timestamp DESC");
            sql.append(" LIMIT ").append(pageSize);
            sql.append(" OFFSET ").append((pageNum - 1) * pageSize);
            sql.append(";");

            log.info("查询仿真执行记录SQL: {}", sql);

            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            List<SimulationExecutionEntity> result = records.stream().map(record -> {
                SimulationExecutionEntity entity = new SimulationExecutionEntity();
                record.forEach((k, v) -> {
                    String fieldName = k.substring(k.lastIndexOf('.') + 1);
                    ConvertUtil.setEntityField(entity, DATA_PREFIX, fieldName, v);
                });
                return entity;
            }).collect(Collectors.toList());

            log.info("查询仿真执行记录结果: records={}", result.size());
            return result;
        } catch (Exception e) {
            log.error("查询仿真执行记录失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 查询仿真执行记录总数
     */
    public long countExecutions(String archiveName, String status, Long startTime, Long endTime) {
        try {
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM " + DATA_PREFIX + " WHERE 1=1");

            if (archiveName != null && !archiveName.trim().isEmpty()) {
                sql.append(" AND archiveName LIKE '%").append(archiveName.trim()).append("%'");
            }
            if (status != null && !status.trim().isEmpty()) {
                sql.append(" AND status = '").append(status.trim()).append("'");
            }
            if (startTime != null) {
                sql.append(" AND startTime >= ").append(startTime);
            }
            if (endTime != null) {
                sql.append(" AND startTime <= ").append(endTime);
            }
            sql.append(";");

            log.info("统计仿真执行记录SQL: {}", sql);

            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            if (records != null && !records.isEmpty()) {
                Map<String, Object> first = records.get(0);
                for (Object v : first.values()) {
                    if (v instanceof Number) return ((Number) v).longValue();
                }
            }
            return 0;
        } catch (Exception e) {
            log.error("统计仿真执行记录失败", e);
            return 0;
        }
    }

    /**
     * 保存仿真执行记录到IginX
     */
    private void saveExecution(SimulationExecutionEntity execution) {
        try {
            List<Point> points = new ArrayList<>();
            long timestamp = execution.getTimestamp();

            String basePath = DATA_PREFIX;

            points.add(ConvertUtil.createFieldPoint(basePath, "timestamp", execution.getTimestamp(), timestamp));
            points.add(ConvertUtil.createFieldPoint(basePath, "archiveId", execution.getArchiveId(), timestamp));
            points.add(ConvertUtil.createFieldPoint(basePath, "archiveName", execution.getArchiveName(), timestamp));
            points.add(ConvertUtil.createFieldPoint(basePath, "startTime", execution.getStartTime(), timestamp));
            points.add(ConvertUtil.createFieldPoint(basePath, "endTime", execution.getEndTime(), timestamp));
            points.add(ConvertUtil.createFieldPoint(basePath, "status", execution.getStatus(), timestamp));
            points.add(ConvertUtil.createFieldPoint(basePath, "error", execution.getError(), timestamp));
            points.add(ConvertUtil.createFieldPoint(basePath, "inputMeasurements", execution.getInputMeasurements(), timestamp));
            points.add(ConvertUtil.createFieldPoint(basePath, "outputMeasurements", execution.getOutputMeasurements(), timestamp));
            points.add(ConvertUtil.createFieldPoint(basePath, "outputTable", execution.getOutputTable(), timestamp));
            points.add(ConvertUtil.createFieldPoint(basePath, "processLog", execution.getProcessLog(), timestamp));

            // 保存result为JSON字符串
            if (execution.getResult() != null) {
                String resultJson = JSON.toJSONString(execution.getResult());
                points.add(ConvertUtil.createFieldPoint(basePath, "result", resultJson, timestamp));
            }

            iginxClient.getWriteClient().writePoints(points.stream().filter(Objects::nonNull).collect(Collectors.toList()));
            log.info("仿真执行记录已保存: timestamp={}, archiveId={}", execution.getTimestamp(), execution.getArchiveId());
        } catch (Exception e) {
            log.error("保存仿真执行记录失败", e);
        }
    }

    /**
     * 从有向图中提取首节点输入测点路径和末节点输出测点路径
     * 参考RunTaskService.runTask中从AssociationRulesEntity提取inputMeasurements/outputMeasurements的模式
     */
    private void extractMeasurementsFromGraph(SimulationArchiveEntity archive, Map<String, Object> executionResult, SimulationExecutionEntity execution) {
        try {
            String graphJson = archive.getGraphJson();
            if (graphJson == null || graphJson.isEmpty()) return;

            ObjectMapper objectMapper = new ObjectMapper();
            JsonNode graphNode = objectMapper.readTree(graphJson);
            JsonNode nodes = graphNode.get("nodes");
            JsonNode edges = graphNode.get("edges");

            if (nodes == null || !nodes.isArray() || nodes.size() == 0) return;

            // 构建节点映射
            Map<String, JsonNode> nodeMap = new LinkedHashMap<>();
            for (JsonNode node : nodes) {
                String nodeId = node.get("nodeId").asText();
                nodeMap.put(nodeId, node);
            }

            // 构建邻接表，找出入度为0的节点（首节点）和出度为0的节点（末节点）
            Map<String, List<String>> adjacencyList = new HashMap<>();
            Map<String, Integer> inDegree = new HashMap<>();
            for (String nodeId : nodeMap.keySet()) {
                adjacencyList.put(nodeId, new ArrayList<>());
                inDegree.put(nodeId, 0);
            }

            if (edges != null && edges.isArray()) {
                for (JsonNode edge : edges) {
                    String sourceId = edge.get("sourceNodeId").asText();
                    String targetId = edge.get("targetNodeId").asText();
                    if (nodeMap.containsKey(sourceId) && nodeMap.containsKey(targetId)) {
                        adjacencyList.get(sourceId).add(targetId);
                        inDegree.put(targetId, inDegree.get(targetId) + 1);
                    }
                }
            }

            // 找首节点（入度为0）和末节点（出度为0）
            String firstNodeId = null;
            String lastNodeId = null;
            for (String nodeId : nodeMap.keySet()) {
                if (inDegree.get(nodeId) == 0) {
                    firstNodeId = nodeId;
                }
                if (adjacencyList.get(nodeId).isEmpty()) {
                    lastNodeId = nodeId;
                }
            }

            // 提取首节点的输入测点路径和时间范围
            if (firstNodeId != null) {
                JsonNode firstNode = nodeMap.get(firstNodeId);
                String algorithmName = firstNode.has("algorithmName") ? firstNode.get("algorithmName").asText() : "";
                String algorithmVersion = firstNode.has("algorithmVersion") ? firstNode.get("algorithmVersion").asText() : "";

                // 使用节点配置的时间范围
                if (firstNode.has("startTime") && firstNode.has("endTime")) {
                    execution.setStartTime(firstNode.get("startTime").asLong());
                    execution.setEndTime(firstNode.get("endTime").asLong());
                    log.info("从首节点配置提取时间范围: {} - {}", execution.getStartTime(), execution.getEndTime());
                }

                if (!algorithmName.isEmpty() && !algorithmVersion.isEmpty()) {
                    AlgorithmMetaEntity algorithmMeta = algorithmFileService.queryMeta(algorithmName, algorithmVersion);
                    if (algorithmMeta != null) {
                        // 优先使用 inputData（数据源字段全路径）
                        if (algorithmMeta.getInputData() != null && !algorithmMeta.getInputData().isEmpty()) {
                            execution.setInputMeasurements(algorithmMeta.getInputData());
                        }
                        // 如果有 inputsBind，构建完整路径
                        else if (algorithmMeta.getInputsBind() != null && !algorithmMeta.getInputsBind().isEmpty()
                            && algorithmMeta.getTableName() != null) {
                            List<InputBindDto> inputs = JSON.parseArray(algorithmMeta.getInputsBind(), InputBindDto.class);
                            List<String> inputPaths = inputs.stream().map(inputBindDto ->
                                String.format("%s.%s", algorithmMeta.getTableName(), inputBindDto.getSourceField()))
                                .collect(Collectors.toList());
                            execution.setInputMeasurements(JSONArray.toJSONString(inputPaths));
                        }
                    }
                }
            }

            // 提取末节点的输出测点路径
            if (lastNodeId != null) {
                JsonNode lastNode = nodeMap.get(lastNodeId);
                String algorithmName = lastNode.has("algorithmName") ? lastNode.get("algorithmName").asText() : "";
                String algorithmVersion = lastNode.has("algorithmVersion") ? lastNode.get("algorithmVersion").asText() : "";

                if (!algorithmName.isEmpty() && !algorithmVersion.isEmpty()) {
                    AlgorithmMetaEntity algorithmMeta = algorithmFileService.queryMeta(algorithmName, algorithmVersion);
                    if (algorithmMeta != null) {
                        // 设置输出表
                        if (algorithmMeta.getOutputTable() != null && !algorithmMeta.getOutputTable().isEmpty()) {
                            execution.setOutputTable(algorithmMeta.getOutputTable());
                        }

                        // 构建输出测点路径
                        if (algorithmMeta.getOutputsBind() != null && !algorithmMeta.getOutputsBind().isEmpty()
                            && algorithmMeta.getOutputTable() != null) {
                            List<OutputBindDto> outputs = JSON.parseArray(algorithmMeta.getOutputsBind(), OutputBindDto.class);
                            List<String> outputPaths = outputs.stream()
                                .map(outputBindDto -> String.format("%s.%s", algorithmMeta.getOutputTable(), outputBindDto.getResultTarget()))
                                .collect(Collectors.toList());
                            execution.setOutputMeasurements(JSONArray.toJSONString(outputPaths));
                        }
                    }
                }
            }

        } catch (Exception e) {
            log.error("提取测点路径失败", e);
        }
    }

    /**
     * 从IginX加载仿真执行记录
     */
    private SimulationExecutionEntity loadExecution(Long timestamp) {
        try {
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(SimulationExecutionEntity.class, DATA_PREFIX);

            IginXTable table = iginxClient.getQueryClient().query(
                SimpleQuery.builder()
                    .addMeasurements(new HashSet<>(measurements))
                    .startKey(timestamp)
                    .endKey(timestamp + 1)
                    .build()
            );

            log.info("Query result: table={}, records={}", table != null, table != null && table.getRecords() != null ? table.getRecords().size() : 0);

            if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) {
                log.warn("No execution records found for timestamp: {}", timestamp);
                return null;
            }

            SimulationExecutionEntity execution = new SimulationExecutionEntity();
            execution.setTimestamp(timestamp);

            // Get the first record's values
            IginXRecord record = table.getRecords().get(0);
            for (String path : measurements) {
                Object value = record.getValue(path);
                log.debug("Path: {}, Value: {}", path, value);
                if (value != null) {
                    String fieldName = path.substring(path.lastIndexOf('.') + 1);
                    // Convert byte[] to String if needed
                    String strValue = value instanceof byte[] ? ConvertUtil.bytesToString((byte[]) value) : value.toString();
                    switch (fieldName) {
                        case "archiveId":
                            execution.setArchiveId(value instanceof Number ? ((Number) value).longValue() : null);
                            break;
                        case "archiveName":
                            execution.setArchiveName(strValue);
                            break;
                        case "startTime":
                            execution.setStartTime(value instanceof Number ? ((Number) value).longValue() : null);
                            break;
                        case "endTime":
                            execution.setEndTime(value instanceof Number ? ((Number) value).longValue() : null);
                            break;
                        case "status":
                            execution.setStatus(strValue);
                            break;
                        case "error":
                            execution.setError(strValue);
                            break;
                        case "inputMeasurements":
                            execution.setInputMeasurements(strValue);
                            break;
                        case "outputMeasurements":
                            execution.setOutputMeasurements(strValue);
                            break;
                        case "outputTable":
                            execution.setOutputTable(strValue);
                            break;
                        case "processLog":
                            execution.setProcessLog(strValue);
                            break;
                        case "result":
                            try {
                                execution.setResult(JSON.parseObject(strValue));
                            } catch (Exception e) {
                                log.warn("解析result JSON失败", e);
                            }
                            break;
                    }
                }
            }

            log.info("Loaded execution: timestamp={}, archiveName={}, status={}", execution.getTimestamp(), execution.getArchiveName(), execution.getStatus());
            return execution;
        } catch (Exception e) {
            log.error("加载仿真执行记录失败", e);
            return null;
        }
    }

    /**
     * 删除仿真执行记录
     */
    public void deleteExecution(Long timestamp) {
        try {
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(SimulationExecutionEntity.class, DATA_PREFIX);
            
            // 从IginX删除执行记录
            iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp - 1, timestamp + 1);
            
            log.info("仿真执行记录已删除: timestamp={}", timestamp);
        } catch (Exception e) {
            log.error("删除仿真执行记录失败", e);
            throw new RuntimeException("删除失败: " + e.getMessage(), e);
        }
    }
}
