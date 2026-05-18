package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.query.IginXRecord;
import cn.edu.tsinghua.iginx.session_v2.query.IginXTable;
import cn.edu.tsinghua.iginx.session_v2.query.SimpleQuery;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.entity.ProjectEntity;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.util.*;

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
        if (project.getId() == null || project.getId().isEmpty()) {
            project.setId(UUID.randomUUID().toString());
        }
        
        if (project.getCreateTime() == null) {
            project.setCreateTime(System.currentTimeMillis());
        }
        
        if (project.getUpdateTime() == null) {
            project.setUpdateTime(System.currentTimeMillis());
        }
        
        if (project.getStatus() == null) {
            project.setStatus(true);
        }
        
        saveProjectMetadata(project);
        
        // 添加到项目列表
        addProjectToList(project.getId(), project.getName());
        
        return project;
    }

    /**
     * 更新项目
     */
    public ProjectEntity updateProject(ProjectEntity project) throws Exception {
        project.setUpdateTime(System.currentTimeMillis());
        saveProjectMetadata(project);
        return project;
    }

    /**
     * 删除项目
     */
    public void deleteProject(String projectId) throws Exception {
        String metaPath = META_PREFIX + "." + projectId;
        
        try {
            iginxClient.getDeleteClient().deleteMeasurementsData(
                Collections.singletonList(metaPath), 
                0L, 
                Long.MAX_VALUE
            );
        } catch (Exception e) {
            // 忽略删除失败
        }
        
        // 从项目列表中移除
        removeFromProjectList(projectId);
    }

    /**
     * 查询项目
     */
    public ProjectEntity getProject(String projectId) throws Exception {
        String metaPath = META_PREFIX + "." + projectId;
        
        SimpleQuery query = SimpleQuery.builder()
                .addMeasurement(metaPath)
                .endKey(Long.MAX_VALUE)
                .build();

        IginXTable table = iginxClient.getQueryClient().query(query);
        
        if (table == null || table.getRecords() == null || table.getRecords().isEmpty()) {
            return null;
        }

        ProjectEntity project = new ProjectEntity();
        
        for (IginXRecord record : table.getRecords()) {
            Map<String, Object> values = record.getValues();
            
            if (values.containsKey(metaPath + ".id") && values.get(metaPath + ".id") instanceof byte[]) {
                project.setId(new String((byte[]) values.get(metaPath + ".id"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".name") && values.get(metaPath + ".name") instanceof byte[]) {
                project.setName(new String((byte[]) values.get(metaPath + ".name"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".description") && values.get(metaPath + ".description") instanceof byte[]) {
                project.setDescription(new String((byte[]) values.get(metaPath + ".description"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".type") && values.get(metaPath + ".type") instanceof byte[]) {
                project.setType(new String((byte[]) values.get(metaPath + ".type"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".algorithms") && values.get(metaPath + ".algorithms") instanceof byte[]) {
                project.setAlgorithms(new String((byte[]) values.get(metaPath + ".algorithms"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".models") && values.get(metaPath + ".models") instanceof byte[]) {
                project.setModels(new String((byte[]) values.get(metaPath + ".models"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".dataSources") && values.get(metaPath + ".dataSources") instanceof byte[]) {
                project.setDataSources(new String((byte[]) values.get(metaPath + ".dataSources"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".simulationArchives") && values.get(metaPath + ".simulationArchives") instanceof byte[]) {
                project.setSimulationArchives(new String((byte[]) values.get(metaPath + ".simulationArchives"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".createTime") && values.get(metaPath + ".createTime") instanceof Long) {
                project.setCreateTime((Long) values.get(metaPath + ".createTime"));
            }
            if (values.containsKey(metaPath + ".updateTime") && values.get(metaPath + ".updateTime") instanceof Long) {
                project.setUpdateTime((Long) values.get(metaPath + ".updateTime"));
            }
            if (values.containsKey(metaPath + ".owner") && values.get(metaPath + ".owner") instanceof byte[]) {
                project.setOwner(new String((byte[]) values.get(metaPath + ".owner"), StandardCharsets.UTF_8));
            }
            if (values.containsKey(metaPath + ".status") && values.get(metaPath + ".status") instanceof Boolean) {
                project.setStatus((Boolean) values.get(metaPath + ".status"));
            }
            if (values.containsKey(metaPath + ".config") && values.get(metaPath + ".config") instanceof byte[]) {
                project.setConfig(new String((byte[]) values.get(metaPath + ".config"), StandardCharsets.UTF_8));
            }
        }

        return project;
    }

    /**
     * 查询所有项目
     */
    public List<ProjectEntity> getAllProjects() throws Exception {
        List<String> projectIds = getProjectList();
        List<ProjectEntity> projects = new ArrayList<>();
        
        for (String projectId : projectIds) {
            try {
                ProjectEntity project = getProject(projectId);
                if (project != null) {
                    projects.add(project);
                }
            } catch (Exception e) {
                // 跳过查询失败的项目
            }
        }
        
        return projects;
    }

    /**
     * 搜索项目
     */
    public List<ProjectEntity> searchProjects(String keyword, String searchType) throws Exception {
        List<ProjectEntity> allProjects = getAllProjects();
        List<ProjectEntity> result = new ArrayList<>();
        
        if (keyword == null || keyword.isEmpty()) {
            return allProjects;
        }
        
        String lowerKeyword = keyword.toLowerCase();
        
        for (ProjectEntity project : allProjects) {
            boolean match = false;
            
            switch (searchType) {
                case "name":
                    if (project.getName() != null && project.getName().toLowerCase().contains(lowerKeyword)) {
                        match = true;
                    }
                    break;
                case "algorithm":
                    if (project.getAlgorithms() != null && project.getAlgorithms().toLowerCase().contains(lowerKeyword)) {
                        match = true;
                    }
                    break;
                case "model":
                    if (project.getModels() != null && project.getModels().toLowerCase().contains(lowerKeyword)) {
                        match = true;
                    }
                    break;
                case "data":
                    if (project.getDataSources() != null && project.getDataSources().toLowerCase().contains(lowerKeyword)) {
                        match = true;
                    }
                    break;
                default:
                    // 全局搜索
                    if ((project.getName() != null && project.getName().toLowerCase().contains(lowerKeyword)) ||
                        (project.getDescription() != null && project.getDescription().toLowerCase().contains(lowerKeyword)) ||
                        (project.getAlgorithms() != null && project.getAlgorithms().toLowerCase().contains(lowerKeyword)) ||
                        (project.getModels() != null && project.getModels().toLowerCase().contains(lowerKeyword)) ||
                        (project.getDataSources() != null && project.getDataSources().toLowerCase().contains(lowerKeyword))) {
                        match = true;
                    }
            }
            
            if (match) {
                result.add(project);
            }
        }
        
        return result;
    }

    /**
     * 保存项目元数据
     */
    private void saveProjectMetadata(ProjectEntity project) throws Exception {
        String metaPath = META_PREFIX + "." + project.getId();
        long timestamp = System.currentTimeMillis();

        List<Point> points = new ArrayList<>();

        addMetaPoint(points, metaPath, "id", project.getId(), timestamp);
        addMetaPoint(points, metaPath, "name", project.getName(), timestamp);
        addMetaPoint(points, metaPath, "description", project.getDescription(), timestamp);
        addMetaPoint(points, metaPath, "type", project.getType(), timestamp);
        addMetaPoint(points, metaPath, "algorithms", project.getAlgorithms(), timestamp);
        addMetaPoint(points, metaPath, "models", project.getModels(), timestamp);
        addMetaPoint(points, metaPath, "dataSources", project.getDataSources(), timestamp);
        addMetaPoint(points, metaPath, "simulationArchives", project.getSimulationArchives(), timestamp);
        addMetaPoint(points, metaPath, "createTime", project.getCreateTime(), timestamp);
        addMetaPoint(points, metaPath, "updateTime", project.getUpdateTime(), timestamp);
        addMetaPoint(points, metaPath, "owner", project.getOwner(), timestamp);
        addMetaPoint(points, metaPath, "status", project.getStatus(), timestamp);
        addMetaPoint(points, metaPath, "config", project.getConfig(), timestamp);

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

    private void addMetaPoint(List<Point> points, String metaPath, String field, Boolean value, long timestamp) {
        if (value != null) {
            points.add(Point.builder()
                    .measurement(metaPath + "." + field)
                    .key(timestamp)
                    .binaryValue(value.toString().getBytes())
                    .build());
        }
    }

    /**
     * 获取项目列表
     */
    private List<String> getProjectList() throws Exception {
        SimpleQuery query = SimpleQuery.builder()
                .addMeasurement(PROJECTS_LIST_PREFIX)
                .endKey(Long.MAX_VALUE)
                .build();

        IginXTable table = iginxClient.getQueryClient().query(query);
        
        List<String> projectIds = new ArrayList<>();
        
        if (table != null && table.getRecords() != null) {
            for (IginXRecord record : table.getRecords()) {
                Map<String, Object> values = record.getValues();
                String field = PROJECTS_LIST_PREFIX + ".projectId";
                if (values.containsKey(field) && values.get(field) instanceof byte[]) {
                    projectIds.add(new String((byte[]) values.get(field), StandardCharsets.UTF_8));
                }
            }
        }
        
        return projectIds;
    }

    /**
     * 添加项目到列表
     */
    private void addProjectToList(String projectId, String projectName) throws Exception {
        long timestamp = System.currentTimeMillis();
        
        Point point = Point.builder()
                .measurement(PROJECTS_LIST_PREFIX + ".projectId")
                .key(timestamp)
                .binaryValue(projectId.getBytes())
                .build();
        
        iginxClient.getWriteClient().writePoints(Collections.singletonList(point));
    }

    /**
     * 从项目列表中移除
     */
    private void removeFromProjectList(String projectId) throws Exception {
        // 简化实现：删除整个列表并重建
        try {
            iginxClient.getDeleteClient().deleteMeasurementsData(
                Collections.singletonList(PROJECTS_LIST_PREFIX), 
                0L, 
                Long.MAX_VALUE
            );
        } catch (Exception e) {
            // 忽略删除失败
        }
        
        // 重建列表（跳过已删除的项目）
        List<ProjectEntity> projects = getAllProjects();
        for (ProjectEntity project : projects) {
            if (!project.getId().equals(projectId)) {
                addProjectToList(project.getId(), project.getName());
            }
        }
    }

    /**
     * 导出项目（用于导入）
     */
    public String exportProject(String projectId) throws Exception {
        ProjectEntity project = getProject(projectId);
        if (project == null) {
            throw new IllegalArgumentException("项目不存在");
        }
        
        return objectMapper.writeValueAsString(project);
    }

    /**
     * 导入项目
     */
    public ProjectEntity importProject(String projectJson) throws Exception {
        ProjectEntity project = objectMapper.readValue(projectJson, ProjectEntity.class);
        
        // 生成新的ID
        project.setId(UUID.randomUUID().toString());
        project.setCreateTime(System.currentTimeMillis());
        project.setUpdateTime(System.currentTimeMillis());
        
        return createProject(project);
    }
}
