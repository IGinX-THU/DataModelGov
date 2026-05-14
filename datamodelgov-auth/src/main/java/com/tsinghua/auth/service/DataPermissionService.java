package com.tsinghua.auth.service;

import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.WriteClient;
import com.tsinghua.auth.dao.DataPermissionDao;
import com.tsinghua.auth.dto.DataPermissionQueryRequest;
import com.tsinghua.auth.dto.DataPermissionUpdateRequest;
import com.tsinghua.auth.entity.DataPermissionEntity;
import com.tsinghua.auth.util.AuthUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.*;

/**
 * 数据权限服务
 * 基于时间戳主键的Entity表权限控制
 */
@Slf4j
@Service
public class DataPermissionService {

    @Autowired
    private DataPermissionDao dataPermissionDao;

    @Autowired
    private IginXClient iginxClient;

    /**
     * 保存数据权限
     */
    public void saveDataPermission(DataPermissionEntity entity) {
        try {
            long timestamp;
            if (entity.getId() != null){
                timestamp = entity.getId();
            } else if (entity.getCreateTime() != null){
                timestamp = entity.getCreateTime();
            } else {
                timestamp = System.currentTimeMillis();
            }

            entity.setId(timestamp);
            entity.setCreateTime(timestamp);

            if (!StringUtils.hasText(entity.getOwner())) {
                entity.setOwner(AuthUtil.getCurrentUsername());
            }

            // 这里需要注入IginXClient，并使用writeClient写入
            WriteClient writeClient = iginxClient.getWriteClient();
            writeClient.writeMeasurement(entity);

            log.info("保存数据权限: 用户={}, 表前缀={}, 时间戳集合={}",
                    entity.getOwner(), entity.getTablePrefix(), entity.getTimestampSet());
            
        } catch (Exception e) {
            log.error("保存数据权限失败: {}", e.getMessage(), e);
            throw new RuntimeException("保存数据权限失败: " + e.getMessage(), e);
        }
    }

    /**
     * 获取当前用户可访问的表前缀列表
     */
    public List<String> getCurrentUserAccessibleTables() {
        String currentUser = AuthUtil.getCurrentUsername("unknown");
        if (currentUser == null || "unknown".equals(currentUser)) {
            return new ArrayList<>();
        }
        return dataPermissionDao.getUserAccessibleTables(currentUser);
    }

    public boolean existTablePrefix(String tablePrefix){
        if (!AuthUtil.isAdmin()) {
            List<DataPermissionEntity> list = dataPermissionDao.findByTablePrefix(tablePrefix);
            return !list.isEmpty();
        }
        return false;
    }

    /**
     * 获取当前用户可访问的表前缀列表
     */
    public List<DataPermissionEntity> getOwnerTables() {
        String currentUser = AuthUtil.getCurrentUsername();
        return dataPermissionDao.findByOwner(currentUser);
    }

    private List<DataPermissionEntity> listOwnerTablesFiltered(DataPermissionQueryRequest request) {
        String currentUser = AuthUtil.getCurrentUsername();
        if (currentUser == null || "unknown".equalsIgnoreCase(currentUser)) {
            return Collections.emptyList();
        }
        List<DataPermissionEntity> all = dataPermissionDao.findByOwner(currentUser);
        String prefix = request != null && StringUtils.hasText(request.getTablePrefix())
                ? request.getTablePrefix().trim().toLowerCase(Locale.ROOT)
                : null;
        List<DataPermissionEntity> filtered = new ArrayList<>();
        for (DataPermissionEntity e : all) {
            if (prefix != null) {
                String tp = e.getTablePrefix() != null ? e.getTablePrefix().toLowerCase(Locale.ROOT) : "";
                if (!tp.contains(prefix)) {
                    continue;
                }
            }
            filtered.add(e);
        }
        filtered.sort(Comparator.comparing(
                DataPermissionEntity::getCreateTime,
                Comparator.nullsLast(Comparator.reverseOrder())));
        return filtered;
    }

