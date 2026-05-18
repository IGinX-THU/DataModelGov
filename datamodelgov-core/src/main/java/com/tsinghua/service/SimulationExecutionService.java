package com.tsinghua.service;

import com.tsinghua.entity.SimulationArchiveEntity;
import com.tsinghua.entity.SimulationExecutionEntity;
import com.tsinghua.model.Result;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 仿真执行服务
 * 负责管理仿真的运行和调度
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
     * 运行仿真
     */
    public Result<Void> runSimulation(Long createTime) {
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
                    Map<String, Object> executionResult = executionEngine.executeGraph(archive);
                    
                    // 更新执行状态
                    execution.setEndTime(System.currentTimeMillis());
                    execution.setStatus((Boolean) executionResult.get("success") ? "completed" : "failed");
                    execution.setResult(executionResult);
                    
                    // 更新档案信息
                    archive.setIsRunning(false);
                    archive.setExecutionCount((archive.getExecutionCount() == null ? 0 : archive.getExecutionCount()) + 1);
                    simulationArchiveService.saveArchive(archive);

                    // 如果配置了输出API，发送结果
                    if (archive.getOutputApiConfig() != null && !archive.getOutputApiConfig().isEmpty()) {
                        Map<String, Object> apiConfig = apiOutputSenderService.parseApiConfig(archive.getOutputApiConfig());
                        String apiUrl = apiOutputSenderService.extractApiUrl(apiConfig);
                        Map<String, String> headers = apiOutputSenderService.extractHeaders(apiConfig);
                        
                        if (apiUrl != null) {
                            apiOutputSenderService.sendOutput(apiUrl, executionResult, headers);
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
                } finally {
                    runningSimulations.remove(createTime);
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

            return Result.success(data);

        } catch (Exception e) {
            log.error("获取执行状态失败", e);
            Map<String, Object> errorData = new HashMap<>();
            errorData.put("error", "获取失败: " + e.getMessage());
            return Result.success(errorData);
        }
    }

    /**
     * 定时任务：检查并执行定时仿真
     */
    @Scheduled(cron = "0 * * * * ?") // 每分钟检查一次
    public void checkScheduledSimulations() {
        try {
            // TODO: 查询所有启用了定时调度的仿真档案
            // 根据cron表达式判断是否需要执行
            log.debug("检查定时仿真任务");
        } catch (Exception e) {
            log.error("检查定时仿真失败", e);
        }
    }
}
