package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.ClusterInfo;
import cn.edu.tsinghua.iginx.session.Column;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.QueryClient;
import cn.edu.tsinghua.iginx.session_v2.query.*;
import cn.edu.tsinghua.iginx.thrift.*;
import cn.edu.tsinghua.iginx.utils.Pair;
import com.tsinghua.dto.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.stream.Collectors;


/**
 * 数据源管理服务
 */
@Slf4j
@Service
public class DataTableService {

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    public TableDto dataQuery(DataQueryRequest request) {
        List<String> columns = new ArrayList<>();
        List<Map<String, Object>> resultSet = new ArrayList<>();

        try {
            QueryClient queryClient = iginxClient.getQueryClient();

            Set<String> paths = new HashSet<>(request.getPaths());
            long startKey = Optional.ofNullable(request.getStartTime()).orElse(0L);
            long endKey = Optional.ofNullable(request.getEndTime()).orElse(Long.MAX_VALUE);

            long precision = request.getPrecision();
            if (precision <= 0L) {
                precision = 1000L;
            }
            TimePrecision timePrecision;
            if (request.getTimePrecision() == null || TimePrecision.findByValue(request.getTimePrecision()) == null) {
                timePrecision = TimePrecision.MS;
            } else {
                timePrecision = TimePrecision.findByValue(request.getTimePrecision());
            }

            IginXTable table;
            if (request.getAggregateType() == null || AggregateType.findByValue(request.getAggregateType()) == null) {
                table = queryClient.query(
                        SimpleQuery.builder()
                                .addMeasurements(paths)
                                .startKey(startKey)
                                .endKey(endKey)
                                .build()
                );
            } else {
                table = queryClient.query(DownsampleQuery.builder()
                        .addMeasurements(paths)
                        .startKey(startKey)
                        .endKey(endKey)
                        .aggregate(AggregateType.findByValue(request.getAggregateType()))
                        .precision(precision)
                        .timePrecision(timePrecision.name())
                        .build());
            }

            IginXHeader header = table.getHeader();
            if (header.hasTimestamp()) {
                log.info("Time\t");
                columns.add("Time");
            }
            for (IginXColumn column : header.getColumns()) {
                log.info(column.getName() + "\t");
                columns.add(column.getName());
            }

            List<IginXRecord> records = table.getRecords();
            for (IginXRecord record : records) {
                Map<String, Object> recordMap = new LinkedHashMap<>();
                if (header.hasTimestamp()) {
//                log.info(record.getKey() + "\t");
                    recordMap.put("Time", record.getKey());
                }
                recordMap.putAll(record.getValues());
                resultSet.add(recordMap);
            }
        } catch (Exception e) {
            log.error("数据查询失败", e);
        }

        return new TableDto(columns, resultSet);
    }

    public Long importData(MultipartFile file, DataImportRequest importConfig) {
        Path tempFilePath = null;
        try {
            // 保存为临时文件
            tempFilePath = Files.createTempFile("iginx_import_", ".csv");
            file.transferTo(tempFilePath.toFile());
            log.info("CSV文件已暂存至：{}", tempFilePath);

            // 打开会话
            iginxSession.openSession();

            // 核心：构建正确的 LOAD DATA 语句（注意末尾的分号）
            String loadStatement = String.format(
                    "LOAD DATA FROM INFILE '%s' AS CSV SKIPPING HEADER INTO %s;",
                    file.getOriginalFilename(),
                    importConfig.getTargetPath().trim()
            );

            log.info("执行LOAD语句: {}", loadStatement);

            // 执行导入
            Pair<List<String>, Long> resp = iginxSession.executeLoadCSV(loadStatement, tempFilePath.toAbsolutePath().toString());

            return resp.v;

        } catch (IOException e) {
            log.error("文件处理失败", e);
            return 0L;
        } catch (Exception e) {
            log.error("调用IGinX导入数据失败", e);
            return 0L;
        } finally {
            // 资源清理
            if (iginxSession != null) {
                try {
                    iginxSession.closeSession();
                } catch (Exception e) {
                    log.warn("关闭IGinX会话异常", e);
                }
            }
            if (tempFilePath != null) {
                try {
                    Files.deleteIfExists(tempFilePath);
                } catch (IOException e) {
                    log.error("删除临时文件失败: {}", tempFilePath, e);
                }
            }
        }
    }

}
