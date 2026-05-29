package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.ClusterInfo;
import cn.edu.tsinghua.iginx.session.Column;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.thrift.RemovedStorageEngineInfo;
import cn.edu.tsinghua.iginx.thrift.StorageEngineInfo;
import cn.edu.tsinghua.iginx.thrift.StorageEngineType;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsinghua.auth.entity.DataPermissionEntity;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.dto.ColumnDto;
import com.tsinghua.dto.StorageEngineInfoDto;
import com.tsinghua.dto.request.BaseStorageEngineRequest;
import com.tsinghua.entity.DataArchiveEntity;
import com.tsinghua.util.ProjectContext;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.CollectionUtils;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;


/**
 * 数据源管理服务
 */
@Slf4j
@Service
public class DataSourceService {

    @Autowired
    private Session iginxSession;

    @Autowired
    private DataPermissionService dataPermissionService;

    @Autowired
    private DataArchiveService dataArchiveService;

    @Autowired
    private ProjectService projectService;

    /**
     * 注册异构数据源
     */
    public boolean registerDataSource(BaseStorageEngineRequest request) throws Exception {
        // 自动添加项目名称前缀
        String projectName = ProjectContext.getCurrentProject("unknown");
        if (projectName != null && !projectName.isEmpty()) {
            String schemaPrefix = request.getSchemaPrefix();
            if (!schemaPrefix.startsWith(projectName + ".")) {
                request.setSchemaPrefix(projectName + "." + schemaPrefix);
                log.info("自动添加项目名称前缀: {} -> {}", schemaPrefix, request.getSchemaPrefix());
            }
        }

        if (dataPermissionService.existTablePrefix(request.getSchemaPrefix())) {
            throw new IllegalArgumentException("数据资源已存在");
        }
        // iginxSession.openSession();
        iginxSession.addStorageEngine(request.getIp(),
                request.getPort(),
                StorageEngineType.findByValue(request.getStorageEngineType()),
                request.buildExtraParams());
        // iginxSession.closeSession();
        dataPermissionService.saveTablePrefix(request.getSchemaPrefix());
        log.info("成功注册数据源: {}", request);

        // 保存数据档案
        saveDataSourceArchive(request);

        // 添加到项目的datas字段
        if (projectName != null && !projectName.isEmpty()) {
            try {
                projectService.addToProject(projectName, request.getSchemaPrefix(), "datas");
            } catch (Exception e) {
                log.error("添加数据路径到项目失败", e);
            }
        }

        return true;
    }

    /**
     * 移除异构数据源
     */
    public boolean removeDataSource(StorageEngineInfoDto storageEngineInfoDto) throws Exception {
        // iginxSession.openSession();
        RemovedStorageEngineInfo removedStorageEngineInfo = new RemovedStorageEngineInfo(storageEngineInfoDto.getIp(), storageEngineInfoDto.getPort(), storageEngineInfoDto.getSchemaPrefix(), storageEngineInfoDto.getDataPrefix());
        List<RemovedStorageEngineInfo> removedStorageEngineList = Collections.singletonList(removedStorageEngineInfo);
        iginxSession.removeStorageEngine(removedStorageEngineList);
        // iginxSession.closeSession();
        dataPermissionService.deleteByTablePrefix(storageEngineInfoDto.getSchemaPrefix());

        // 删除对应的数据档案元数据
        try {
            DataArchiveEntity archive = dataArchiveService.findByName(storageEngineInfoDto.getSchemaPrefix());
            if (archive != null && archive.getId() != null) {
                dataArchiveService.deleteArchive(archive.getId());
                log.info("已删除数据源档案元数据: {}", storageEngineInfoDto.getSchemaPrefix());
            }
        } catch (Exception e) {
            log.error("删除数据源档案元数据失败", e);
        }

        // 从项目的datas字段移除
        String projectName = ProjectContext.getCurrentProject("unknown");
        if (projectName != null && !projectName.isEmpty()) {
            try {
                projectService.removeFromProject(projectName, storageEngineInfoDto.getSchemaPrefix(), "datas");
            } catch (Exception e) {
                log.error("从项目移除数据路径失败", e);
            }
        }

        return true;
    }

