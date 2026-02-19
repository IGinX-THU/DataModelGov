package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;
import org.springframework.util.StringUtils;

import javax.validation.constraints.NotNull;
import java.time.Duration;
import java.util.Map;
import java.util.HashMap;

/**
 * 文件系统存储引擎注册请求
 * 基于文档 12.3.1 节"文件系统存储"的参数表格
 */
@Data
@EqualsAndHashCode(callSuper = true)
@ApiModel(description = "文件系统存储引擎注册请求")
public class FilesystemStorageRequest extends BaseStorageEngineRequest {

    // ==================== IGinX端口参数 ====================

    /**
     * IGinX节点端口 (iginx_port)
     * 文档3.3.1节: 与ip结合唯一标识某个IGinX服务节点
     */
    @NotNull(message = "iginx_port参数不能为空")
    @ApiModelProperty(value = "IGinX节点端口", example = "6888", required = true)
    private Integer iginxPort;

    // ==================== 核心路径参数 ====================

    /**
     * IGinX 数据存储目录 (dir)
     * 当 is_read_only 被设置为 false 时，要求参数被设置
     */
    @ApiModelProperty(value = "IGinX数据存储目录（非只读时必须设置）")
    private String dir;

    /**
     * 历史数据文件读取目录 (dummy_dir)
     * 当 has_data 被设置为 true 时，要求该参数被设置
     */
    @ApiModelProperty(value = "历史数据文件读取目录（has_data=true时必须设置）")
    private String dummyDir;

    /**
     * 历史数据的数据路径前缀 (embedded_prefix)
     * 默认值: dummy_dir 的目录名
     */
    @ApiModelProperty(value = "历史数据的数据路径前缀")
    private String embeddedPrefix;

    // ==================== 数据结构参数 ====================

    /**
     * 指定将 IGinX 数据写入文件系统的方式 (data.struct)
     * 默认值: LegacyParquet
     */
    @ApiModelProperty(value = "IGinX数据写入文件系统的方式", example = "LegacyParquet")
    private String dataStruct;

    /**
     * 通过后缀为不同的 IGinX 数据写入文件系统的方式指定不同的参数 (data.config.<suffix>)
     * 例如: data.config.compression, data.config.encoding 等
     */
    @ApiModelProperty(value = "数据写入配置参数Map")
    private Map<String, String> dataConfig;

    /**
     * 指定 Dummy 分片从文件系统读取原有文件的方式 (dummy.struct)
     * 默认值: LegacyFilesystem
     */
    @ApiModelProperty(value = "从文件系统读取原有文件的方式", example = "LegacyFilesystem")
    private String dummyStruct;

    /**
     * 通过后缀为不同的从文件系统读取原有文件的方式指定不同的参数 (dummy.config.<suffix>)
     */
    @ApiModelProperty(value = "历史数据读取配置参数Map")
    private Map<String, String> dummyConfig;

    // ==================== 客户端连接参数 ====================

    /**
     * 跨机器访问时，socket 读写超时时间 (client.socketTimeout)
     * 单位的缺省值为毫秒
     */
    @ApiModelProperty(value = "socket读写超时时间", example = "30000")
    private Long clientSocketTimeout;

    /**
     * 跨机器访问时，socket 连接超时时间 (client.connectTimeout)
     * 单位的缺省值为毫秒
     */
    @ApiModelProperty(value = "socket连接超时时间", example = "10000")
    private Long clientConnectTimeout;

    /**
     * 跨机器访问时，socket 连接池最大容量 (client.connectPool.maxTotal)
     * 默认值: 8
     */
    @ApiModelProperty(value = "socket连接池最大容量", example = "8")
    private Integer clientConnectPoolMaxTotal;

    /**
     * 跨机器访问时，socket 连接池的淘汰时间 (client.connectPool.minEvictableIdleDuration)
     * 单位的缺省值为毫秒
     */
    @ApiModelProperty(value = "socket连接池淘汰时间", example = "1800000")
    private Long clientConnectPoolMinEvictableIdleDuration;

