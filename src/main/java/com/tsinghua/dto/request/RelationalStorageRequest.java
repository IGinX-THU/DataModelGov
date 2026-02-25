package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;
import org.springframework.util.StringUtils;

import javax.validation.constraints.NotBlank;
import java.util.Map;

@Data
@EqualsAndHashCode(callSuper = true)
@ApiModel(description = "关系型数据库存储引擎注册请求")
public class RelationalStorageRequest extends StorageEngineRegisterWrapper {

    @NotBlank(message = "数据库引擎不能为空")
    @ApiModelProperty(value = "数据库引擎(mysql/postgresql)", example = "postgresql", required = true)
    private String engine;

    @ApiModelProperty(value = "数据库用户名", example = "postgres", required = true)
    private String username;

    @ApiModelProperty(value = "数据库密码", example = "postgres")
    private String password;

    @ApiModelProperty(value = "元数据配置文件路径（仅mysql需要）", example = "resources/mysql-meta-template.properties")
    private String metaPropertiesPath;

    // ==================== HikariDataSource 连接池参数 ====================

    @ApiModelProperty(value = "连接超时时间（单位：毫秒）", example = "30000")
    private Long connectionTimeout;

    @ApiModelProperty(value = "空闲连接超时时间（单位：毫秒）", example = "10000")
    private Long idleTimeout;

    @ApiModelProperty(value = "连接池中的最大连接数", example = "20")
    private Integer maximumPoolSize;

    @ApiModelProperty(value = "连接池中的最小空闲连接数", example = "1")
    private Integer minimumIdle;

    @ApiModelProperty(value = "检测连接泄漏的阈值（单位：毫秒）", example = "2500")
    private Long leakDetectionThreshold;

    @ApiModelProperty(value = "SQL 预编译对象缓存个数", example = "250")
    private Integer prepStmtCacheSize;

    @ApiModelProperty(value = "SQL 预编译对象缓存个数上限", example = "2048")
    private Integer prepStmtCacheSqlLimit;

    @Override
    public Map<String, String> buildExtraParams() {
        Map<String, String> params = buildCommonParams();
        params.put("engine", engine);
        if (StringUtils.hasText(username)) {
            params.put("username", username);
        }
        if (password != null && !password.trim().isEmpty()) {
            params.put("password", password);
        }

        if (metaPropertiesPath != null && !metaPropertiesPath.trim().isEmpty()) {
            params.put("meta_properties_path", metaPropertiesPath);
        }

        if (connectionTimeout != null) {
            params.put("connection_timeout", String.valueOf(connectionTimeout));
        }
        if (idleTimeout != null) {
            params.put("idle_timeout", String.valueOf(idleTimeout));
        }
        if (maximumPoolSize != null) {
            params.put("maximum_pool_size", String.valueOf(maximumPoolSize));
        }
        if (minimumIdle != null) {
            params.put("minimum_idle", String.valueOf(minimumIdle));
        }
        if (leakDetectionThreshold != null) {
            params.put("leak_detection_threshold", String.valueOf(leakDetectionThreshold));
        }
        if (prepStmtCacheSize != null) {
            params.put("prep_stmt_cache_size", String.valueOf(prepStmtCacheSize));
        }
        if (prepStmtCacheSqlLimit != null) {
            params.put(" prep_stmt_cache_sql_limit", String.valueOf(prepStmtCacheSqlLimit));
        }

        return params;
    }
}