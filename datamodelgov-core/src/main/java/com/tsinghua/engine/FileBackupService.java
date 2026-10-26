package com.tsinghua.engine;

import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.tsinghua.entity.FileLibraryEntity;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.TreeMap;

/**
 * 项目文件库的 IginX 分块备份与恢复(镜像旧版 ModelFileService 的 64KB 分块读写):
 * 上传入库时把文件分块写入 files_system.<projectId>.<fileId>(块序号作时间戳),
 * 本地文件丢失时按 chunkCount 拼块 + MD5 校验后恢复到原路径。
 */
@Slf4j
@Service
public class FileBackupService {

    private static final int CHUNK_SIZE = 65536; // 64KB

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private FileLibraryMetaService metaService;

    public static String storagePath(FileLibraryEntity e) {
        return "files_system." + e.getProjectId() + "." + e.getId();
    }

    public static String md5Hex(byte[] bytes) {
        try {
            byte[] d = MessageDigest.getInstance("MD5").digest(bytes);
            StringBuilder sb = new StringBuilder();
            for (byte b : d) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (Exception e) {
            return "";
        }
    }

    /** 分块备份到 IginX,回填 fileMd5/chunkCount/backupState;失败置 failed 不抛出。 */
    public void backup(FileLibraryEntity entity, File file) {
        try {
            byte[] bytes = Files.readAllBytes(file.toPath());
            int totalChunks = bytes.length == 0 ? 1 : (int) Math.ceil((double) bytes.length / CHUNK_SIZE);
            String path = storagePath(entity);
            List<Point> points = new ArrayList<>();
            for (int i = 0; i < totalChunks; i++) {
                int start = i * CHUNK_SIZE;
                int end = Math.min(bytes.length, start + CHUNK_SIZE);
                byte[] chunk = Arrays.copyOfRange(bytes, start, end);
                points.add(Point.builder()
                        .measurement(path)
                        .key(i)
                        .binaryValue(chunk)
                        .build());
            }
            iginxClient.getWriteClient().writePoints(points);
            entity.setChunkCount(totalChunks);
            entity.setFileMd5(md5Hex(bytes));
            entity.setBackupState("done");
            metaService.save(entity);
            log.info("文件库IginX备份完成: {} -> {} ({}块, {}字节)", entity.getName(), path, totalChunks, bytes.length);
        } catch (Exception e) {
            log.warn("文件库IginX备份失败(本地文件仍可用): {}", entity.getName(), e);
            entity.setBackupState("failed");
            try {
                metaService.save(entity);
            } catch (Exception ignore) { }
        }
    }

    /** 本地文件存在直接返回;缺失则从 IginX 恢复到原路径(MD5 校验)。 */
    public File resolve(FileLibraryEntity entity) throws Exception {
        File f = new File(entity.getPath());
        if (f.isFile()) return f;
        if (entity.getChunkCount() == null || entity.getChunkCount() <= 0
                || entity.getFileMd5() == null || entity.getFileMd5().isEmpty()) {
            throw new Exception("本地文件缺失且IginX备份不可用: " + entity.getName());
        }
        String path = storagePath(entity);
        TreeMap<Integer, byte[]> chunkMap = new TreeMap<>();
        cn.edu.tsinghua.iginx.session_v2.query.SimpleQuery query = cn.edu.tsinghua.iginx.session_v2.query.SimpleQuery.builder()
                .addMeasurement(path)
                .endKey(Long.MAX_VALUE)
                .build();
        IginXTable table = iginxClient.getQueryClient().query(query);
        if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) {
            throw new Exception("本地文件缺失且IginX备份数据不存在: " + entity.getName());
        }
        for (IginXRecord record : table.getRecords()) {
            Long ts = record.getKey();
            Object value = record.getValues().get(path);
            if (value instanceof byte[]) {
                chunkMap.put(ts.intValue(), (byte[]) value);
            } else if (value != null) {
                chunkMap.put(ts.intValue(), value.toString().getBytes(StandardCharsets.UTF_8));
            }
        }
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        for (int i = 0; i < entity.getChunkCount(); i++) {
            byte[] chunk = chunkMap.get(i);
            if (chunk == null) throw new Exception("IginX备份不完整,缺少第 " + i + " 块: " + entity.getName());
            baos.write(chunk);
        }
        byte[] bytes = baos.toByteArray();
        String actual = md5Hex(bytes);
        if (!actual.equals(entity.getFileMd5())) {
            throw new Exception("IginX备份恢复校验失败(MD5不匹配): " + entity.getName());
        }
        File dst = new File(entity.getPath());
        if (dst.getParentFile() != null && !dst.getParentFile().exists() && !dst.getParentFile().mkdirs()) {
            throw new Exception("无法重建文件目录: " + dst.getParentFile());
        }
        try (FileOutputStream fos = new FileOutputStream(dst)) {
            fos.write(bytes);
        }
        log.info("文件库本地文件已从IginX备份恢复: {} ({}字节)", entity.getName(), bytes.length);
        return dst;
    }

    /** 清理 IginX 备份分块(删除条目时调用)。 */
    public void deleteBackup(FileLibraryEntity entity) {
        if (entity == null || entity.getId() == null) return;
        try {
            String path = storagePath(entity);
            List<String> measurements = new ArrayList<>();
            measurements.add(path);
            int upper = (entity.getChunkCount() == null ? 0 : entity.getChunkCount()) + 2;
            iginxClient.getDeleteClient().deleteMeasurementsData(measurements, -1, upper);
        } catch (Exception e) {
            log.warn("清理文件库IginX备份失败: {}", entity.getName(), e);
        }
    }
}
