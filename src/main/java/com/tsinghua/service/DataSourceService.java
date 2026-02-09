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

//    @Autowired
    private IginXClient iginxClient;

    /**
     * 注册异构数据源
     */
    public boolean registerDataSource(Storage storage) {
        try {
            // 1. 构建IGinX存储引擎添加命令
//            String extraParams = buildExtraParams(dto);
//            String sql = String.format(
//                    "ADD STORAGEENGINE (\"%s\", %d, \"%s\", \"%s\")",
//                    dto.getIp(), dto.getPort(), dto.getType(), extraParams
//            );
            // 2. 执行SQL注册
//            iginxClient.executeSql(sql);
            ClusterClient clusterClient = iginxClient.getClusterClient();
            clusterClient.scaleOutStorage(storage);
            return true;
        } catch (Exception e) {
            log.error("注册异构数据源失败", e);
            return false;
        }
    }

    /**
     * 移除异构数据源
     */
    public boolean removeDataSource(String alias) {
        try {
            // 实际项目需添加依赖检查：是否被关联规则引用
            String sql = String.format("REMOVE STORAGEENGINE (\"%s\", 0, \"\", \"\")", alias);
//            iginxClient.executeSql(sql);
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * 构建额外参数
     */
    private String buildExtraParams(DataSourceDTO dto) {
        StringBuilder params = new StringBuilder();
        params.append("username=").append(dto.getUsername())
                .append(",password=").append(dto.getPassword())
                .append(",iginx_port=8080");
        if (dto.getExtraParams() != null && !dto.getExtraParams().isEmpty()) {
            params.append(",").append(dto.getExtraParams());
        }
        return params.toString();
    }
}