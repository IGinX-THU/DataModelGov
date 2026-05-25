package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXHeader;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.tsinghua.dto.DataQueryRequest;
import com.tsinghua.dto.InputBindDto;
import com.tsinghua.dto.OutputBindDto;
import com.tsinghua.entity.AlgorithmMetaEntity;
import com.tsinghua.entity.SimulationNodeEntity;
import com.tsinghua.entity.SimulationEdgeEntity;
import com.tsinghua.model.Result;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * 算法执行服务
 * 负责执行仿真图中的算法任务节点
 * 参考RunTaskService的执行逻辑：下载算法文件、导出数据、执行命令、收集输出
 */
@Slf4j
@Service
public class AlgorithmExecutionService {

    @Autowired
    private AlgorithmFileService algorithmFileService;

    @Autowired
    private ModelFileService modelFileService;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private DataTableService dataTableService;

    // 存储执行结果
    private final Map<String, String> executionResults = new ConcurrentHashMap<>();

    // 存储执行状态
    private final Map<String, String> executionStatus = new ConcurrentHashMap<>();

    /**
     * 执行算法任务（联合仿真专用）
     * 参考RunTaskService.runTask的完整流程
     * 数据源从算法档案获取，模型从算法档案的calledModels获取并下载到执行目录
     * 执行目录使用project下对应项目的目录
     *
     * @param algorithmName 算法名称
     * @param algorithmVersion 算法版本
     * @param startTime 数据时间窗口开始时间
     * @param endTime 数据时间窗口结束时间
     * @param projectName 项目名称（用于确定执行目录）
     * @param predecessorOutputs 前驱节点的输出数据（含边数据映射信息）
     * @param executionParams 执行参数
     */
    public Result<Map<String, Object>> executeAlgorithmTask(
            String algorithmName, String algorithmVersion,
            Long startTime, Long endTime,
            String projectName,
            Map<String, Object> predecessorOutputs,
            Map<String, Object> executionParams) {
        try {
            // 1. 获取算法元数据
            AlgorithmMetaEntity algorithmMeta = algorithmFileService.queryMeta(algorithmName, algorithmVersion);
            if (algorithmMeta == null) {
                return new Result<>(500, "算法元数据不存在: " + algorithmName + " " + algorithmVersion, null);
            }

            // 2. 创建任务目录（使用project下对应项目的目录）
            long timestamp = System.currentTimeMillis();
            Path taskDir;
            if (projectName != null && !projectName.isEmpty()) {
                taskDir = Paths.get("project", projectName, "job", "simulation", String.valueOf(timestamp));
            } else {
                taskDir = Paths.get("job", "simulation", String.valueOf(timestamp));
            }
            Files.createDirectories(taskDir);
            log.info("创建仿真任务目录: {}", taskDir);

            // 创建日志文件
            Path logFile = taskDir.resolve("task.log");
            StringBuilder processLogBuilder = new StringBuilder();
            String startLog = "进程启动: 算法=" + algorithmName + " v" + algorithmVersion +
                ", 目录=" + taskDir.toString() +
                ", 时间=" + new Date() + "\n";
            processLogBuilder.append(startLog);
            try { Files.write(logFile, startLog.getBytes(StandardCharsets.UTF_8), StandardOpenOption.CREATE, StandardOpenOption.APPEND); } catch (IOException e) { log.warn("写入日志失败", e); }

            try {
                // 3. 下载算法文件
                algorithmFileService.extractAlgorithmFile(algorithmName, algorithmVersion, taskDir);
                log.info("算法文件已提取到: {}", taskDir);
                String extractLog = "算法文件已提取完成\n";
                processLogBuilder.append(extractLog);
                try { Files.write(logFile, extractLog.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND); } catch (IOException e) { /* ignore */ }

                // 4. 下载算法依赖的模型文件（DLL等）到执行目录
                downloadCalledModels(algorithmMeta, taskDir);

                // 5. 写入前驱节点的输出数据作为输入（使用边的数据映射配置）
                if (predecessorOutputs != null && !predecessorOutputs.isEmpty()) {
                    writePredecessorOutputs(taskDir, predecessorOutputs, algorithmMeta);
                    String predLog = "前驱节点输出数据已写入\n";
                    processLogBuilder.append(predLog);
                    try { Files.write(logFile, predLog.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND); } catch (IOException e) { /* ignore */ }
                }

                // 6. 导出输入数据（从IginX查询，使用算法档案中的数据源配置）
                exportInputData(startTime, endTime, algorithmMeta, taskDir);
                String dataLog = "输入数据导出完成" + (startTime != null ? ", startTime=" + startTime : "") + (endTime != null ? ", endTime=" + endTime : "") + "\n";
                processLogBuilder.append(dataLog);
                try { Files.write(logFile, dataLog.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND); } catch (IOException e) { /* ignore */ }

                // 7. 执行命令
                String cmd = algorithmMeta.getCmd();
                if (cmd == null || cmd.trim().isEmpty()) {
                    return new Result<>(500, "算法未设置运行命令", null);
                }

                String cmdLog = "执行命令: " + cmd + "\n";
                processLogBuilder.append(cmdLog);
                try { Files.write(logFile, cmdLog.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND); } catch (IOException e) { /* ignore */ }

                String output = executeCommand(cmd, taskDir, algorithmMeta, processLogBuilder, logFile);

                // 8. 读取输出文件
                String outputText = collectOutputText(taskDir, algorithmMeta, output);

                // 9. 读取输出CSV文件内容
                String outputCsvContent = readOutputCsv(taskDir, algorithmMeta);

                String endLog = "进程结束: 退出成功, 时间=" + new Date() + "\n";
                processLogBuilder.append(endLog);
                try { Files.write(logFile, endLog.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND); } catch (IOException e) { /* ignore */ }

                // 保存执行结果
                String executionId = UUID.randomUUID().toString();
                executionResults.put(executionId, outputText);
                executionStatus.put(executionId, "completed");

                Map<String, Object> resultData = new HashMap<>();
                resultData.put("output", outputText);
                resultData.put("outputCsv", outputCsvContent);
                resultData.put("processLog", processLogBuilder.toString());
                resultData.put("taskDir", taskDir.toString());

                return Result.success(resultData);
            } catch (Exception e) {
                String errorLog = "进程异常: " + e.getMessage() + "\n";
                processLogBuilder.append(errorLog);
                try { Files.write(logFile, errorLog.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND); } catch (IOException ex) { /* ignore */ }
                throw e;
            }
        } catch (Exception e) {
            log.error("算法任务执行失败: {}:{}", algorithmName, algorithmVersion, e);
            return new Result<>(500, "算法执行失败: " + e.getMessage(), null);
        }
    }

