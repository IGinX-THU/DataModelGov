package com.tsinghua.service;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsinghua.entity.AlgorithmMetaEntity;
import com.tsinghua.entity.SimulationArchiveEntity;
import com.tsinghua.model.Result;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 有向图执行引擎
 * 用于执行仿真档案中的有向图
 * 所有节点均为算法任务节点，按拓扑排序顺序执行
 */
@Slf4j
@Service
public class DirectedGraphExecutionEngine {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final ExecutorService executorService = Executors.newFixedThreadPool(10);
    private final AtomicBoolean stopRequested = new AtomicBoolean(false);

    @Autowired
    private AlgorithmExecutionService algorithmExecutionService;

    /**
     * 执行仿真图（全量执行）
     */
    public Map<String, Object> executeGraph(SimulationArchiveEntity archive) {
        return executeGraph(archive, null, archive.getProjectName());
    }

    /**
     * 执行仿真图（支持选择性执行，每个节点使用自己的时间窗口）
     * @param archive 仿真档案
     * @param selectedNodeIds 选中的节点ID列表（null表示全量执行）
     * @param projectName 项目名称
     */
    public Map<String, Object> executeGraph(SimulationArchiveEntity archive, List<String> selectedNodeIds,
                                             String projectName) {
        Map<String, Object> result = new HashMap<>();
        stopRequested.set(false);

        try {
            String graphJson = archive.getGraphJson();
            if (graphJson == null || graphJson.isEmpty()) {
                result.put("success", false);
                result.put("message", "仿真图为空");
                return result;
            }

            JsonNode graphNode = objectMapper.readTree(graphJson);
            JsonNode nodes = graphNode.get("nodes");
            JsonNode edges = graphNode.get("edges");

            if (nodes == null || !nodes.isArray() || nodes.size() == 0) {
                result.put("success", false);
                result.put("message", "仿真图没有节点");
                return result;
            }

            // 构建节点映射
            Map<String, JsonNode> nodeMap = new LinkedHashMap<>();
            for (JsonNode node : nodes) {
                String nodeId = node.get("nodeId").asText();
                nodeMap.put(nodeId, node);
            }

            // 确定要执行的节点集合
            Set<String> executeNodeIds;
            if (selectedNodeIds != null && !selectedNodeIds.isEmpty()) {
                executeNodeIds = new HashSet<>(selectedNodeIds);
                // 自动加入选中节点的前驱节点（保证数据流完整）
                addPredecessorNodes(edges, executeNodeIds, nodeMap);
            } else {
                executeNodeIds = nodeMap.keySet();
            }

            // 构建邻接表和入度表（仅包含要执行的节点）
            Map<String, List<String>> adjacencyList = new HashMap<>();
            Map<String, Integer> inDegree = new HashMap<>();
            for (String nodeId : executeNodeIds) {
                adjacencyList.put(nodeId, new ArrayList<>());
                inDegree.put(nodeId, 0);
            }

            if (edges != null && edges.isArray()) {
                for (JsonNode edge : edges) {
                    String sourceId = edge.get("sourceNodeId").asText();
                    String targetId = edge.get("targetNodeId").asText();
                    log.info("边: {} -> {}", sourceId, targetId);
                    if (executeNodeIds.contains(sourceId) && executeNodeIds.contains(targetId)) {
                        adjacencyList.get(sourceId).add(targetId);
                        inDegree.put(targetId, inDegree.get(targetId) + 1);
                    }
                }
            }
            log.info("入度表: {}", inDegree);

            // 拓扑排序
            List<String> executionOrder = topologicalSort(adjacencyList, inDegree);
            if (executionOrder == null) {
                result.put("success", false);
                result.put("message", "仿真图存在环，无法执行");
                return result;
            }

            log.info("执行顺序: {}", executionOrder);

            // 按拓扑顺序执行节点
            Map<String, Object> executionResults = new ConcurrentHashMap<>();
            Map<String, String> nodeOutputs = new ConcurrentHashMap<>(); // 节点输出的txt文本
            Map<String, Future<?>> futures = new HashMap<>();

            for (String nodeId : executionOrder) {
                if (stopRequested.get()) {
                    result.put("success", false);
                    result.put("message", "仿真已被停止");
                    return result;
                }

                JsonNode node = nodeMap.get(nodeId);

                // 等待前置节点完成
                if (edges != null && edges.isArray()) {
                    for (JsonNode edge : edges) {
                        if (edge.get("targetNodeId").asText().equals(nodeId)) {
                            String sourceId = edge.get("sourceNodeId").asText();
                            if (futures.containsKey(sourceId)) {
                                futures.get(sourceId).get();
                            }
                        }
                    }
                }

                // 执行当前算法节点
                try {
                    Future<?> future = executorService.submit(() -> {
                        try {
                            Map<String, Object> nodeResult = executeAlgorithmNode(
                                node, edges, executionResults, nodeOutputs, projectName);
                            executionResults.put(nodeId, nodeResult);
                            log.info("节点 {} 执行完成", nodeId);
                        } catch (Exception e) {
                            log.error("节点 {} 执行失败", nodeId, e);
                            Map<String, Object> errorResult = new HashMap<>();
                            errorResult.put("nodeId", nodeId);
                            errorResult.put("status", "failed");
                            errorResult.put("error", e.getMessage());
                            errorResult.put("processLog", "");
                            executionResults.put(nodeId, errorResult);
                        }
                    });
                    futures.put(nodeId, future);
                } catch (RejectedExecutionException e) {
                    log.error("节点 {} 提交任务失败，线程池已关闭", nodeId, e);
                    Map<String, Object> errorResult = new HashMap<>();
                    errorResult.put("nodeId", nodeId);
                    errorResult.put("status", "failed");
                    errorResult.put("error", "线程池已关闭，无法提交任务: " + e.getMessage());
                    executionResults.put(nodeId, errorResult);
                }
            }

            // 等待所有节点完成
            for (Future<?> future : futures.values()) {
                future.get();
            }

            // 按拓扑排序顺序构建results，保证前端日志显示顺序正确
            Map<String, Object> orderedResults = new LinkedHashMap<>();
            for (String nodeId : executionOrder) {
                Object nodeResult = executionResults.get(nodeId);
                if (nodeResult != null) {
                    orderedResults.put(nodeId, nodeResult);
                }
            }

            result.put("success", true);
            result.put("message", "仿真执行成功");
            result.put("executionOrder", executionOrder);
            result.put("results", orderedResults);
            result.put("nodeOutputs", nodeOutputs);

        } catch (Exception e) {
            log.error("执行仿真图失败", e);
            result.put("success", false);
            result.put("message", "执行失败: " + e.getMessage());
        }

        return result;
    }

