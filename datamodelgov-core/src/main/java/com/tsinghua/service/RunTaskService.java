package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
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
import org.springframework.stereotype.Service;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;
import java.util.stream.Collectors;

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


    public void runTask(RunTaskRequest runTaskRequest) {
        try {
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
            
            runTaskEntity.setInputMeasurements(JSONArray.toJSONString(inputs.stream().map(InputBindDto::getSourceField).collect(Collectors.toList())));
            runTaskEntity.setOutputMeasurements(JSONArray.toJSONString(outputs.stream().map(OutputBindDto::getResultTarget).collect(Collectors.toList())));
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
                executeCommand(associationRulesEntity, runTaskEntity, taskDir);
            } else {
                log.warn("未设置运行命令，任务状态保持为PENDING");
            }

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
            // 写入表头（根据inputsBind映射关系）
            for (int i = 0; i < inputs.size(); i++) {
                InputBindDto input = inputs.get(i);
                writer.print(input.getTargetField()); // 使用targetField作为列名
                if (i < inputs.size() - 1) {
                    writer.print(",");
                }
            }
            writer.println();
            
            // 写入数据
            if (table != null && table.getRecords() != null) {
                for (IginXRecord record : table.getRecords()) {
                    for (int i = 0; i < inputs.size(); i++) {
                        String sourceField = String.format("%s.%s", tableName, inputs.get(i).getSourceField());
                        Object value = record.getValue(sourceField);
                        
                        if (value instanceof byte[]) {
                            writer.print(ConvertUtil.bytesToString((byte[]) value));
                        } else if (value != null) {
                            writer.print(value.toString());
                        } else {
                            writer.print("");
                        }
                        
                        if (i < inputs.size() - 1) {
                            writer.print(",");
                        }
                    }
                    writer.println();
                }
            }
            
            writer.flush();
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
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "inputMeasurements", runTaskEntity.getInputMeasurements(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "outputMeasurements", runTaskEntity.getOutputMeasurements(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "status", runTaskEntity.getStatus(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "timestamp", runTaskEntity.getTimestamp(), timestamp));

        // 批量写入元数据
        iginxClient.getWriteClient().writePoints(metaPoints);
        log.info("关联规则已保存。名称: {}, 时间戳: {}", runTaskEntity.getName(), timestamp);
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

    private void executeCommand(AssociationRulesEntity associationRulesEntity, RunTaskEntity runTaskEntity, Path taskDir) throws Exception {
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
        int exitCode = process.waitFor();
        
        if (exitCode == 0) {
            log.info("命令执行成功，退出码: {}", exitCode);
            runTaskEntity.setStatus(TaskStatus.SUCCESS);
        } else {
            log.error("命令执行失败，退出码: {}", exitCode);
            runTaskEntity.setStatus(TaskStatus.FAILED);
        }
        
        // 保存最终状态
        saveTask(runTaskEntity);
    }

}
