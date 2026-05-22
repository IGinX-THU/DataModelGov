package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.query.SimpleQuery;
import com.tsinghua.entity.AlgorithmMetaEntity;
import com.tsinghua.entity.SimulationNodeEntity;
import com.tsinghua.entity.SimulationEdgeEntity;
import com.tsinghua.model.Result;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 算法执行服务
 * 负责执行仿真图中的算法节点
 */
@Service
public class AlgorithmExecutionService {

    @Autowired
    private AlgorithmFileService algorithmFileService;

    @Autowired
    private IginXClient iginxClient;

    // 存储执行结果
    private final Map<String, String> executionResults = new ConcurrentHashMap<>();

    // 存储执行状态
    private final Map<String, String> executionStatus = new ConcurrentHashMap<>();

    /**
     * 执行单个算法节点
     */
    public Result<String> executeAlgorithm(SimulationNodeEntity node, Map<String, Object> inputData) {
        try {
            if (!"algorithm".equals(node.getNodeType())) {
                return Result.error("节点类型不是算法", null);
            }

            if (node.getAlgorithmName() == null || node.getAlgorithmVersion() == null) {
                return Result.error("算法名称或版本为空", null);
            }

            // 下载算法文件
            byte[] algorithmBytes = algorithmFileService.downloadAlgorithm(
                node.getAlgorithmName(), 
                node.getAlgorithmVersion()
            );

            // 获取算法元数据
            AlgorithmMetaEntity algorithmMeta = algorithmFileService.queryMeta(
                node.getAlgorithmName(), 
                node.getAlgorithmVersion()
            );

            if (algorithmMeta == null) {
                return Result.error("算法元数据不存在", null);
            }

            // 创建临时目录
            Path tempDir = Files.createTempDirectory("algorithm_execution_");
            
            try {
                // 保存算法文件
                Path algorithmFile = tempDir.resolve(algorithmMeta.getFileName());
                Files.write(algorithmFile, algorithmBytes);

                // 准备输入文件
                Path inputFile = tempDir.resolve(algorithmMeta.getInputCsvName() != null ?
                    algorithmMeta.getInputCsvName() : "input.txt");
                if (inputData != null && !inputData.isEmpty()) {
                    Files.write(inputFile, formatInputData(inputData));
                }

                // 执行算法
                String output = executeAlgorithmFile(
                    algorithmFile, 
                    inputFile, 
                    algorithmMeta.getAlgorithmType(),
                    algorithmMeta.getCmd()
                );

                // 保存执行结果
                String executionId = UUID.randomUUID().toString();
                executionResults.put(executionId, output);
                executionStatus.put(executionId, "completed");

                return Result.success(executionId, null);
            } finally {
                // 清理临时目录
                cleanupTempDir(tempDir);
            }
        } catch (Exception e) {
            return Result.error("算法执行失败: " + e.getMessage(), null);
        }
    }

    /**
     * 执行仿真图（按拓扑顺序）
     */
    public Result<String> executeSimulationGraph(
        List<SimulationNodeEntity> nodes, 
        List<SimulationEdgeEntity> edges
    ) {
        try {
            // 构建拓扑排序
            List<SimulationNodeEntity> executionOrder = topologicalSort(nodes, edges);
            
            if (executionOrder == null) {
                return Result.error("仿真图存在环，无法执行", null);
            }

            StringBuilder totalOutput = new StringBuilder();
            Map<String, Object> nodeOutputs = new HashMap<>();

            // 按顺序执行节点
            for (SimulationNodeEntity node : executionOrder) {
                if ("algorithm".equals(node.getNodeType())) {
                    // 准备输入数据
                    Map<String, Object> inputData = prepareInputData(node, edges, nodeOutputs);
                    
                    // 执行算法
                    Result<String> result = executeAlgorithm(node, inputData);
                    if (!result.getSuccess()) {
                        return Result.error("节点 " + node.getNodeName() + " 执行失败: " + result.getMessage(), null);
                    }

                    // 获取输出
                    String output = executionResults.get(result.getData());
                    nodeOutputs.put(node.getNodeId(), output);
                    totalOutput.append("节点 ").append(node.getNodeName()).append(" 执行结果:\n")
                              .append(output).append("\n\n");
                }
            }

            return Result.success(totalOutput.toString(), null);
        } catch (Exception e) {
            return Result.error("仿真图执行失败: " + e.getMessage(), null);
        }
    }

    /**
     * 拓扑排序
     */
    private List<SimulationNodeEntity> topologicalSort(
        List<SimulationNodeEntity> nodes, 
        List<SimulationEdgeEntity> edges
    ) {
        Map<String, Integer> inDegree = new HashMap<>();
        Map<String, List<String>> adjList = new HashMap<>();
        
        // 初始化
        for (SimulationNodeEntity node : nodes) {
            inDegree.put(node.getNodeId(), 0);
            adjList.put(node.getNodeId(), new ArrayList<>());
        }
        
        // 构建邻接表和入度
        for (SimulationEdgeEntity edge : edges) {
            String from = edge.getSourceNodeId();
            String to = edge.getTargetNodeId();
            adjList.get(from).add(to);
            inDegree.put(to, inDegree.get(to) + 1);
        }
        
        // 拓扑排序
        List<SimulationNodeEntity> result = new ArrayList<>();
        Queue<String> queue = new LinkedList<>();
        
        // 找到入度为0的节点
        for (SimulationNodeEntity node : nodes) {
            if (inDegree.get(node.getNodeId()) == 0) {
                queue.offer(node.getNodeId());
            }
        }
        
        while (!queue.isEmpty()) {
            String nodeId = queue.poll();
            SimulationNodeEntity node = nodes.stream()
                .filter(n -> n.getNodeId().equals(nodeId))
                .findFirst()
                .orElse(null);
            
            if (node != null) {
                result.add(node);
            }
            
            for (String neighbor : adjList.get(nodeId)) {
                inDegree.put(neighbor, inDegree.get(neighbor) - 1);
                if (inDegree.get(neighbor) == 0) {
                    queue.offer(neighbor);
                }
            }
        }
        
        // 检查是否有环
        if (result.size() != nodes.size()) {
            return null;
        }
        
        return result;
    }