    /**
     * 递归添加前驱节点（保证数据流完整性）
     */
    private void addPredecessorNodes(JsonNode edges, Set<String> executeNodeIds, Map<String, JsonNode> nodeMap) {
        if (edges == null || !edges.isArray()) return;
        boolean added = true;
        while (added) {
            added = false;
            for (JsonNode edge : edges) {
                String sourceId = edge.get("sourceNodeId").asText();
                String targetId = edge.get("targetNodeId").asText();
                if (executeNodeIds.contains(targetId) && !executeNodeIds.contains(sourceId) && nodeMap.containsKey(sourceId)) {
                    executeNodeIds.add(sourceId);
                    added = true;
                }
            }
        }
    }

    /**
     * 拓扑排序
     */
    private List<String> topologicalSort(Map<String, List<String>> adjacencyList, Map<String, Integer> inDegree) {
        // 使用副本避免修改原始数据
        Map<String, Integer> inDegreeCopy = new HashMap<>(inDegree);
        List<String> result = new ArrayList<>();
        Queue<String> queue = new LinkedList<>();

        for (Map.Entry<String, Integer> entry : inDegreeCopy.entrySet()) {
            if (entry.getValue() == 0) {
                queue.offer(entry.getKey());
            }
        }

        while (!queue.isEmpty()) {
            String node = queue.poll();
            result.add(node);

            for (String neighbor : adjacencyList.get(node)) {
                inDegreeCopy.put(neighbor, inDegreeCopy.get(neighbor) - 1);
                if (inDegreeCopy.get(neighbor) == 0) {
                    queue.offer(neighbor);
                }
            }
        }

        if (result.size() != inDegree.size()) {
            return null;
        }

        return result;
    }

