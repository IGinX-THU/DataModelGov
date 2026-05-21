package com.tsinghua.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsinghua.entity.SimulationArchiveEntity;
import com.tsinghua.model.Result;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.concurrent.*;

/**
 * 有向图执行引擎
 * 用于执行仿真档案中的有向图
 */
@Slf4j
@Service
public class DirectedGraphExecutionEngine {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final ExecutorService executorService = Executors.newFixedThreadPool(10);

    @Autowired
    private AlgorithmExecutionService algorithmExecutionService;

    /**
     * 执行仿真图
     */
    public Map<String, Object> executeGraph(SimulationArchiveEntity archive) {
        Map<String, Object> result = new HashMap<>();
        try {
            String graphJson = archive.getGraphJson();
            if (graphJson == null || graphJson.isEmpty()) {
                result.put("success", false);
                result.put("message", "仿真图为空");
                return result;
            }

            JsonNode graphNode = objectMapper.readTree(graphJson);
            
            // 解析节点和边
            JsonNode nodes = graphNode.get("nodes");
            JsonNode edges = graphNode.get("edges");

            if (nodes == null || !nodes.isArray() || nodes.size() == 0) {
                result.put("success", false);
                result.put("message", "仿真图没有节点");
                return result;
            }

            // 构建邻接表和入度表
            Map<String, List<String>> adjacencyList = new HashMap<>();
            Map<String, Integer> inDegree = new HashMap<>();
            Map<String, JsonNode> nodeMap = new HashMap<>();

            // 初始化
            for (JsonNode node : nodes) {
                String nodeId = node.get("nodeId").asText();
                adjacencyList.put(nodeId, new ArrayList<>());
                inDegree.put(nodeId, 0);
                nodeMap.put(nodeId, node);
            }

            // 构建边关系
            if (edges != null && edges.isArray()) {
                for (JsonNode edge : edges) {
                    String sourceId = edge.get("sourceNodeId").asText();
                    String targetId = edge.get("targetNodeId").asText();
                    
                    adjacencyList.get(sourceId).add(targetId);
                    inDegree.put(targetId, inDegree.get(targetId) + 1);
                }
            }

            // 拓扑排序
            List<String> executionOrder = topologicalSort(adjacencyList, inDegree);
            
            if (executionOrder == null) {
                result.put("success", false);
                result.put("message", "仿真图存在环，无法执行");
                return result;
            }

            log.info("执行顺序: {}", executionOrder);

            // 按拓扑顺序执行节点
            Map<String, Object> executionResults = new HashMap<>();
            Map<String, Future<?>> futures = new HashMap<>();

            for (String nodeId : executionOrder) {
                JsonNode node = nodeMap.get(nodeId);
                String nodeType = node.get("nodeType").asText();
                
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

                // 执行当前节点
                Future<?> future = executorService.submit(() -> {
                    try {
                        Object nodeResult = executeNode(node, executionResults);
                        executionResults.put(nodeId, nodeResult);
                        log.info("节点 {} 执行完成", nodeId);
                    } catch (Exception e) {
                        log.error("节点 {} 执行失败", nodeId, e);
                        throw new RuntimeException("节点执行失败: " + nodeId, e);
                    }
                });
                
                futures.put(nodeId, future);
            }

            // 等待所有节点完成
            for (Future<?> future : futures.values()) {
                future.get();
            }

            result.put("success", true);
            result.put("message", "仿真执行成功");
            result.put("executionOrder", executionOrder);
            result.put("results", executionResults);

        } catch (Exception e) {
            log.error("执行仿真图失败", e);
            result.put("success", false);
            result.put("message", "执行失败: " + e.getMessage());
        }

        return result;
    }

    /**
     * 拓扑排序
     */
    private List<String> topologicalSort(Map<String, List<String>> adjacencyList, Map<String, Integer> inDegree) {
        List<String> result = new ArrayList<>();
        Queue<String> queue = new LinkedList<>();

        // 找到所有入度为0的节点
        for (Map.Entry<String, Integer> entry : inDegree.entrySet()) {
            if (entry.getValue() == 0) {
                queue.offer(entry.getKey());
            }
        }

        while (!queue.isEmpty()) {
            String node = queue.poll();
            result.add(node);

            for (String neighbor : adjacencyList.get(node)) {
                inDegree.put(neighbor, inDegree.get(neighbor) - 1);
                if (inDegree.get(neighbor) == 0) {
                    queue.offer(neighbor);
                }
            }
        }

        // 检查是否所有节点都已访问（检测环）
        if (result.size() != inDegree.size()) {
            return null; // 存在环
        }

        return result;
    }