    /**
     * 准备输入数据
     */
    private Map<String, Object> prepareInputData(
        SimulationNodeEntity node,
        List<SimulationEdgeEntity> edges,
        Map<String, Object> nodeOutputs
    ) {
        Map<String, Object> inputData = new HashMap<>();
        
        // 从IGinX查询数据
        if (node.getInputDataSource() != null && node.getInputDataTable() != null) {
            try {
                String path = node.getInputDataSource() + "." + node.getInputDataTable();
                // 查询最新数据
                SimpleQuery query = SimpleQuery.builder()
                        .addMeasurement(path)
                        .endKey(Long.MAX_VALUE)
                        .build();

                IginXTable table = iginxClient.getQueryClient().query(query);
                
                if (table != null && table.getRecords() != null && !table.getRecords().isEmpty()) {
                    List<Object> values = new ArrayList<>();
                    for (IginXRecord record : table.getRecords()) {
                        Map<String, Object> recordValues = record.getValues();
                        Object value = recordValues.get(path);
                        if (value != null) {
                            values.add(value);
                        }
                    }
                    inputData.put("iginx_data", values);
                }
            } catch (Exception e) {
                System.err.println("查询IGinX数据失败: " + e.getMessage());
            }
        }
        
        // 添加前驱节点的输出
        for (SimulationEdgeEntity edge : edges) {
            if (edge.getTargetNodeId().equals(node.getNodeId())) {
                Object output = nodeOutputs.get(edge.getSourceNodeId());
                if (output != null) {
                    inputData.put(edge.getSourceNodeId(), output);
                }
            }
        }
        
        return inputData;
    }

    /**
     * 执行算法文件
     */
    private String executeAlgorithmFile(
        Path algorithmFile, 
        Path inputFile,
        String algorithmType,
        String cmd
    ) throws Exception {
        Path outputFile = inputFile.getParent().resolve("output.txt");
        
        ProcessBuilder processBuilder;
        
        switch (algorithmType) {
            case "python":
                processBuilder = new ProcessBuilder(
                    "python", algorithmFile.toString(), inputFile.toString(), outputFile.toString()
                );
                break;
            case "java":
                processBuilder = new ProcessBuilder(
                    "java", "-jar", algorithmFile.toString(), inputFile.toString(), outputFile.toString()
                );
                break;
            case "shell":
                processBuilder = new ProcessBuilder(
                    "bash", algorithmFile.toString(), inputFile.toString(), outputFile.toString()
                );
                break;
            default:
                // 使用自定义命令
                String[] command = (cmd != null ? cmd : "").split(" ");
                List<String> commandList = new ArrayList<>(Arrays.asList(command));
                commandList.add(inputFile.toString());
                commandList.add(outputFile.toString());
                processBuilder = new ProcessBuilder(commandList);
                break;
        }
        
        processBuilder.directory(inputFile.getParent().toFile());
        processBuilder.redirectErrorStream(true);
        
        Process process = processBuilder.start();
        
        // 读取输出
        StringBuilder output = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(
            new InputStreamReader(process.getInputStream()))) {
            String line;
            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
            }
        }
        
        int exitCode = process.waitFor();
        
        // 读取输出文件
        if (Files.exists(outputFile)) {
            output.append("\n=== 输出文件内容 ===\n");
            output.append(new String(Files.readAllBytes(outputFile)));
        }
        
        if (exitCode != 0) {
            throw new RuntimeException("算法执行失败，退出码: " + exitCode);
        }
        
        return output.toString();
    }

    /**
     * 格式化输入数据
     */
    private byte[] formatInputData(Map<String, Object> inputData) throws IOException {
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, Object> entry : inputData.entrySet()) {
            sb.append(entry.getKey()).append("=").append(entry.getValue()).append("\n");
        }
        return sb.toString().getBytes();
    }

    /**
     * 清理临时目录
     */
    private void cleanupTempDir(Path tempDir) {
        try {
            Files.walk(tempDir)
                .sorted(Comparator.reverseOrder())
                .forEach(path -> {
                    try {
                        Files.deleteIfExists(path);
                    } catch (IOException e) {
                        System.err.println("删除文件失败: " + path);
                    }
                });
            Files.deleteIfExists(tempDir);
        } catch (IOException e) {
            System.err.println("清理临时目录失败: " + e.getMessage());
        }
    }

    /**
     * 获取执行结果
     */
    public Result<String> getExecutionResult(String executionId) {
        String result = executionResults.get(executionId);
        if (result == null) {
            return Result.error("执行结果不存在", null);
        }
        return Result.success(result, null);
    }

    /**
     * 获取执行状态
     */
    public Result<String> getExecutionStatus(String executionId) {
        String status = executionStatus.get(executionId);
        if (status == null) {
            return Result.error("执行状态不存在", null);
        }
        return Result.success(status, null);
    }
}