    /**
     * 执行算法任务节点
     * 参考RunTaskService的执行逻辑：下载算法文件、导出数据、执行命令
     * 每个节点使用自己配置的startTime/endTime作为数据时间窗口
     */
    private Map<String, Object> executeAlgorithmNode(JsonNode node, JsonNode edges,
                                                      Map<String, Object> executionResults,
                                                      Map<String, String> nodeOutputs,
                                                      String projectName) throws Exception {
        String nodeId = node.get("nodeId").asText();
        String nodeName = node.has("nodeName") ? node.get("nodeName").asText() : "";
        String algorithmName = node.has("algorithmName") ? node.get("algorithmName").asText() : "";
        String algorithmVersion = node.has("algorithmVersion") ? node.get("algorithmVersion").asText() : "";

        log.info("执行算法任务节点: nodeId={}, name={}, algorithm={}:{}", nodeId, nodeName, algorithmName, algorithmVersion);

        if (algorithmName.isEmpty() || algorithmVersion.isEmpty()) {
            throw new Exception("节点 " + nodeName + " 未配置算法");
        }

        // 使用节点自己配置的时间窗口
        Long startTime = node.has("startTime") && !node.get("startTime").isNull() ? node.get("startTime").asLong() : null;
        Long endTime = node.has("endTime") && !node.get("endTime").isNull() ? node.get("endTime").asLong() : null;

        // 构造执行参数
        Map<String, Object> executionParams = new HashMap<>();
        executionParams.put("nodeId", nodeId);
        executionParams.put("nodeName", nodeName);
        executionParams.put("algorithmName", algorithmName);
        executionParams.put("algorithmVersion", algorithmVersion);
        executionParams.put("startTime", startTime);
        executionParams.put("endTime", endTime);

        // 收集前驱节点的输出，使用边的数据映射配置
        // dataMapping格式: {"sourceOutput": "output.csv", "targetInput": "input.csv"}
        Map<String, Object> predecessorOutputs = new HashMap<>();
        if (edges != null && edges.isArray()) {
            for (JsonNode edge : edges) {
                String sourceId = edge.get("sourceNodeId").asText();
                String targetId = edge.get("targetNodeId").asText();
                if (targetId.equals(nodeId) && executionResults.containsKey(sourceId)) {
                    Object predResult = executionResults.get(sourceId);
                    if (predResult instanceof Map) {
                        Map<?, ?> predMap = (Map<?, ?>) predResult;
                        if ("completed".equals(predMap.get("status"))) {
                            // 解析边的数据映射
                            String sourceOutput = null;
                            String targetInput = null;
                            if (edge.has("dataMapping") && !edge.get("dataMapping").isNull()) {
                                try {
                                    JsonNode mapping = objectMapper.readTree(edge.get("dataMapping").asText());
                                    sourceOutput = mapping.has("sourceOutput") ? mapping.get("sourceOutput").asText() : null;
                                    targetInput = mapping.has("targetInput") ? mapping.get("targetInput").asText() : null;
                                } catch (Exception e) {
                                    log.warn("解析边数据映射失败: {}", edge.get("dataMapping"), e);
                                }
                            }
                            Map<String, Object> outputEntry = new HashMap<>();
                            outputEntry.put("output", predMap.get("output"));
                            outputEntry.put("outputCsv", predMap.get("outputCsv"));
                            outputEntry.put("sourceOutput", sourceOutput);
                            outputEntry.put("targetInput", targetInput);
                            outputEntry.put("taskDir", predMap.get("taskDir"));
                            predecessorOutputs.put(sourceId, outputEntry);
                        }
                    }
                }
            }
        }

        // 收集后继节点的边配置，获取当前节点的输出文件名映射
        String sourceOutputMapping = null;
        if (edges != null && edges.isArray()) {
            for (JsonNode edge : edges) {
                String sourceId = edge.get("sourceNodeId").asText();
                String targetId = edge.get("targetNodeId").asText();
                if (sourceId.equals(nodeId)) {
                    // 这是当前节点作为源节点的边，获取sourceOutput配置
                    if (edge.has("dataMapping") && !edge.get("dataMapping").isNull()) {
                        try {
                            JsonNode mapping = objectMapper.readTree(edge.get("dataMapping").asText());
                            String mappingSourceOutput = mapping.has("sourceOutput") ? mapping.get("sourceOutput").asText() : null;
                            if (mappingSourceOutput != null && !mappingSourceOutput.isEmpty()) {
                                // 如果有多个后继节点，使用第一个配置的sourceOutput
                                if (sourceOutputMapping == null) {
                                    sourceOutputMapping = mappingSourceOutput;
                                } else if (!sourceOutputMapping.equals(mappingSourceOutput)) {
                                    log.warn("节点 {} 有多个后继节点配置了不同的sourceOutput: {}, {}", nodeId, sourceOutputMapping, mappingSourceOutput);
                                }
                            }
                        } catch (Exception e) {
                            log.warn("解析边数据映射失败: {}", edge.get("dataMapping"), e);
                        }
                    }
                }
            }
        }
        executionParams.put("sourceOutputMapping", sourceOutputMapping);

        // 调用算法执行服务（模型从算法档案的calledModels获取，下载到项目执行目录）
        Result<Map<String, Object>> execResult = algorithmExecutionService.executeAlgorithmTask(
            algorithmName, algorithmVersion, startTime, endTime,
            projectName, predecessorOutputs, executionParams);

        Map<String, Object> nodeResult = new HashMap<>();
        nodeResult.put("nodeId", nodeId);
        nodeResult.put("nodeName", nodeName);
        nodeResult.put("algorithm", algorithmName);
        nodeResult.put("version", algorithmVersion);

        if (execResult.getSuccess()) {
            Map<String, Object> resultData = execResult.getData();
            String outputText = resultData != null ? (String) resultData.get("output") : "";
            String outputCsv = resultData != null ? (String) resultData.get("outputCsv") : null;
            String processLog = resultData != null ? (String) resultData.get("processLog") : "";
            String taskDir = resultData != null ? (String) resultData.get("taskDir") : "";
            String calledModels = resultData != null ? (String) resultData.get("calledModels") : null;

            nodeResult.put("status", "completed");
            nodeResult.put("output", outputText);
            nodeResult.put("outputCsv", outputCsv);
            nodeResult.put("processLog", processLog);
            nodeResult.put("taskDir", taskDir);
            nodeResult.put("calledModels", calledModels);
            nodeResult.put("timestamp", System.currentTimeMillis());
            nodeOutputs.put(nodeId, outputText);
        } else {
            Map<String, Object> resultData = execResult.getData();
            String processLog = resultData != null ? (String) resultData.get("processLog") : "";
            nodeResult.put("status", "failed");
            nodeResult.put("error", execResult.getMessage());
            nodeResult.put("processLog", processLog != null ? processLog : "");
            nodeResult.put("timestamp", System.currentTimeMillis());
        }

        return nodeResult;
    }

    /**
     * 停止执行
     */
    public void stopExecution() {
        stopRequested.set(true);
        // 不shutdown线程池，只设置停止标志，线程池在整个服务生命周期内保持活跃
        log.info("执行引擎已请求停止");
    }
}
