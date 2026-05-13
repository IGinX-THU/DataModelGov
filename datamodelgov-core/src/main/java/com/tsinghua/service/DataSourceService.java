package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.ClusterInfo;
import cn.edu.tsinghua.iginx.session.Column;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.thrift.RemovedStorageEngineInfo;
import cn.edu.tsinghua.iginx.thrift.StorageEngineInfo;
import cn.edu.tsinghua.iginx.thrift.StorageEngineType;
import com.tsinghua.auth.entity.DataPermissionEntity;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.dto.ColumnDto;
import com.tsinghua.dto.StorageEngineInfoDto;
import com.tsinghua.dto.request.BaseStorageEngineRequest;
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

    /**
     * 注册异构数据源
     */
    public boolean registerDataSource(BaseStorageEngineRequest request) throws Exception {
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
            accessibleTables.forEach(accessibleTable -> filteredList.addAll(
                    storageEngineInfoDtos.stream().filter(storageEngineInfoDto ->
                                    accessibleTable.equalsIgnoreCase(storageEngineInfoDto.getSchemaPrefix()))
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
            accessibleTables.forEach(accessibleTable -> filteredTree.addAll(
                    tree.stream().filter(columnDto ->
                                    columnDto.getPath().startsWith(accessibleTable))
                            .collect(Collectors.toList())));
            return  filteredTree;
        }

        return tree;
    }

}
