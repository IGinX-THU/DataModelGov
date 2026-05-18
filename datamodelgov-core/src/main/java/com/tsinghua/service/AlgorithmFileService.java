package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.query.SimpleQuery;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.entity.AlgorithmMetaEntity;
import com.tsinghua.dto.UploadResult;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.*;

@Service
public class AlgorithmFileService {

    private static final int CHUNK_SIZE = 65536; // 64KB
    private static final String STORAGE_PREFIX = "algorithms_system";
    private static final String META_PREFIX = "relational_system.algorithms_meta";

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private DataPermissionService dataPermissionService;

    /**
     * 上传算法文件
     */
    public UploadResult uploadAlgorithm(MultipartFile file, String name, String version) throws Exception {
        String storagePath = buildStoragePath(name, version);

        if (dataPermissionService.existTablePrefix(storagePath)) {
            throw new IllegalArgumentException("算法资产已存在");
        }

        byte[] fileBytes = file.getBytes();
        int totalChunks = (int) Math.ceil((double) fileBytes.length / CHUNK_SIZE);

        // 准备数据点列表
        List<Point> points = new ArrayList<>();

        // 分块存储
        for (int i = 0; i < totalChunks; i++) {
            int start = i * CHUNK_SIZE;
            int end = Math.min(start + CHUNK_SIZE, fileBytes.length);
            byte[] chunk = Arrays.copyOfRange(fileBytes, start, end);

            // 构建数据点 - 直接存储二进制数据
            Point point = Point.builder()
                    .measurement(storagePath)
                    .key((long) i)
                    .binaryValue(chunk)
                    .build();
            points.add(point);
        }

        // 批量写入数据点
        iginxClient.getWriteClient().writePoints(points);

        // 计算MD5
        String md5 = calculateMD5(fileBytes);

        // 保存元数据
        AlgorithmMetaEntity meta = new AlgorithmMetaEntity();
        meta.setName(name);
        meta.setVersion(version);
        meta.setFileName(file.getOriginalFilename());
        meta.setFileSize((long) fileBytes.length);
        meta.setChunkCount(totalChunks);
        meta.setStoragePath(storagePath);
        meta.setFileMd5(md5);
        meta.setTimestamp(System.currentTimeMillis());

        saveAlgorithmMetadata(meta);

        UploadResult result = new UploadResult();
        result.setName(name);
        result.setVersion(version);
        result.setFileName(file.getOriginalFilename());
        result.setFileSize(fileBytes.length);
        result.setChunkCount(totalChunks);
        result.setStoragePath(storagePath);
        result.setFileMd5(md5);

        return result;
    }

    /**
     * 下载算法文件
     */
    public byte[] downloadAlgorithm(String name, String version) throws Exception {
        String storagePath = buildStoragePath(name, version);
        AlgorithmMetaEntity meta = queryMeta(name, version);
        
        if (meta == null) {
            throw new IllegalArgumentException("算法不存在");
        }

        TreeMap<Integer, byte[]> chunkMap = new TreeMap<>();

        // 构建查询
        SimpleQuery query = SimpleQuery.builder()
                .addMeasurement(storagePath)
                .endKey(Long.MAX_VALUE)
                .build();

        IginXTable table = iginxClient.getQueryClient().query(query);

        if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) {
            throw new Exception("未找到指定的算法文件数据: " + name + " v" + version);
        }

        // 按块序号组织数据
        for (IginXRecord record : table.getRecords()) {
            Long timestamp = record.getKey();
            Map<String, Object> valuesMap = record.getValues();
            Object value = valuesMap.get(storagePath);

            if (value instanceof byte[]) {
                byte[] chunkData = (byte[]) value;
                int chunkIndex = timestamp.intValue();
                chunkMap.put(chunkIndex, chunkData);
            }
        }

        // 按序合并所有块
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        for (int i = 0; i < meta.getChunkCount(); i++) {
            byte[] chunk = chunkMap.get(i);
            if (chunk == null) {
                throw new Exception("文件数据不完整，缺少第 " + i + " 个文件块");
            }
            baos.write(chunk);
        }

