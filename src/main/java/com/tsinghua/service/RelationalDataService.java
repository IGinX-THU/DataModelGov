package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import com.tsinghua.dto.RelationalQueryRequest;
import com.tsinghua.dto.TableDto;
import lombok.extern.slf4j.Slf4j;
import org.checkerframework.checker.nullness.compatqual.NonNullDecl;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@Service
public class RelationalDataService {

    @Autowired
    private Session iginxSession;

    public TableDto queryData(RelationalQueryRequest request) {
        try {
            String sql = "SELECT * FROM %s LIMIT %s OFFSET %s;";
            // 修复分页计算：OFFSET应该是(pageNum - 1) * pageSize
            int offset = (request.getPageNum() - 1) * request.getPageSize();
            log.info("执行SQL: {}, tableName: {}, pageSize: {}, offset: {}", 
                    sql, request.getTableName(), request.getPageSize(), offset);
            
            iginxSession.openSession();
            SessionExecuteSqlResult res = iginxSession.executeSql(String.format(sql, request.getTableName(), request.getPageSize(), offset));
            List<Map<String, Object>> records = getRecords(res);
            iginxSession.closeSession();
            
            TableDto result = new TableDto(res.getPaths(), records);
            log.info("查询结果: paths={}, records={}", res.getPaths(), records.size());
            
            return result;
        } catch (Exception e) {
            log.error("查询失败", e);
            return null;
        }
    }

    @NonNullDecl
    private static List<Map<String, Object>> getRecords(SessionExecuteSqlResult res) {
        List<String> header = res.getPaths();
        List<Map<String, Object>> records = new ArrayList<>();
        List<List<Object>>  rows = res.getValues();
        rows.forEach(row -> {
            Map<String, Object> rs = new LinkedHashMap<>();
            for (int i=0; i<=header.size() -1; i++){
                Object value = row.get(i);
                if (value instanceof byte[]) {
                    rs.put(header.get(i), new String((byte[]) value, StandardCharsets.UTF_8));
                } else {
                    rs.put(header.get(i), row.get(i));
                }
            }
            records.add(rs);
        });
        return records;
    }

    public Object countData(RelationalQueryRequest request) {
        try {
            String sql = "SELECT COUNT(1) FROM %s;";
            iginxSession.openSession();
            SessionExecuteSqlResult res = iginxSession.executeSql(String.format(sql, request.getTableName()));
            iginxSession.closeSession();
            return res.getValues().get(0).get(0);
        } catch (Exception e) {
            log.error("查询失败", e);
            return 0;
        }
    }
}
