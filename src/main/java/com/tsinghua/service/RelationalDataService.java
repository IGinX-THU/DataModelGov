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
            iginxSession.openSession();
            SessionExecuteSqlResult res =  iginxSession.executeSql(String.format(sql, request.getTableName(), request.getPageSize(), request.getPageNum()));
            List<Map<String, Object>> records = getRecords(res);
            iginxSession.closeSession();
            return new TableDto(res.getPaths(), records);
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

}