        return baos.toByteArray();
    }

    /**
     * 查询算法元数据
     */
    public AlgorithmMetaEntity queryMeta(String name, String version) throws Exception {
        String metaPath = META_PREFIX + "." + name + "_" + version;
        
        SimpleQuery query = SimpleQuery.builder()
                .addMeasurement(metaPath)
                .endKey(Long.MAX_VALUE)
                .build();

        IginXTable table = iginxClient.getQueryClient().query(query);
        
        if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) {
            return null;
        }

        AlgorithmMetaEntity meta = new AlgorithmMetaEntity();
        
        for (IginXRecord record : table.getRecords()) {
            Map<String, Object> values = record.getValues();
            
            if (values.containsKey(metaPath + ".name") && values.get(metaPath + ".name") instanceof byte[]) {
                meta.setName(new String((byte[]) values.get(metaPath + ".name"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".version") && values.get(metaPath + ".version") instanceof byte[]) {
                meta.setVersion(new String((byte[]) values.get(metaPath + ".version"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".fileName") && values.get(metaPath + ".fileName") instanceof byte[]) {
                meta.setFileName(new String((byte[]) values.get(metaPath + ".fileName"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".fileSize") && values.get(metaPath + ".fileSize") instanceof Long) {
                meta.setFileSize((Long) values.get(metaPath + ".fileSize"));
            }
            if (values.containsKey(metaPath + ".chunkCount") && values.get(metaPath + ".chunkCount") instanceof Integer) {
                meta.setChunkCount((Integer) values.get(metaPath + ".chunkCount"));
            }
            if (values.containsKey(metaPath + ".storagePath") && values.get(metaPath + ".storagePath") instanceof byte[]) {
                meta.setStoragePath(new String((byte[]) values.get(metaPath + ".storagePath"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".fileMd5") && values.get(metaPath + ".fileMd5") instanceof byte[]) {
                meta.setFileMd5(new String((byte[]) values.get(metaPath + ".fileMd5"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".author") && values.get(metaPath + ".author") instanceof byte[]) {
                meta.setAuthor(new String((byte[]) values.get(metaPath + ".author"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".scene") && values.get(metaPath + ".scene") instanceof byte[]) {
                meta.setScene(new String((byte[]) values.get(metaPath + ".scene"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".inputs") && values.get(metaPath + ".inputs") instanceof byte[]) {
                meta.setInputs(new String((byte[]) values.get(metaPath + ".inputs"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".outputs") && values.get(metaPath + ".outputs") instanceof byte[]) {
                meta.setOutputs(new String((byte[]) values.get(metaPath + ".outputs"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".timestamp") && values.get(metaPath + ".timestamp") instanceof Long) {
                meta.setTimestamp((Long) values.get(metaPath + ".timestamp"));
            }
            if (values.containsKey(metaPath + ".cmd") && values.get(metaPath + ".cmd") instanceof byte[]) {
                meta.setCmd(new String((byte[]) values.get(metaPath + ".cmd"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".inputFile") && values.get(metaPath + ".inputFile") instanceof byte[]) {
                meta.setInputFile(new String((byte[]) values.get(metaPath + ".inputFile"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".outputFile") && values.get(metaPath + ".outputFile") instanceof byte[]) {
                meta.setOutputFile(new String((byte[]) values.get(metaPath + ".outputFile"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".algorithmType") && values.get(metaPath + ".algorithmType") instanceof byte[]) {
                meta.setAlgorithmType(new String((byte[]) values.get(metaPath + ".algorithmType"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".dependencies") && values.get(metaPath + ".dependencies") instanceof byte[]) {
                meta.setDependencies(new String((byte[]) values.get(metaPath + ".dependencies"), StandardCharsets.UTF_8));
            }
        }

        return meta;
    }

    /**
     * 保存算法元数据
     */
    public void saveAlgorithmMetadata(AlgorithmMetaEntity meta) throws Exception {
        String metaPath = META_PREFIX + "." + meta.getName() + "_" + meta.getVersion();
        long timestamp = System.currentTimeMillis();

        List<Point> points = new ArrayList<>();

        addMetaPoint(points, metaPath, "name", meta.getName(), timestamp);
        addMetaPoint(points, metaPath, "version", meta.getVersion(), timestamp);
        addMetaPoint(points, metaPath, "fileName", meta.getFileName(), timestamp);
        addMetaPoint(points, metaPath, "fileSize", meta.getFileSize(), timestamp);
        addMetaPoint(points, metaPath, "chunkCount", meta.getChunkCount(), timestamp);
        addMetaPoint(points, metaPath, "storagePath", meta.getStoragePath(), timestamp);
        addMetaPoint(points, metaPath, "fileMd5", meta.getFileMd5(), timestamp);
        addMetaPoint(points, metaPath, "author", meta.getAuthor(), timestamp);
        addMetaPoint(points, metaPath, "scene", meta.getScene(), timestamp);
        addMetaPoint(points, metaPath, "inputs", meta.getInputs(), timestamp);
        addMetaPoint(points, metaPath, "outputs", meta.getOutputs(), timestamp);
        addMetaPoint(points, metaPath, "timestamp", meta.getTimestamp(), timestamp);
        addMetaPoint(points, metaPath, "cmd", meta.getCmd(), timestamp);
        addMetaPoint(points, metaPath, "inputFile", meta.getInputFile(), timestamp);
        addMetaPoint(points, metaPath, "outputFile", meta.getOutputFile(), timestamp);
        addMetaPoint(points, metaPath, "algorithmType", meta.getAlgorithmType(), timestamp);
        addMetaPoint(points, metaPath, "dependencies", meta.getDependencies(), timestamp);

        iginxClient.getWriteClient().writePoints(points);
    }

    private void addMetaPoint(List<Point> points, String metaPath, String field, String value, long timestamp) {
        if (value != null) {
            points.add(Point.builder()
                    .measurement(metaPath + "." + field)
                    .key(timestamp)
                    .binaryValue(value.getBytes())
                    .build());
        }
    }

    private void addMetaPoint(List<Point> points, String metaPath, String field, Long value, long timestamp) {
        if (value != null) {
            points.add(Point.builder()
                    .measurement(metaPath + "." + field)
                    .key(timestamp)
                    .longValue(value)
                    .build());
        }
    }

    private void addMetaPoint(List<Point> points, String metaPath, String field, Integer value, long timestamp) {
        if (value != null) {
            points.add(Point.builder()
                    .measurement(metaPath + "." + field)
                    .key(timestamp)
                    .intValue(value)
                    .build());
        }
    }

    /**
     * 查询算法元数据历史
     */
    public List<AlgorithmMetaEntity> queryMetaList(String name) throws Exception {
        // 查询所有版本的算法元数据
        String prefix = META_PREFIX + "." + name;
        // 这里简化实现，实际需要根据IGinX的查询API调整
        List<AlgorithmMetaEntity> result = new ArrayList<>();
        // TODO: 实现版本列表查询
        return result;
    }

    /**
     * 删除算法
     */
    public void deleteAlgorithm(String name, String version) throws Exception {
        String storagePath = buildStoragePath(name, version);
        String metaPath = META_PREFIX + "." + name + "_" + version;

        // 删除存储的文件数据
        try {
            iginxClient.getDeleteClient().deleteMeasurementsData(
                Collections.singletonList(storagePath), 
                0L, 
                Long.MAX_VALUE
            );
        } catch (Exception e) {
            // 忽略删除失败
        }

        // 删除元数据
        try {
            iginxClient.getDeleteClient().deleteMeasurementsData(
                Collections.singletonList(metaPath), 
                0L, 
                Long.MAX_VALUE
            );
        } catch (Exception e) {
            // 忽略删除失败
        }
    }

    private String buildStoragePath(String name, String version) {
        return STORAGE_PREFIX + "." + name + "_" + version;
    }

    private String calculateMD5(byte[] data) throws Exception {
        MessageDigest md = MessageDigest.getInstance("MD5");
        byte[] hash = md.digest(data);
        StringBuilder sb = new StringBuilder();
        for (byte b : hash) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}