    /**
     * 执行单个节点
     */
    private Object executeNode(JsonNode node, Map<String, Object> executionResults) throws Exception {
        String nodeType = node.get("nodeType").asText();
        String resourceName = node.has("resourceName") ? node.get("resourceName").asText() : "";
        String resourceVersion = node.has("resourceVersion") ? node.get("resourceVersion").asText() : "";
        
        log.info("执行节点: type={}, resource={}, version={}", nodeType, resourceName, resourceVersion);

        switch (nodeType) {
            case "algorithm":
                return executeAlgorithmNode(node, executionResults);
            case "model":
                return executeModelNode(node, executionResults);
            case "data":
                return executeDataNode(node, executionResults);
            default:
                throw new Exception("未知的节点类型: " + nodeType);
        }
    }

    /**
     * 执行算法节点
     */
    private Object executeAlgorithmNode(JsonNode node, Map<String, Object> executionResults) throws Exception {
        String algorithmName = node.has("resourceName") ? node.get("resourceName").asText() : "";
        String algorithmVersion = node.has("resourceVersion") ? node.get("resourceVersion").asText() : "";
        String algorithmType = node.has("algorithmType") ? node.get("algorithmType").asText() : "python";
        
        log.info("执行算法: {} version: {} type: {}", algorithmName, algorithmVersion, algorithmType);
        
        // 准备输入数据
        Map<String, Object> inputData = new HashMap<>();
        
        // 添加前驱节点的输出
        String nodeId = node.get("nodeId").asText();
        for (Map.Entry<String, Object> entry : executionResults.entrySet()) {
            if (!entry.getKey().equals(nodeId)) {
                inputData.put(entry.getKey(), entry.getValue());
            }
        }
        
        // 调用算法执行服务
        try {
            // 构造SimulationNodeEntity
            com.tsinghua.entity.SimulationNodeEntity simNode = new com.tsinghua.entity.SimulationNodeEntity();
            simNode.setNodeId(nodeId);
            simNode.setNodeName(node.has("nodeName") ? node.get("nodeName").asText() : algorithmName);
            simNode.setNodeType("algorithm");
            simNode.setResourceName(algorithmName);
            simNode.setResourceVersion(algorithmVersion);
            simNode.setAlgorithmName(algorithmName);
            simNode.setAlgorithmVersion(algorithmVersion);
            
            // 执行算法
            Result<String> result = algorithmExecutionService.executeAlgorithm(simNode, inputData);
            
            if (result.getSuccess()) {
                String executionId = result.getData();
                Result<String> outputResult = algorithmExecutionService.getExecutionResult(executionId);
                
                Map<String, Object> nodeResult = new HashMap<>();
                nodeResult.put("algorithm", algorithmName);
                nodeResult.put("version", algorithmVersion);
                nodeResult.put("status", "completed");
                nodeResult.put("output", outputResult.getData());
                nodeResult.put("timestamp", System.currentTimeMillis());
                
                return nodeResult;
            } else {
                throw new Exception("算法执行失败: " + result.getMessage());
            }
        } catch (Exception e) {
            log.error("算法执行失败: {}", algorithmName, e);
            Map<String, Object> errorResult = new HashMap<>();
            errorResult.put("algorithm", algorithmName);
            errorResult.put("status", "failed");
            errorResult.put("error", e.getMessage());
            errorResult.put("timestamp", System.currentTimeMillis());
            return errorResult;
        }
    }

    /**
     * 执行模型节点
     */
    private Object executeModelNode(JsonNode node, Map<String, Object> executionResults) throws Exception {
        // TODO: 实现模型执行逻辑
        // 这里需要调用模型文件服务来提取和运行模型
        String modelName = node.has("resourceName") ? node.get("resourceName").asText() : "";
        String modelVersion = node.has("resourceVersion") ? node.get("resourceVersion").asText() : "";
        
        log.info("执行模型: {} version: {}", modelName, modelVersion);
        
        Map<String, Object> result = new HashMap<>();
        result.put("model", modelName);
        result.put("version", modelVersion);
        result.put("status", "completed");
        result.put("output", "模型执行结果数据");
        result.put("timestamp", System.currentTimeMillis());
        
        return result;
    }

    /**
     * 执行数据节点
     */
    private Object executeDataNode(JsonNode node, Map<String, Object> executionResults) throws Exception {
        // TODO: 实现数据节点逻辑
        // 数据节点主要用于提供输入数据
        String dataSource = node.has("resourceName") ? node.get("resourceName").asText() : "";
        
        log.info("读取数据源: {}", dataSource);
        
        Map<String, Object> result = new HashMap<>();
        result.put("dataSource", dataSource);
        result.put("status", "completed");
        result.put("data", "数据内容");
        result.put("timestamp", System.currentTimeMillis());
        
        return result;
    }

    /**
     * 停止执行
     */
    public void stopExecution() {
        executorService.shutdownNow();
        log.info("执行引擎已停止");
    }
}
