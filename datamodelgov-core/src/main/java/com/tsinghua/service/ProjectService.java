package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.WriteClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.query.SimpleQuery;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.ProjectEntity;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.nio.charset.StandardCharsets;
import java.util.*;

@Slf4j
@Service
public class ProjectService {

    private static final String META_PREFIX = "relational_system.projects";
    private static final String PROJECTS_LIST_PREFIX = "relational_system.projects_list";

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private DataPermissionService dataPermissionService;

    @Autowired
    private ObjectMapper objectMapper;

    /**
     * 创建项目
     */
    public ProjectEntity createProject(ProjectEntity project) throws Exception {

        
        saveProjectMetadata(project);

        return project;
    }


    /**
     * 保存项目元数据
     */
    private void saveProjectMetadata(ProjectEntity entity) throws Exception {

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

        log.info("项目保存成功: {}", entity);

    }

}