    /**
     * 当前用户拥有的权限分页列表（内存分页，与筛选条件一致）
     */
    public List<DataPermissionEntity> queryOwnerTables(DataPermissionQueryRequest request) {
        if (request == null) {
            request = new DataPermissionQueryRequest();
        }
        List<DataPermissionEntity> filtered = listOwnerTablesFiltered(request);
        int page = request.getPage() == null || request.getPage() < 1 ? 1 : request.getPage();
        int pageSize = request.getPageSize() == null || request.getPageSize() < 1 ? 10 : request.getPageSize();
        int from = (page - 1) * pageSize;
        if (from >= filtered.size()) {
            return Collections.emptyList();
        }
        int to = Math.min(from + pageSize, filtered.size());
        return new ArrayList<>(filtered.subList(from, to));
    }

    public long countOwnerTables(DataPermissionQueryRequest request) {
        if (request == null) {
            request = new DataPermissionQueryRequest();
        }
        return listOwnerTablesFiltered(request).size();
    }

    private long primaryKeyOf(DataPermissionEntity e) {
        if (e.getId() != null) {
            return e.getId();
        }
        if (e.getCreateTime() != null) {
            return e.getCreateTime();
        }
        return -1L;
    }

    /**
     * 更新当前用户名下某条权限的公开范围与可见用户（不可改表前缀、所有者等）
     */
    public void updateOwnerPermission(DataPermissionUpdateRequest req) {
        String currentUser = AuthUtil.getCurrentUsername();
        if (currentUser == null || "unknown".equalsIgnoreCase(currentUser)) {
            throw new IllegalStateException("未登录");
        }
        long id = req.getId();
        DataPermissionEntity existing = null;
        for (DataPermissionEntity e : dataPermissionDao.findByOwner(currentUser)) {
            if (primaryKeyOf(e) == id) {
                existing = e;
                break;
            }
        }
        if (existing == null) {
            throw new IllegalArgumentException("记录不存在或无权修改");
        }
        if (req.getIsPublic() != null) {
            existing.setPublic(req.getIsPublic());
        }
        if (req.getVisibleUsers() != null) {
            existing.setVisibleUsers(req.getVisibleUsers());
        }
        existing.setId(id);
        existing.setCreateTime(id);
        saveDataPermission(existing);
    }

    /**
     * 删除
     */
    public void deleteByTablePrefix(String tablePrefix) {
        try {
            // 先查询用户获取时间戳
            List<DataPermissionEntity> list = dataPermissionDao.findByTablePrefix(tablePrefix);
            if (list.isEmpty()) {
                log.warn("权限不存在，无法删除: {}", tablePrefix);
                return;
            }
            list.forEach(dataPermissionEntity ->
                    dataPermissionDao.deleteById(dataPermissionEntity.getCreateTime()));
            log.info("权限已删除: {}", tablePrefix);
        } catch (Exception e) {
            log.error("删除用户失败: {}", e.getMessage(), e);
            throw new RuntimeException("删除用户失败: " + e.getMessage(), e);
        }
    }

    /**
     * 保存
     */
    public void saveTablePrefix(String tablePrefix) {
        if (!AuthUtil.isAdmin()) {
            DataPermissionEntity dataPermissionEntity = DataPermissionEntity.builder()
                    .tablePrefix(tablePrefix)
                    .isPublic(false)
                    .build();
            saveDataPermission(dataPermissionEntity);
        }
    }

    /**
     * 保存
     */
    public void saveTablePrefix(String tablePrefix, boolean isPublic, String owner) {
        if (!AuthUtil.isAdmin()) {
            DataPermissionEntity dataPermissionEntity = DataPermissionEntity.builder()
                    .tablePrefix(tablePrefix)
                    .isPublic(isPublic)
                    .owner(owner)
                    .build();
            saveDataPermission(dataPermissionEntity);
        }
    }

}
