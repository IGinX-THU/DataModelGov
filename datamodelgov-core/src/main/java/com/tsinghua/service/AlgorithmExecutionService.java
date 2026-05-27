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
import com.tsinghua.auth.util.AuthUtil;
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
        StringBuilder processLogBuilder = new StringBuilder();
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
                boolean hasPredecessorData = predecessorOutputs != null && !predecessorOutputs.isEmpty();
                if (hasPredecessorData) {
                    writePredecessorOutputs(taskDir, predecessorOutputs, algorithmMeta);
                    String predLog = "前驱节点输出数据已写入\n";
                    processLogBuilder.append(predLog);
                    try { Files.write(logFile, predLog.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND); } catch (IOException e) { /* ignore */ }
                }

                // 6. 导出输入数据（从IginX查询，使用算法档案中的数据源配置）
                // 如果没有前驱节点数据，才从IginX导出数据作为输入
                if (!hasPredecessorData) {
                    exportInputData(startTime, endTime, algorithmMeta, taskDir);
                    String dataLog = "输入数据导出完成" + (startTime != null ? ", startTime=" + startTime : "") + (endTime != null ? ", endTime=" + endTime : "") + "\n";
                    processLogBuilder.append(dataLog);
                    try { Files.write(logFile, dataLog.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND); } catch (IOException e) { /* ignore */ }
                }

                // 7. 执行命令（根据边数据映射动态调整输入输出CSV文件名）
                String cmd = algorithmMeta.getCmd();
                if (cmd == null || cmd.trim().isEmpty()) {
                    return new Result<>(500, "算法未设置运行命令", null);
                }

                // 如果有前驱节点数据，根据边数据映射替换命令中的输入文件名
                if (hasPredecessorData && predecessorOutputs != null) {
                    cmd = adjustCommandWithMapping(cmd, predecessorOutputs, algorithmMeta);
                }

                // 如果有后继节点配置的sourceOutputMapping，替换命令中的输出文件名
                String sourceOutputMapping = executionParams != null ? (String) executionParams.get("sourceOutputMapping") : null;
                if (sourceOutputMapping != null && !sourceOutputMapping.isEmpty()) {
                    String defaultOutputCsv = algorithmMeta.getOutputCsvName();
                    if (defaultOutputCsv == null || defaultOutputCsv.trim().isEmpty()) {
                        defaultOutputCsv = "output.csv";
                    }
                    cmd = cmd.replace(defaultOutputCsv, sourceOutputMapping);
                    log.info("命令输出文件名已替换: {} -> {}", defaultOutputCsv, sourceOutputMapping);
                }

                String cmdLog = "执行命令: " + cmd + "\n";
                processLogBuilder.append(cmdLog);
                try { Files.write(logFile, cmdLog.getBytes(StandardCharsets.UTF_8), StandardOpenOption.APPEND); } catch (IOException e) { /* ignore */ }

                String output = executeCommand(cmd, taskDir, algorithmMeta, processLogBuilder, logFile);

                // 8. 读取输出文件
                String outputText = collectOutputText(taskDir, algorithmMeta, output);

                // 9. 处理输出CSV表头映射（参考RunTaskService的processOutputCsv）
                // 使用 sourceOutputMapping 指定的输出文件名
                String actualOutputCsv = sourceOutputMapping != null && !sourceOutputMapping.isEmpty()
                    ? sourceOutputMapping : algorithmMeta.getOutputCsvName();
                processOutputCsvHeaderMapping(taskDir, algorithmMeta, actualOutputCsv);

                // 10. 读取输出CSV文件内容
                String outputCsvContent = readOutputCsv(taskDir, actualOutputCsv);

                // 11. 如果配置了结果回写路径前缀，将输出CSV入库
                String outputTable = algorithmMeta.getOutputTable();
                if (outputTable != null && !outputTable.trim().isEmpty() && actualOutputCsv != null && !actualOutputCsv.trim().isEmpty()) {
                    try {
                        Path outputCsvFile = taskDir.resolve(actualOutputCsv);
                        if (Files.exists(outputCsvFile)) {
                            long recordsNum = dataTableService.importCsvFile(outputCsvFile, outputTable, actualOutputCsv, null, algorithmMeta.getAuthor());
                            log.info("输出CSV已入库到 {}, 记录数: {}", outputTable, recordsNum);
                        }
                    } catch (Exception e) {
                        log.error("输出CSV入库失败: {}", outputTable, e);
                    }
                }

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
            Map<String, Object> errorData = new HashMap<>();
            errorData.put("processLog", processLogBuilder.toString());
            return new Result<>(500, "算法执行失败: " + e.getMessage(), errorData);
        }
    }

    /**
     * 下载算法依赖的模型文件（DLL等）到执行目录
     * 从算法档案的calledModels字段获取模型列表，逐个下载
     * calledModels格式：JSON数组 [{"name":"model1","version":"v1"}, ...]
     */
    private void downloadCalledModels(AlgorithmMetaEntity algorithmMeta, Path taskDir) {
        String calledModelsStr = algorithmMeta.getCalledModels();
        log.info("开始下载模型，calledModels={}", calledModelsStr);

        if (calledModelsStr == null || calledModelsStr.trim().isEmpty()) {
            log.info("算法 {} 无依赖模型，跳过模型下载", algorithmMeta.getName());
            return;
        }

        try {
            JSONArray calledModels = JSONArray.parseArray(calledModelsStr);
            log.info("解析到 {} 个依赖模型", calledModels.size());

            for (int i = 0; i < calledModels.size(); i++) {
                JSONObject modelRef = calledModels.getJSONObject(i);
                String modelName = modelRef.getString("modelName");
                String modelVersion = modelRef.getString("version");
                log.info("准备下载模型: {} v{}", modelName, modelVersion);

                if (modelName != null && modelVersion != null) {
                    try {
                        modelFileService.extractModelFile(modelName, modelVersion, taskDir);
                        log.info("模型 {} v{} 已下载到执行目录: {}", modelName, modelVersion, taskDir);
                    } catch (Exception e) {
                        log.error("下载模型 {} v{} 失败", modelName, modelVersion, e);
                    }
                }
            }
        } catch (Exception e) {
            log.error("解析calledModels失败: {}", calledModelsStr, e);
        }
    }

    /**
     * 写入前驱节点的输出数据到任务目录
     * 每个前驱节点的输出写入独立的输入CSV文件，不合并
     * 多个前驱节点时，命令中会有多个-i参数分别指向各输入文件
     */
    @SuppressWarnings("unchecked")
    private void writePredecessorOutputs(Path taskDir, Map<String, Object> predecessorOutputs,
                                         AlgorithmMetaEntity algorithmMeta) throws IOException {
        String defaultInputCsv = algorithmMeta.getInputCsvName();
        if (defaultInputCsv == null || defaultInputCsv.trim().isEmpty()) {
            defaultInputCsv = "input.csv";
        }

        // 检测targetInput冲突：多个前驱映射到同一targetInput时需要自动生成唯一文件名
        Map<String, Integer> targetInputCount = new HashMap<>();
        for (Map.Entry<String, Object> entry : predecessorOutputs.entrySet()) {
            if (!(entry.getValue() instanceof Map)) continue;
            Map<String, Object> predData = (Map<String, Object>) entry.getValue();
            String targetInput = (String) predData.get("targetInput");
            String inputName = (targetInput != null && !targetInput.isEmpty()) ? targetInput : defaultInputCsv;
            targetInputCount.merge(inputName, 1, Integer::sum);
        }

        // 每个前驱节点写入独立的输入文件
        int autoIndex = 1;
        for (Map.Entry<String, Object> entry : predecessorOutputs.entrySet()) {
            if (!(entry.getValue() instanceof Map)) continue;
            Map<String, Object> predData = (Map<String, Object>) entry.getValue();
            String outputCsv = predData.get("outputCsv") != null ? predData.get("outputCsv").toString() : null;
            String targetInput = (String) predData.get("targetInput");

            if (outputCsv == null || outputCsv.trim().isEmpty()) {
                log.warn("前驱节点 {} 无CSV输出数据，跳过", entry.getKey());
                continue;
            }

            // 确定输入文件名：如果有冲突则自动生成唯一文件名
            String inputFileName;
            if (targetInput != null && !targetInput.isEmpty()) {
                if (targetInputCount.getOrDefault(targetInput, 0) > 1) {
                    // 多个前驱映射到同一targetInput，自动生成唯一文件名
                    String baseName = targetInput.replace(".csv", "");
                    inputFileName = baseName + "_" + entry.getKey() + ".csv";
                    log.info("前驱节点 {} targetInput冲突，自动生成文件名: {} -> {}", entry.getKey(), targetInput, inputFileName);
                } else {
                    inputFileName = targetInput;
                }
            } else {
                if (targetInputCount.getOrDefault(defaultInputCsv, 0) > 1) {
                    String baseName = defaultInputCsv.replace(".csv", "");
                    inputFileName = baseName + "_" + autoIndex + ".csv";
                    autoIndex++;
                    log.info("前驱节点 {} 无targetInput且有冲突，自动生成文件名: {}", entry.getKey(), inputFileName);
                } else {
                    inputFileName = defaultInputCsv;
                }
            }

            // 将确定的输入文件名写回predData，供adjustCommandWithMapping使用
            predData.put("resolvedInputFile", inputFileName);

            Path targetFile = taskDir.resolve(inputFileName);
            try (PrintWriter writer = new PrintWriter(new FileWriter(targetFile.toFile()))) {
                writer.print(outputCsv);
            }
            log.info("前驱节点 {} CSV数据已写入: {}", entry.getKey(), targetFile);
        }
    }

    /**
     * 根据边数据映射调整执行命令中的输入CSV文件名
     * 单个前驱：替换命令中的默认输入文件名
     * 多个前驱：将命令中的 -i input.csv 替换为 -i file1.csv -i file2.csv ...
     */
    @SuppressWarnings("unchecked")
    private String adjustCommandWithMapping(String cmd, Map<String, Object> predecessorOutputs,
                                           AlgorithmMetaEntity algorithmMeta) {
        String adjustedCmd = cmd;
        String defaultInputCsv = algorithmMeta.getInputCsvName();
        if (defaultInputCsv == null || defaultInputCsv.trim().isEmpty()) {
            defaultInputCsv = "input.csv";
        }

        // 收集所有已解析的输入文件名（由writePredecessorOutputs写入predData的resolvedInputFile）
        List<String> inputFiles = new ArrayList<>();
        for (Map.Entry<String, Object> entry : predecessorOutputs.entrySet()) {
            if (!(entry.getValue() instanceof Map)) continue;
            Map<String, Object> predData = (Map<String, Object>) entry.getValue();
            String resolvedInputFile = (String) predData.get("resolvedInputFile");
            if (resolvedInputFile != null && !resolvedInputFile.isEmpty()) {
                inputFiles.add(resolvedInputFile);
            } else {
                // 兼容：如果没有resolvedInputFile，回退到targetInput或默认
                String targetInput = (String) predData.get("targetInput");
                if (targetInput != null && !targetInput.isEmpty()) {
                    inputFiles.add(targetInput);
                } else {
                    inputFiles.add(defaultInputCsv);
                }
            }
        }

        if (inputFiles.isEmpty()) {
            return adjustedCmd;
        }

        if (inputFiles.size() == 1) {
            // 单个输入文件，简单替换文件名
            String inputFile = inputFiles.get(0);
            if (!inputFile.equals(defaultInputCsv)) {
                adjustedCmd = adjustedCmd.replace(defaultInputCsv, inputFile);
                log.info("命令输入文件名已替换: {} -> {}", defaultInputCsv, inputFile);
            }
        } else {
            // 多个输入文件，将 -i input.csv 替换为 -i file1.csv -i file2.csv ...
            // 支持多种 -i 参数格式：-i input.csv, -iinput.csv, --input input.csv
            String inputPattern = null;
            String[] inputPatterns = {"-i " + defaultInputCsv, "-i" + defaultInputCsv, "--input " + defaultInputCsv};
            for (String pattern : inputPatterns) {
                if (adjustedCmd.contains(pattern)) {
                    inputPattern = pattern;
                    break;
                }
            }

            if (inputPattern != null) {
                // 找到 -i 参数格式，为每个输入文件生成 -i <file>
                String paramPrefix;
                if (inputPattern.startsWith("--input ")) {
                    paramPrefix = "--input ";
                } else if (inputPattern.startsWith("-i ")) {
                    paramPrefix = "-i ";
                } else {
                    paramPrefix = "-i";
                }

                StringBuilder replacement = new StringBuilder();
                for (int i = 0; i < inputFiles.size(); i++) {
                    if (i > 0) replacement.append(" ");
                    replacement.append(paramPrefix).append(inputFiles.get(i));
                }
                adjustedCmd = adjustedCmd.replace(inputPattern, replacement.toString());
                log.info("命令输入参数已扩展为多个: {} -> {}", inputPattern, replacement);
            } else {
                // 未找到 -i 参数格式，简单替换文件名（第一个），并追加其余 -i 参数
                adjustedCmd = adjustedCmd.replace(defaultInputCsv, inputFiles.get(0));
                for (int i = 1; i < inputFiles.size(); i++) {
                    adjustedCmd += " -i " + inputFiles.get(i);
                }
                log.info("命令输入文件名已替换并追加: {}", inputFiles);
            }
        }

        return adjustedCmd;
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
     * 处理输出CSV表头映射
     * 参考RunTaskService的processOutputCsv，将算法输出的列名映射为用户配置的目标列名
     */
    private void processOutputCsvHeaderMapping(Path taskDir, AlgorithmMetaEntity algorithmMeta, String outputCsvName) {
        String outputsBindStr = algorithmMeta.getOutputsBind();

        if (outputCsvName == null || outputCsvName.trim().isEmpty() || outputsBindStr == null || outputsBindStr.trim().isEmpty()) {
            log.info("输出CSV文件名或输出映射为空，跳过输出表头处理");
            return;
        }

        try {
            // 解析输出绑定配置
            List<OutputBindDto> outputs = JSONArray.parseArray(outputsBindStr, OutputBindDto.class);
            if (outputs == null || outputs.isEmpty()) {
                log.info("输出绑定配置为空，跳过输出表头处理");
                return;
            }

            // 构建输出CSV文件路径
            Path outputCsvFile = taskDir.resolve(outputCsvName);

            if (!Files.exists(outputCsvFile)) {
                log.warn("输出CSV文件不存在: {}", outputCsvFile);
                return;
            }

            log.info("开始处理输出CSV表头映射: {}", outputCsvFile);

            // 读取CSV内容并修改表头
            List<String> lines = Files.readAllLines(outputCsvFile, StandardCharsets.UTF_8);
            if (!lines.isEmpty()) {
                // 先过滤掉空行
                List<String> nonEmptyLines = lines.stream()
                    .filter(line -> line != null && !line.trim().isEmpty())
                    .collect(Collectors.toList());
                
                if (nonEmptyLines.isEmpty()) {
                    log.warn("CSV文件只有空行，跳过处理");
                    return;
                }

                // 校验CSV格式：确保每行列数与表头一致
                String headerLine = nonEmptyLines.get(0).trim();
                int expectedColumnCount = headerLine.split(",").length;
                
                for (int i = 1; i < nonEmptyLines.size(); i++) {
                    String line = nonEmptyLines.get(i).trim();
                    int actualColumnCount = line.split(",").length;
                    if (actualColumnCount != expectedColumnCount) {
                        log.warn("CSV第{}行列数不匹配: 期望{}列，实际{}列，已跳过该行", i + 1, expectedColumnCount, actualColumnCount);
                        nonEmptyLines.set(i, ""); // 标记为空行，后续处理时跳过
                    }
                }

                // 修改表头：将原列名(modelOutput)换成新列名(resultTarget)
                String originalHeader = nonEmptyLines.get(0);
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
                nonEmptyLines.set(0, newHeader.toString());

                // 过滤掉标记为空的行
                List<String> filteredLines = nonEmptyLines.stream()
                    .filter(line -> !line.isEmpty())
                    .collect(Collectors.toList());

                // 写回文件
                Files.write(outputCsvFile, filteredLines, StandardCharsets.UTF_8);
                log.info("输出CSV表头映射完成: {}", outputCsvFile);
            }
        } catch (Exception e) {
            log.error("处理输出CSV表头映射失败", e);
        }
    }

    /**
     * 读取输出CSV文件内容
     */
    private String readOutputCsv(Path taskDir, String outputCsvName) {
        try {
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