    /**
     * 下载算法依赖的模型文件（DLL等）到执行目录
     * 从算法档案的calledModels字段获取模型列表，逐个下载
     * calledModels格式：JSON数组 [{"name":"model1","version":"v1"}, ...]
     */
    private void downloadCalledModels(AlgorithmMetaEntity algorithmMeta, Path taskDir) {
        String calledModelsStr = algorithmMeta.getCalledModels();
        if (calledModelsStr == null || calledModelsStr.trim().isEmpty()) {
            log.info("算法 {} 无依赖模型，跳过模型下载", algorithmMeta.getName());
            return;
        }

        try {
            JSONArray calledModels = JSONArray.parseArray(calledModelsStr);
            for (int i = 0; i < calledModels.size(); i++) {
                JSONObject modelRef = calledModels.getJSONObject(i);
                String modelName = modelRef.getString("name");
                String modelVersion = modelRef.getString("version");
                if (modelName != null && modelVersion != null) {
                    try {
                        modelFileService.extractModelFile(modelName, modelVersion, taskDir);
                        log.info("模型 {} v{} 已下载到执行目录", modelName, modelVersion);
                    } catch (Exception e) {
                        log.warn("下载模型 {} v{} 失败: {}", modelName, modelVersion, e.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            log.warn("解析calledModels失败: {}", calledModelsStr, e);
        }
    }

    /**
     * 写入前驱节点的输出数据到任务目录
     * 使用边的数据映射配置：sourceOutput指定源节点输出文件名，targetInput指定当前节点输入文件名
     * 例如：A输出output.csv → B输入input.csv，则将A的output.csv内容写入B的input.csv
     */
    @SuppressWarnings("unchecked")
    private void writePredecessorOutputs(Path taskDir, Map<String, Object> predecessorOutputs,
                                         AlgorithmMetaEntity algorithmMeta) throws IOException {
        String defaultInputCsv = algorithmMeta.getInputCsvName();
        if (defaultInputCsv == null || defaultInputCsv.trim().isEmpty()) {
            defaultInputCsv = "input.csv";
        }

        boolean hasMappedInput = false;
        StringBuilder combinedOutput = new StringBuilder();

        for (Map.Entry<String, Object> entry : predecessorOutputs.entrySet()) {
            if (!(entry.getValue() instanceof Map)) continue;
            Map<String, Object> predData = (Map<String, Object>) entry.getValue();
            String outputText = predData.get("output") != null ? predData.get("output").toString() : "";
            String sourceOutput = (String) predData.get("sourceOutput");
            String targetInput = (String) predData.get("targetInput");

            if (targetInput != null && !targetInput.isEmpty()) {
                // 有明确的目标输入文件名映射：将前驱输出写入指定的输入文件
                Path targetFile = taskDir.resolve(targetInput);
                try (PrintWriter writer = new PrintWriter(new FileWriter(targetFile.toFile(), true))) {
                    writer.print(outputText);
                }
                hasMappedInput = true;
                log.info("前驱节点 {} 输出已写入: {}", entry.getKey(), targetFile);
            } else {
                // 无明确映射，追加到组合输出
                combinedOutput.append("=== 前驱节点 ").append(entry.getKey()).append(" 输出 ===\n");
                combinedOutput.append(outputText).append("\n");
            }
        }

        // 如果有未映射的前驱输出，写入默认输入文件
        if (combinedOutput.length() > 0 && !hasMappedInput) {
            Path defaultInputFile = taskDir.resolve(defaultInputCsv);
            try (PrintWriter writer = new PrintWriter(new FileWriter(defaultInputFile.toFile(), true))) {
                writer.print(combinedOutput.toString());
            }
            log.info("未映射的前驱输出已写入默认输入文件: {}", defaultInputFile);
        }
    }

    /**
     * 导出输入数据（从IginX查询数据并写入CSV文件）
     * 使用算法档案中的数据源配置（tableName/inputData）
     * 参考RunTaskService.downloadData和exportDataToFile
     */
    private void exportInputData(Long startTime, Long endTime,
                                  AlgorithmMetaEntity algorithmMeta, Path taskDir) {
        try {
            // 从算法元数据获取数据源
            String inputDataStr = algorithmMeta.getInputData();
            if (inputDataStr == null || inputDataStr.trim().isEmpty()) {
                log.info("算法 {} 无数据源配置，跳过数据导出", algorithmMeta.getName());
                return;
            }

            // 解析数据源路径
            List<String> paths = new ArrayList<>();
            try {
                JSONArray dataSources = JSONArray.parseArray(inputDataStr);
                for (int i = 0; i < dataSources.size(); i++) {
                    paths.add(dataSources.getString(i));
                }
            } catch (Exception e) {
                // 如果不是JSON数组，尝试作为单个路径
                paths.add(inputDataStr);
            }

            if (paths.isEmpty()) return;

            // 如果算法元数据有inputsBind，使用它来映射字段
            List<InputBindDto> inputBinds = null;
            if (algorithmMeta.getInputsBind() != null && !algorithmMeta.getInputsBind().isEmpty()) {
                inputBinds = JSONArray.parseArray(algorithmMeta.getInputsBind(), InputBindDto.class);
            }

            // 确定输入CSV文件名
            String inputCsvName = algorithmMeta.getInputCsvName();
            if (inputCsvName == null || inputCsvName.trim().isEmpty()) {
                inputCsvName = "input.csv";
            }
            Path csvFile = taskDir.resolve(inputCsvName);

            // 查询数据
            DataQueryRequest dataRequest = new DataQueryRequest();
            dataRequest.setPaths(paths);
            if (startTime != null) dataRequest.setStartTime(startTime);
            if (endTime != null) dataRequest.setEndTime(endTime);

            IginXTable table = dataTableService.queryIginXTable(dataRequest);
            if (table == null) return;

            // 写入CSV文件
            try (PrintWriter writer = new PrintWriter(new FileWriter(csvFile.toFile(), true))) {
                IginXHeader header = table.getHeader();
                if (header.hasTimestamp()) {
                    writer.print("key,");
                }
                // 写入表头
                for (String path : paths) {
                    String fieldName = path.contains(".") ?
                        path.substring(path.lastIndexOf(".") + 1) : path;
                    writer.print(fieldName + ",");
                }
                writer.println();

                // 写入数据
                List<IginXRecord> records = table.getRecords();
                for (IginXRecord record : records) {
                    if (header.hasTimestamp()) {
                        writer.print(record.getKey() + ",");
                    }
                    for (String path : paths) {
                        Object value = record.getValue(path);
                        if (value instanceof byte[]) {
                            writer.print(ConvertUtil.bytesToString((byte[]) value));
                        } else {
                            writer.print(value != null ? value : "");
                        }
                        writer.print(",");
                    }
                    writer.println();
                }
            }

            log.info("输入数据已导出到: {}", csvFile);
        } catch (Exception e) {
            log.error("导出输入数据失败", e);
        }
    }

    /**
     * 执行命令
     * 参考RunTaskService.executeCommand，实时写入日志文件
     */
    private String executeCommand(String cmd, Path taskDir, AlgorithmMetaEntity algorithmMeta,
                                    StringBuilder processLogBuilder, Path logFile) throws Exception {
        ProcessBuilder processBuilder = new ProcessBuilder();
        processBuilder.directory(taskDir.toFile());

        String[] cmdArray;
        String osName = System.getProperty("os.name", "").toLowerCase();
        if (osName.contains("windows")) {
            cmdArray = new String[]{"cmd", "/c", "chcp 65001 && " + cmd};
        } else {
            cmdArray = cmd.split("\\s+");
        }
        processBuilder.command(cmdArray);
        processBuilder.redirectErrorStream(true);

        log.info("执行命令: {} 在目录: {}", cmd, taskDir);

        Process process = processBuilder.start();

        // 读取输出，实时写入日志
        StringBuilder output = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                String outputLine = "[OUT] " + line + "\n";
                output.append(line).append("\n");
                processLogBuilder.append(outputLine);
                try { Files.write(logFile, outputLine.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND); } catch (IOException e) { /* ignore */ }
            }
        }

        int exitCode = process.waitFor();

        String endLog = "进程结束: 退出码=" + exitCode + "\n";
        processLogBuilder.append(endLog);
        try { Files.write(logFile, endLog.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND); } catch (IOException e) { /* ignore */ }

        if (exitCode != 0) {
            log.error("算法执行失败，退出码: {}, 输出: {}", exitCode, output);
            throw new RuntimeException("算法执行失败，退出码: " + exitCode + "\n" + output);
        }

        return output.toString();
    }

    /**
     * 收集输出文本
     * 读取命令输出和输出文件内容，按规定的txt格式组织
     */
    private String collectOutputText(Path taskDir, AlgorithmMetaEntity algorithmMeta, String cmdOutput) throws IOException {
        StringBuilder outputText = new StringBuilder();

        // 命令输出
        outputText.append("=== 算法执行输出 ===\n");
        outputText.append("算法: ").append(algorithmMeta.getName()).append(" v").append(algorithmMeta.getVersion()).append("\n");
        outputText.append("时间: ").append(new Date()).append("\n\n");
        outputText.append(cmdOutput);

        // 读取输出文件
        String outputCsvName = algorithmMeta.getOutputCsvName();
        if (outputCsvName != null && !outputCsvName.trim().isEmpty()) {
            Path outputFile = taskDir.resolve(outputCsvName);
            if (Files.exists(outputFile)) {
                outputText.append("\n=== 输出文件内容 (").append(outputCsvName).append(") ===\n");
                outputText.append(new String(Files.readAllBytes(outputFile), StandardCharsets.UTF_8));
            }
        }

        // 也检查output.txt
        Path defaultOutputFile = taskDir.resolve("output.txt");
        if (Files.exists(defaultOutputFile)) {
            outputText.append("\n=== 输出文件内容 (output.txt) ===\n");
            outputText.append(new String(Files.readAllBytes(defaultOutputFile), StandardCharsets.UTF_8));
        }

        return outputText.toString();
    }

    /**
     * 读取输出CSV文件内容
     */
    private String readOutputCsv(Path taskDir, AlgorithmMetaEntity algorithmMeta) {
        try {
            String outputCsvName = algorithmMeta.getOutputCsvName();
            if (outputCsvName != null && !outputCsvName.trim().isEmpty()) {
                Path outputFile = taskDir.resolve(outputCsvName);
                if (Files.exists(outputFile)) {
                    return new String(Files.readAllBytes(outputFile), StandardCharsets.UTF_8);
                }
            }
        } catch (Exception e) {
            log.warn("读取输出CSV失败: {}", e.getMessage());
        }
        return null;
    }

    /**
     * 清理目录
     */
    private void cleanupDir(Path dir) {
        try {
            Files.walk(dir)
                .sorted(Comparator.reverseOrder())
                .forEach(path -> {
                    try {
                        Files.deleteIfExists(path);
                    } catch (IOException e) {
                        log.warn("删除文件失败: {}", path);
                    }
                });
        } catch (IOException e) {
            log.warn("清理目录失败: {}", e.getMessage());
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
