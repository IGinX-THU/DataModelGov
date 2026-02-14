package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.QueryClient;
import cn.edu.tsinghua.iginx.session_v2.query.*;
import cn.edu.tsinghua.iginx.thrift.*;
import cn.edu.tsinghua.iginx.utils.Pair;
import com.tsinghua.dto.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;


/**
 * 数据源管理服务
 */
@Slf4j
@Service
public class DataTableService {

    private static final int CHUNK_SIZE = 1024 * 1024; // 1MB，与源码一致

    private static final String KEY = "key";

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    public TableDto dataQuery(DataQueryRequest request) {
        List<String> columns = new ArrayList<>();
        List<Map<String, Object>> resultSet = new ArrayList<>();

        try {
            IginXTable table = queryIginXTable(request);

            IginXHeader header = table.getHeader();
            if (header.hasTimestamp()) {
                log.info(KEY+"\t");
                columns.add(KEY);
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
                    recordMap.put(KEY, record.getKey());
                }
                recordMap.putAll(record.getValues());
                resultSet.add(recordMap);
            }
        } catch (Exception e) {
            log.error("数据查询失败", e);
        }

        return new TableDto(columns, resultSet);
    }

    public Result<Void> importData(MultipartFile file, DataImportRequest importConfig) {
        Path tempFilePath = null;

        try {
            iginxSession.openSession();
            String uploadedFileName = System.currentTimeMillis() + ".csv";
            // 1. 保存上传文件到临时位置
            tempFilePath = Files.createTempFile("iginx_upload_", ".csv");
            file.transferTo(tempFilePath.toFile());

            // 2. 构建LOAD DATA SQL语句
            // 注意：此处的路径是一个“约定”或“任务标识”，最终文件通过uploadFileChunk上传
            String sql = String.format("LOAD DATA FROM INFILE '%s' AS CSV INTO %s;",
                    uploadedFileName, // 使用一个约定的文件名
                    importConfig.getTargetPath());

            // 3. 执行SQL，解析命令并获取服务端准备的状态/路径（如果需要）
            // 根据源码，此处可能会返回一个服务端期望的路径，但uploadFileChunk似乎更直接。
            // 实际流程可能需要先调用一个接口获取上传令牌或路径。这里假设直接上传。

            // 4. 分块读取临时文件并上传
            try (RandomAccessFile raf = new RandomAccessFile(tempFilePath.toFile(), "r")) {
                long offset = 0;
                byte[] buffer = new byte[CHUNK_SIZE];
                int bytesRead;
                while ((bytesRead = raf.read(buffer)) != -1) {
                    byte[] dataToSend;
                    if (bytesRead < CHUNK_SIZE) {
                        dataToSend = new byte[bytesRead];
                        System.arraycopy(buffer, 0, dataToSend, 0, bytesRead);
                    } else {
                        dataToSend = buffer;
                    }
                    ByteBuffer data = ByteBuffer.wrap(dataToSend);
                    FileChunk chunk = new FileChunk(uploadedFileName, offset, data, bytesRead);
                    iginxSession.uploadFileChunk(chunk); // 关键步骤：上传文件块
                    offset += bytesRead;
                }
            }

            // 5. 所有块上传完成后，执行导入
            Pair<List<String>, Long> result = iginxSession.executeLoadCSV(sql, uploadedFileName);
            long recordsNum = result.v;
            return Result.success(String.format("数据导入成功，导入记录数: %d", recordsNum));

        } catch (Exception e) {
            log.error("数据导入失败", e);
            return Result.error("数据导入失败");
        } finally {
            try {
                // 清理临时文件
                if (tempFilePath != null) {
                    Files.deleteIfExists(tempFilePath);
                }
                iginxSession.closeSession();
            } catch (Exception e) {
                log.error("finally Exception", e);
            }

        }
    }

    public void exportData(DataQueryRequest request, HttpServletResponse response) {
        try {
            IginXTable table = queryIginXTable(request);;
            String fileName = "export_" + System.currentTimeMillis() + ".csv";
            // 设置响应头
            response.setContentType("text/csv");
            response.setCharacterEncoding("UTF-8");
            response.setHeader(HttpHeaders.CONTENT_DISPOSITION,
                "attachment; filename=\"" + fileName + "\"");
            PrintWriter writer = response.getWriter();

            // 直接一行一行写入表头和数据
            IginXHeader header = table.getHeader();
            if (header.hasTimestamp()) {
                writer.print("key,");
            }
            for (IginXColumn column: header.getColumns()) {
                writer.print(column.getName() + ",");
            }
            writer.println();
            writer.flush();
            List<IginXRecord> records = table.getRecords();
            for (IginXRecord record: records) {
                if (header.hasTimestamp()) {
                    writer.print(record.getKey() + ",");
                }
                for (IginXColumn column: header.getColumns()) {
                    writer.print(record.getValue(column.getName()));
                    writer.print(",");
                }
                writer.println();
                writer.flush();
            }

        } catch (IOException e) {
            // 忽略客户端中断
            log.error("客户端中断", e);
        }
    }

    private IginXTable queryIginXTable(DataQueryRequest request) {
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
        return table;
    }

}
