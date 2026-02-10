package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session_v2.ClusterClient;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.domain.Storage;
import com.tsinghua.dto.DataSourceDTO;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;


/**
 * 数据源管理服务
 */
@Slf4j
@Service
public class DataSourceService {

    @Autowired
    private IginXClient iginxClient;

    /**
     * 注册异构数据源
     */
    public boolean registerDataSource(Storage storage) {

        // 1. 构建IGinX存储引擎客户端
        ClusterClient clusterClient = iginxClient.getClusterClient();
        // 2. 增加一个底层存储节点
        clusterClient.scaleOutStorage(storage);

        return true;
    }

    /**
     * 移除异构数据源
     */
    public boolean removeDataSource(String alias) {
        try {
            // 实际项目需添加依赖检查：是否被关联规则引用
            String sql = String.format("REMOVE STORAGEENGINE (\"%s\", 0, \"\", \"\")", alias);
            //todo 暂未实现，实际项目需对接IGinX
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

}