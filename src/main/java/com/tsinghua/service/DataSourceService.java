package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.ClusterInfo;
import cn.edu.tsinghua.iginx.session.Column;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.thrift.RemovedStorageEngineInfo;
import cn.edu.tsinghua.iginx.thrift.StorageEngineInfo;
import cn.edu.tsinghua.iginx.thrift.StorageEngineType;
import com.tsinghua.dto.ColumnDto;
import com.tsinghua.dto.DataSourceRequest;
import com.tsinghua.dto.StorageEngineInfoDto;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

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

    /**
     * 注册异构数据源
     */
    public boolean registerDataSource(DataSourceRequest request) {
        try {
            iginxSession.openSession();
            iginxSession.addStorageEngine(request.getIp(),
                    request.getPort(),
                    StorageEngineType.findByValue(request.getStorageEngineType()),
                    request.buildExtraParams());
            iginxSession.closeSession();
            log.info("成功注册数据源: {}", request.getAlias());
            return true;
        } catch (Exception e) {
            log.error("注册数据源失败: {}", request.getAlias(), e);
            return false;
        }
    }

    /**
     * 移除异构数据源
     */
    public boolean removeDataSource(StorageEngineInfoDto storageEngineInfoDto) {
        try {
            iginxSession.openSession();
            RemovedStorageEngineInfo removedStorageEngineInfo = new RemovedStorageEngineInfo(storageEngineInfoDto.getIp(), storageEngineInfoDto.getPort(), storageEngineInfoDto.getSchemaPrefix(), storageEngineInfoDto.getDataPrefix());
            List<RemovedStorageEngineInfo> removedStorageEngineList = Collections.singletonList(removedStorageEngineInfo);
            iginxSession.removeStorageEngine(removedStorageEngineList);
            iginxSession.closeSession();
            return true;
        } catch (Exception e) {
            log.error("移除数据源失败: {}", storageEngineInfoDto, e);
            return false;
        }
    }

    public List<StorageEngineInfoDto> dataSourceList() throws Exception {
        iginxSession.openSession();
        ClusterInfo clusterInfo = iginxSession.getClusterInfo();
        List<StorageEngineInfo> storageEngineInfos = clusterInfo.getStorageEngineInfos();
        List<StorageEngineInfoDto> storageEngineInfoDtos = storageEngineInfos.stream().map(s -> new StorageEngineInfoDto(s.id, s.ip, s.port, s.type.getValue(), s.schemaPrefix, s.dataPrefix)).collect(Collectors.toList());
        iginxSession.closeSession();
        return storageEngineInfoDtos;
    }

    public List<ColumnDto> dataSourceTree() throws Exception {
        iginxSession.openSession();
        List<Column> columnList = iginxSession.showColumns();
        List<ColumnDto> tree = columnList.stream().map(column -> new ColumnDto(column.getPath(), column.getDataType().getValue())).collect(Collectors.toList());
        iginxSession.closeSession();
        return tree;
    }

}
