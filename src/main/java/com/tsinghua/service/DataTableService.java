package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.ClusterInfo;
import cn.edu.tsinghua.iginx.session.Column;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.QueryClient;
import cn.edu.tsinghua.iginx.session_v2.query.*;
import cn.edu.tsinghua.iginx.thrift.*;
import com.tsinghua.dto.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.stream.Collectors;


/**
 * 数据源管理服务
 */
@Slf4j
@Service
public class DataTableService {

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

}
