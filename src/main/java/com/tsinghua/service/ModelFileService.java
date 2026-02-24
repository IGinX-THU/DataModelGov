package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.QueryClient;
import cn.edu.tsinghua.iginx.session_v2.WriteClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.query.Query;
import cn.edu.tsinghua.iginx.session_v2.query.SimpleQuery;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.tsinghua.dto.UploadResult;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.*;

@Slf4j
@Service
public class ModelFileService {

    private static final int CHUNK_SIZE = 65536; // 64KB
    private static final String STORAGE_PREFIX = "fs.models";

    @Autowired
    private IginXClient iginxClient;

    private WriteClient writeClient;
    private QueryClient queryClient;

    /**
     * 初始化 IGinX 客户端连接
     * 在 Java 17 环境下，可以直接使用二进制数据，无需 Base64 编码
     */
    @PostConstruct
    public void init() {
        try {
            // 获取写入和查询客户端
            writeClient = iginxClient.getWriteClient();
            queryClient = iginxClient.getQueryClient();

            log.info("IGinX 客户端 (WriteClient/QueryClient) 初始化成功。");

        } catch (Exception e) {
            log.error("初始化 IGinX 客户端失败，请检查服务地址、端口及网络。", e);
            throw new RuntimeException("IGinX 服务连接失败", e);
        }
    }

    /**
     * 上传模型文件 (Java 17+ 优化版)
     * 直接将二进制分块数据写入 IGinX，无需 Base64 编码
     */
    public UploadResult uploadModel(MultipartFile file, String name, String version) throws Exception {
        String storagePath = buildStoragePath(name, version);
        byte[] fileBytes = file.getBytes();
        int totalChunks = (int) Math.ceil((double) fileBytes.length / CHUNK_SIZE);

        // 准备数据点列表
        List<Point> points = new ArrayList<>();

        for (int i = 0; i < totalChunks; i++) {
            int start = i * CHUNK_SIZE;
            int end = Math.min(fileBytes.length, start + CHUNK_SIZE);
            byte[] chunk = Arrays.copyOfRange(fileBytes, start, end);

            // 构建数据点 - 直接存储二进制数据
            Point point = Point.builder()
                    .measurement(storagePath)    // 存储路径
                    .key(i)         // 块序号作为时间戳
                    .binaryValue(chunk)          // 直接存储二进制块 (Java 17+ 兼容)
                    .build();

            points.add(point);

            // 进度提示
            if ((i + 1) % 100 == 0 || i == totalChunks - 1) {
                log.info("模型 {} 版本 {}: 处理进度 {}/{}", name, version, i + 1, totalChunks);
            }
        }

        // 批量写入数据点
        log.info("开始写入模型文件: {} 版本 {}, 共 {} 个数据块...", name, version, totalChunks);
        writeClient.writePoints(points);

        // 计算文件校验信息
        String fileMd5 = calculateMD5(fileBytes);

        log.info("模型文件上传成功。名称: {}, 版本: {}, 块数: {}, MD5: {}",
                name, version, totalChunks, fileMd5);

        return new UploadResult(name, version, file.getOriginalFilename(),
                file.getSize(), totalChunks, storagePath, fileMd5);
    }

    /**
     * 下载模型文件 (Java 17+ 优化版)
     * 从 IGinX 直接读取二进制数据并合并
     */
    public byte[] downloadModel(String name, String version) throws Exception {
        String storagePath = buildStoragePath(name, version);
        log.info("开始下载模型: {} v{}, 存储路径: {}", name, version, storagePath);

        // 构建查询 - 使用 SimpleQuery (官方示例方式)
        SimpleQuery query = SimpleQuery.builder()
                .addMeasurement(storagePath)   // 添加要查询的 measurement
                .endKey(Long.MAX_VALUE)        // 设置查询结束时间戳
                .build();

        // 执行查询
        IginXTable table = queryClient.query(query);

        if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) {
            throw new Exception("未找到指定的模型文件: " + name + " v" + version);
        }

        // 按时间戳排序并合并数据
        TreeMap<Long, byte[]> chunkMap = new TreeMap<>();

        for (IginXRecord record : table.getRecords()) {
            Long timestamp = record.getKey();

            // 注意: getValues() 返回 Map<String, Object>
            Map<String, Object> valuesMap = record.getValues();

            // 从 Map 中获取对应路径的值
            Object value = valuesMap.get(storagePath);
            if (value instanceof byte[]) {
                // 直接获取二进制数据
                byte[] chunkData = (byte[]) value;
                chunkMap.put(timestamp, chunkData);
            } else if (value != null) {
                // 如果值不是 byte[]，尝试按字符串处理（兼容性回退）
                log.warn("路径 {} 的值类型为 {}，尝试转换为字节数组",
                        storagePath, value.getClass().getSimpleName());
                byte[] chunkData = value.toString().getBytes(StandardCharsets.UTF_8);
                chunkMap.put(timestamp, chunkData);
            }
        }

        // 合并所有块
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        for (byte[] chunk : chunkMap.values()) {
            baos.write(chunk);
        }

        byte[] fileBytes = baos.toByteArray();
        log.info("模型文件下载成功。名称: {}, 版本: {}, 总大小: {} bytes, 块数: {}",
                name, version, fileBytes.length, chunkMap.size());

        return fileBytes;
    }

    /**
     * 检查模型文件是否存在
     */
    public boolean checkModelExists(String name, String version) {
        try {
            String storagePath = buildStoragePath(name, version);

            SimpleQuery query = SimpleQuery.builder()
                    .addMeasurement(storagePath)
                    .endKey(1L)  // 只检查第一个时间戳
                    .build();

            IginXTable table = queryClient.query(query);
            return table != null && table.getRecords() != null && !table.getRecords().isEmpty();

        } catch (Exception e) {
            log.warn("检查模型存在性时发生异常", e);
            return false;
        }
    }

    /**
     * 获取模型的块数信息
     */
    public int getChunkCount(String name, String version) throws Exception {
        String storagePath = buildStoragePath(name, version);

        SimpleQuery query = SimpleQuery.builder()
                .addMeasurement(storagePath)
                .endKey(Long.MAX_VALUE)
                .build();

        IginXTable table = queryClient.query(query);
        return table != null && table.getRecords() != null ? table.getRecords().size() : 0;
    }

    /**
     * 构建存储路径
     */
    private String buildStoragePath(String name, String version) {
        String safeVersion = version.replace('.', '_');
        return String.format("%s.%s.%s", STORAGE_PREFIX, name, safeVersion);
    }

    /**
     * 计算文件的 MD5 校验和
     */
    private String calculateMD5(byte[] bytes) {
        try {
            java.security.MessageDigest md = java.security.MessageDigest.getInstance("MD5");
            byte[] digest = md.digest(bytes);
            StringBuilder sb = new StringBuilder();
            for (byte b : digest) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (Exception e) {
            log.warn("计算 MD5 失败", e);
            return "";
        }
    }

}
