package com.tsinghua.service;

import com.tsinghua.entity.SimulationArchiveEntity;
import com.tsinghua.entity.SimulationExecutionEntity;
import com.tsinghua.model.Result;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.scheduling.support.CronExpression;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

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
            execution.setArchiveId(createTime);
            execution.setStartTime(System.currentTimeMillis());
            execution.setStatus("running");
            runningSimulations.put(createTime, execution);

            // 异步执行仿真
            new Thread(() -> {
                try {
                    Map<String, Object> executionResult = executionEngine.executeGraph(
                        archive, selectedNodeIds, archive.getProjectName());

                    // 更新执行状态
                    execution.setEndTime(System.currentTimeMillis());
                    execution.setStatus(Boolean.TRUE.equals(executionResult.get("success")) ? "completed" : "failed");
                    execution.setResult(executionResult);

                    // 更新档案信息
                    archive.setIsRunning(false);
                    archive.setExecutionCount((archive.getExecutionCount() == null ? 0 : archive.getExecutionCount()) + 1);
                    simulationArchiveService.saveArchive(archive);

                    // 如果配置了输出API，发送结果
                    if (archive.getOutputApiConfig() != null && !archive.getOutputApiConfig().isEmpty()) {
                        try {
                            boolean sent = outputApiSenderService.sendResult(archive.getOutputApiConfig(), executionResult);
                            log.info("输出API发送结果: {}", sent ? "成功" : "失败");
                        } catch (Exception apiEx) {
                            log.error("输出API发送失败", apiEx);
                        }
                    }

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

            SimulationExecutionEntity execution = runningSimulations.get(createTime);

            Map<String, Object> data = new HashMap<>();
            data.put("isRunning", archive.getIsRunning() != null && archive.getIsRunning());
            data.put("lastExecutionTime", archive.getLastExecutionTime());
            data.put("executionCount", archive.getExecutionCount());
            data.put("execution", execution);

            // 如果执行完成，包含结果数据
            if (execution != null && execution.getResult() instanceof Map) {
                data.put("result", execution.getResult());
            }

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
    public Result<Map<String, Object>> getExecutionLog(Long createTime) {
        try {
            SimulationExecutionEntity execution = runningSimulations.get(createTime);
            Map<String, Object> data = new HashMap<>();

            if (execution != null && execution.getResult() instanceof Map) {
                Map<String, Object> result = (Map<String, Object>) execution.getResult();
                Map<String, Object> results = (Map<String, Object>) result.get("results");
                if (results != null) {
                    Map<String, String> nodeLogs = new HashMap<>();
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
     */
    @Scheduled(cron = "0 * * * * ?")
    public void checkScheduledSimulations() {
        try {
            // 查询所有启用了定时调度的仿真档案
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
}
