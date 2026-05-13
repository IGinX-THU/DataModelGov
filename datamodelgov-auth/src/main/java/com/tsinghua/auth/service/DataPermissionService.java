package com.tsinghua.auth.service;

import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.WriteClient;
import com.tsinghua.auth.dao.DataPermissionDao;
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

}
