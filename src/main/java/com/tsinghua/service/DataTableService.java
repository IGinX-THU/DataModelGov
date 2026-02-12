package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.ClusterInfo;
import cn.edu.tsinghua.iginx.session.Column;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.QueryClient;
import cn.edu.tsinghua.iginx.session_v2.query.*;
import cn.edu.tsinghua.iginx.thrift.AggregateType;
import cn.edu.tsinghua.iginx.thrift.RemovedStorageEngineInfo;
import cn.edu.tsinghua.iginx.thrift.StorageEngineInfo;
import cn.edu.tsinghua.iginx.thrift.StorageEngineType;
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
        QueryClient queryClient = iginxClient.getQueryClient();

        Set<String> paths = new HashSet<>(request.getPaths());
        long startKey = Optional.ofNullable(request.getStartTime()).orElse(0L);
        long endKey = Optional.ofNullable(request.getEndTime()).orElse(Long.MAX_VALUE);

        IginXTable table;
        if (request.getAggregateType() == null || AggregateType.findByValue(request.getAggregateType()) == null) {
            table = queryClient.query( // 查询 a.a.a 序列最近一秒内的数据
                    SimpleQuery.builder()
                            .addMeasurements(paths)
                            .startKey(startKey)
                            .endKey(endKey)
                            .build()
            );
        } else {
            table = queryClient.query(AggregateQuery.builder()
                    .addMeasurements(paths)
                    .startKey(startKey)
                    .endKey(endKey)
                    .aggregate(AggregateType.findByValue(request.getAggregateType()))
                    .build());
        }

        List<String> columns = new ArrayList<>();
        IginXHeader header = table.getHeader();
        if (header.hasTimestamp()) {
            log.info("Time\t");
            columns.add("Time");
        }
        for (IginXColumn column: header.getColumns()) {
            log.info(column.getName() + "\t");
            columns.add(column.getName());
        }
        List<Map<String, Object>> resultSet = new ArrayList<>();
        List<IginXRecord> records = table.getRecords();
        for (IginXRecord record: records) {
            Map<String, Object> recordMap = new LinkedHashMap<>();
            if (header.hasTimestamp()) {
//                log.info(record.getKey() + "\t");
                recordMap.put("Time", record.getKey());
            }
            recordMap.putAll(record.getValues());
            resultSet.add(recordMap);
        }
        return new TableDto(columns, resultSet);
    }

}
