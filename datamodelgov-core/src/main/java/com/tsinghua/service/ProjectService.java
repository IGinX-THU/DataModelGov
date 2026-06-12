package com.tsinghua.service;

import cn.edu.tsinghua.iginx.exception.SessionException;
import cn.edu.tsinghua.iginx.session.Column;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.WriteClient;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.dto.ProjectTree;
import com.tsinghua.dto.ProjectsQueryRequest;
import com.tsinghua.entity.ProjectEntity;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsinghua.enums.PathConstants;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
public class ProjectService {

    private static final String META_PREFIX = PathConstants.PROJECT_META_PREFIX;

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private Session iginxSession;

    @Autowired
    private DataPermissionService dataPermissionService;

    @Autowired
    private ObjectMapper objectMapper;

    /**
     * 创建项目
     */
    public ProjectEntity createProject(ProjectEntity project) throws Exception {

        ProjectEntity projectEntity = findByName(project.getName());
        if (projectEntity != null) {
            log.error("项目已存在: {}", project.getName());
            throw new IllegalArgumentException("项目已存在");
        }
        // 2. 创建任务目录 (相对于项目根目录的tasks文件夹下)
        Path taskDir = Paths.get(PathConstants.PROJECT_PATH, project.getName());
        Files.createDirectories(taskDir);
        log.info("创建工程目录: {}", taskDir);
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

    public ProjectEntity findByName(String name) {
        try {
            String sql = "select * from %s where name = '%s' ;";
            SessionExecuteSqlResult res =  iginxSession.executeSql(String.format(sql, PathConstants.PROJECT_META_PREFIX, name));
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            if (records.isEmpty()) {
                return null;
            }

            ProjectEntity entity = new ProjectEntity();
            Map<String, Object> rs = records.get(0);
            // 使用ConvertUtil的通用方法设置字段值
            return ConvertUtil.mapToEntity(entity, rs, PathConstants.PROJECT_META_PREFIX);
        } catch (Exception e) {
            log.error("查询失败", e);
            return null;
        }
    }

    /**
     * 查询解析规则详情
     * 参考queryMeta逻辑，只用createTime作为唯一标识
     */
    public ProjectEntity findById(Long createTime) {
        try {
            String sql = "select * from %s where createTime = %s limit 1;";
            SessionExecuteSqlResult res = iginxSession.executeSql(String.format(sql, PathConstants.PROJECT_META_PREFIX, createTime));
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            if (records.isEmpty()) {
                return null;
            }

            ProjectEntity entity = new ProjectEntity();
            Map<String, Object> rs = records.get(0);
            // 使用ConvertUtil的通用方法设置字段值
            return ConvertUtil.mapToEntity(entity, rs, PathConstants.PROJECT_META_PREFIX);
        } catch (Exception e) {
            log.error("查询解析规则失败", e);
            return null;
        }
    }

    public ProjectTree buildProjectTree(String name) throws Exception {
        ProjectTree projectTree = new ProjectTree();
        ProjectEntity project = findByName(name);
        if (project == null) {
            return null;
        }
        List<Column> columnList = iginxSession.showColumns();
        List<String> accessiblePaths = columnList.stream().map(Column::getPath).collect(Collectors.toList());
        projectTree.setName(project.getName());
        if (StringUtils.hasText(project.getAlgorithms())) {
            projectTree.setAlgorithms(Arrays.stream(project.getAlgorithms().split(","))
                    .filter(path -> accessiblePaths.stream().anyMatch(accessiblePath -> accessiblePath.startsWith(path)))
                    .distinct().collect(Collectors.toList()));
        }
        if (StringUtils.hasText(project.getModels())) {
            projectTree.setModels(Arrays.stream(project.getModels().split(","))
                    .filter(path -> accessiblePaths.stream().anyMatch(accessiblePath -> accessiblePath.startsWith(path)))
                    .distinct().collect(Collectors.toList()));
        }
        if (StringUtils.hasText(project.getDatas())) {
            projectTree.setDatas(Arrays.stream(project.getDatas().split(","))
                    .filter(path -> accessiblePaths.stream().anyMatch(accessiblePath -> accessiblePath.startsWith(path)))
                    .distinct().collect(Collectors.toList()));
        }
        return projectTree;
    }

    /**
     * 分页查询解析规则
     */
    public List<ProjectEntity> queryProjects(ProjectsQueryRequest request) {
        try {
            // 构建基础SQL
            StringBuilder sql = new StringBuilder("SELECT * FROM relational_system.project WHERE 1=1");

            // 添加筛选条件
            if (request.getName() != null && !request.getName().trim().isEmpty()) {
                sql.append(" AND name LIKE '^.*").append(request.getName().trim()).append(".*'");
            }

            if (request.getAlgorithm() != null && !request.getAlgorithm().trim().isEmpty()) {
                sql.append(" AND algorithms LIKE '^.*").append(request.getAlgorithm().trim()).append(".*'");
            }

            if (request.getModel() != null && !request.getModel().trim().isEmpty()) {
                sql.append(" AND models LIKE '^.*").append(request.getModel().trim()).append(".*'");
            }

            if (request.getData() != null && !request.getData().trim().isEmpty()) {
                sql.append(" AND datas LIKE '^.*").append(request.getData().trim()).append(".*'");
            }

            if (!AuthUtil.isAdmin()) {
                sql.append(" AND owner = '").append(AuthUtil.getCurrentUsername()).append("'");
            }

            // 添加排序和分页
            sql.append(" LIMIT ").append(request.getPageSize());
            sql.append(" OFFSET ").append((request.getPageNum() - 1) * request.getPageSize());
            sql.append(";");

            log.info("执行SQL: {}", sql);

            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            // 转换为ParsingRulesEntity列表 - 参考ModelFileService的转换方式
            List<ProjectEntity> result = records.stream().map(record -> {
                ProjectEntity entity = new ProjectEntity();
                // 使用ConvertUtil的通用方法设置字段值 - 参考ModelFileService.queryMeta
                ConvertUtil.mapToEntity(entity, record, PathConstants.PROJECT_META_PREFIX);
                return entity;
            }).collect(Collectors.toList());

            log.info("查询结果: records={}", result.size());
            return result;
        } catch (Exception e) {
            log.error("查询失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 查询解析规则总数
     */
    public Object countProjects(ProjectsQueryRequest request) {
        try {
            // 构建基础SQL
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM relational_system.project WHERE 1=1");

            // 添加筛选条件
            if (request.getName() != null && !request.getName().trim().isEmpty()) {
                sql.append(" AND name LIKE '^.*").append(request.getName().trim()).append(".*'");
            }

            if (request.getAlgorithm() != null && !request.getAlgorithm().trim().isEmpty()) {
                sql.append(" AND algorithms LIKE '^.*").append(request.getAlgorithm().trim()).append(".*'");
            }

            if (request.getModel() != null && !request.getModel().trim().isEmpty()) {
                sql.append(" AND models LIKE '^.*").append(request.getModel().trim()).append(".*'");
            }

            if (request.getData() != null && !request.getData().trim().isEmpty()) {
                sql.append(" AND datas LIKE '^.*").append(request.getData().trim()).append(".*'");
            }

            if (!AuthUtil.isAdmin()) {
                sql.append(" AND owner = '").append(AuthUtil.getCurrentUsername()).append("'");
            }

            sql.append(";");

            log.info("执行COUNT SQL: {}", sql);

            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());

            return res.getValues().get(0).get(0);
        } catch (Exception e) {
            log.error("查询失败", e);
            return 0;
        }
    }

    /**
     * 添加路径到项目（通用方法，支持datas/models/algorithms）
     */
    public void addToProject(String projectName, String path, String fieldType) throws Exception {
        if (projectName == null || projectName.isEmpty()) {
            log.warn("项目名称为空，跳过添加路径");
            return;
        }
        if (path == null || path.isEmpty()) {
            log.warn("路径为空，跳过添加");
            return;
        }

        ProjectEntity project = findByName(projectName);
        if (project == null) {
            log.warn("项目不存在: {}", projectName);
            return;
        }

        String currentValue = getFieldValue(project, fieldType);
        String newValue;
        if (currentValue == null || currentValue.isEmpty()) {
            newValue = path;
        } else {
            String[] existingItems = currentValue.split(",");
            for (String existing : existingItems) {
                if (existing.trim().equals(path)) {
                    log.info("路径已存在: {} (字段: {})", path, fieldType);
                    return;
                }
            }
            newValue = currentValue + "," + path;
        }

        setFieldValue(project, fieldType, newValue);
        saveProjectMetadata(project);
        log.info("已添加路径到项目: {}, 字段: {}, 路径: {}", projectName, fieldType, path);
    }

    /**
     * 从项目移除路径（通用方法，支持datas/models/algorithms）
     */
    public void removeFromProject(String projectName, String path, String fieldType) throws Exception {
        if (projectName == null || projectName.isEmpty()) {
            log.warn("项目名称为空，跳过移除路径");
            return;
        }
        if (path == null || path.isEmpty()) {
            log.warn("路径为空，跳过移除");
            return;
        }

        ProjectEntity project = findByName(projectName);
        if (project == null) {
            log.warn("项目不存在: {}", projectName);
            return;
        }

        String currentValue = getFieldValue(project, fieldType);
        if (currentValue == null || currentValue.isEmpty()) {
            log.info("项目的{}字段为空，无需移除", fieldType);
            return;
        }

        String[] existingItems = currentValue.split(",");
        List<String> newList = new ArrayList<>();
        for (String existing : existingItems) {
            if (!existing.trim().equals(path)) {
                newList.add(existing.trim());
            }
        }

        String newValue = String.join(",", newList);
        setFieldValue(project, fieldType, newValue);
        saveProjectMetadata(project);
        log.info("已从项目移除路径: {}, 字段: {}, 路径: {}", projectName, fieldType, path);
    }

    private String getFieldValue(ProjectEntity project, String fieldType) {
        switch (fieldType) {
            case "datas": return project.getDatas();
            case "models": return project.getModels();
            case "algorithms": return project.getAlgorithms();
            default: return null;
        }
    }

    private void setFieldValue(ProjectEntity project, String fieldType, String value) {
        switch (fieldType) {
            case "datas": project.setDatas(value); break;
            case "models": project.setModels(value); break;
            case "algorithms": project.setAlgorithms(value); break;
        }
    }

}