    public List<StorageEngineInfoDto> dataSourceList() throws Exception {
        // iginxSession.openSession();
        ClusterInfo clusterInfo = iginxSession.getClusterInfo();
        List<StorageEngineInfo> storageEngineInfos = clusterInfo.getStorageEngineInfos();
        List<StorageEngineInfoDto> storageEngineInfoDtos = storageEngineInfos.stream().map(s -> new StorageEngineInfoDto(s.id, s.ip, s.port, s.type.getValue(), s.schemaPrefix, s.dataPrefix)).collect(Collectors.toList());
        // iginxSession.closeSession();

        if (!AuthUtil.isAdmin()) {
            List<StorageEngineInfoDto> filteredList = new ArrayList<>();
            List<String> accessibleTables = dataPermissionService.getCurrentUserAccessibleTables();
            if (CollectionUtils.isEmpty(accessibleTables)) {
                return filteredList;
            }
            String currentProject = ProjectContext.getCurrentProject(null);
            accessibleTables.forEach(accessibleTable -> filteredList.addAll(
                    storageEngineInfoDtos.stream().filter(storageEngineInfoDto ->
                                    accessibleTable.equalsIgnoreCase(storageEngineInfoDto.getSchemaPrefix()))
                            .filter(column -> {
                                // 如果有当前项目，只返回该项目相关的路径
                                if (currentProject != null && !currentProject.isEmpty()) {
                                    String path = column.getSchemaPrefix();
                                    return path.startsWith(currentProject + ".");
                                }
                                return true;
                            })
                            .collect(Collectors.toList())));
            return filteredList;
        }

        return storageEngineInfoDtos;
    }

    public List<ColumnDto> dataSourceTree() throws Exception {
        // iginxSession.openSession();
        List<Column> columnList = iginxSession.showColumns();
        List<ColumnDto> tree = columnList.stream()
                .filter(column -> !column.getPath().contains("relational_system"))
                .map(column -> new ColumnDto(column.getPath(), column.getDataType().getValue()))
                .collect(Collectors.toList());
        // iginxSession.closeSession();

        if (!AuthUtil.isAdmin()) {
            List<ColumnDto> filteredTree = new ArrayList<>();
            List<String> accessibleTables = dataPermissionService.getCurrentUserAccessibleTables();
            if (CollectionUtils.isEmpty(accessibleTables)) {
                return filteredTree;
            }
            String currentProject = ProjectContext.getCurrentProject(null);

            accessibleTables.forEach(accessibleTable -> filteredTree.addAll(
                    tree.stream().filter(columnDto ->
                                    columnDto.getPath().startsWith(accessibleTable))
                            .filter(column -> {
                                // 如果有当前项目，只返回该项目相关的路径
                                if (currentProject != null && !currentProject.isEmpty()) {
                                    String path = column.getPath();
                                    return path.startsWith(currentProject + ".") ||
                                            path.startsWith("models_system." + currentProject + ".") ||
                                            path.startsWith("algorithms_system." + currentProject + ".");
                                }
                                return false;
                            })
                            .collect(Collectors.toList())));
            return  filteredTree;
        }

        return tree;
    }

    /**
     * 保存数据源档案
     */
    private void saveDataSourceArchive(BaseStorageEngineRequest request) {
        try {
            DataArchiveEntity archive = new DataArchiveEntity();
            archive.setName(request.getSchemaPrefix());
            archive.setType("datasource");
            archive.setDesc(request.getDescription());
            
            log.info("准备保存数据源档案: name={}, desc={}", archive.getName(), archive.getDesc());
            
            // 从上下文获取项目名称和用户名
            String projectName = ProjectContext.getCurrentProject(null);
            archive.setProjectName(projectName);
            archive.setOwner(com.tsinghua.auth.util.AuthUtil.getCurrentUsername());

            // 将请求对象转换为JSON字符串保存到config字段
            ObjectMapper objectMapper = new ObjectMapper();
            String configJson = objectMapper.writeValueAsString(request);
            archive.setConfig(configJson);

            dataArchiveService.saveArchive(archive);
            log.info("数据源档案已保存: {}, desc={}", request.getSchemaPrefix(), archive.getDesc());
        } catch (Exception e) {
            log.error("保存数据源档案失败", e);
            // 不抛出异常，避免影响主流程
        }
    }

}