    @Override
    public Map<String, String> buildExtraParams() {
        Map<String, String> params = buildCommonParams();
        params.put("iginx_port", String.valueOf(iginxPort));

        // 1. 验证核心参数组合
        if (!getIsReadOnly() && (dir == null || dir.trim().isEmpty())) {
            throw new IllegalArgumentException("非只读模式(is_read_only=false)必须提供数据目录(dir)参数");
        }

        if (getHasData()) {
            if (dummyDir == null || dummyDir.trim().isEmpty()) {
                throw new IllegalArgumentException("读取原有数据(has_data=true)必须提供历史数据目录(dummy_dir)参数");
            }
        }

        // 2. 添加dir和dummy_dir参数
        if (dir != null && !dir.trim().isEmpty()) {
            params.put("dir", dir);
        }

        if (dummyDir != null && !dummyDir.trim().isEmpty()) {
            params.put("dummy_dir", dummyDir);

            // 设置embedded_prefix，如果用户未指定则使用dummy_dir的目录名
            if (embeddedPrefix != null && !embeddedPrefix.trim().isEmpty()) {
                params.put("embedded_prefix", embeddedPrefix);
            } else {
                // 从dummy_dir提取目录名作为embedded_prefix
                String dirName = extractDirNameFromPath(dummyDir);
                if (dirName != null && !dirName.trim().isEmpty()) {
                    params.put("embedded_prefix", dirName);
                }
            }
        }

        // 3. 添加数据结构参数
        if (StringUtils.hasText(dataStruct)) {
            params.put("data.struct", dataStruct);
        }
        if (StringUtils.hasText(dummyStruct)) {
            params.put("dummy.struct", dummyStruct);
        }

        // 4. 添加数据配置参数
        if (dataConfig != null && !dataConfig.isEmpty()) {
            for (Map.Entry<String, String> entry : dataConfig.entrySet()) {
                params.put("data.config." + entry.getKey(), entry.getValue());
            }
        }

        if (dummyConfig != null && !dummyConfig.isEmpty()) {
            for (Map.Entry<String, String> entry : dummyConfig.entrySet()) {
                params.put("dummy.config." + entry.getKey(), entry.getValue());
            }
        }

        // 5. 添加客户端连接参数
        if (clientSocketTimeout != null) {
            params.put("client.socketTimeout", String.valueOf(clientSocketTimeout));
        }

        if (clientConnectTimeout != null) {
            params.put("client.connectTimeout", String.valueOf(clientConnectTimeout));
        }

        if (clientConnectPoolMaxTotal != null) {
            params.put("client.connectPool.maxTotal", String.valueOf(clientConnectPoolMaxTotal));
        }
        if (clientConnectPoolMinEvictableIdleDuration != null) {
            params.put("client.connectPool.minEvictableIdleDuration", String.valueOf(clientConnectPoolMinEvictableIdleDuration));
        }
        return params;
    }

    /**
     * 从路径中提取目录名
     * 例如: /path/to/data -> data
     */
    private String extractDirNameFromPath(String path) {
        if (path == null || path.trim().isEmpty()) {
            return null;
        }

        // 规范化路径，移除末尾的斜杠
        String normalizedPath = path.trim();
        if (normalizedPath.endsWith("/") || normalizedPath.endsWith("\\")) {
            normalizedPath = normalizedPath.substring(0, normalizedPath.length() - 1);
        }

        // 找到最后一个路径分隔符
        int lastSeparator = Math.max(
                normalizedPath.lastIndexOf('/'),
                normalizedPath.lastIndexOf('\\')
        );

        if (lastSeparator >= 0 && lastSeparator < normalizedPath.length() - 1) {
            return normalizedPath.substring(lastSeparator + 1);
        }

        return normalizedPath; // 没有分隔符，直接返回整个路径
    }
}