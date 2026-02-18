package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;

/**
 * Redis 存储引擎注册请求
 * 基于文档 12.3.3 节
 */
@Data
@EqualsAndHashCode(callSuper = true)
@ApiModel(description = "Redis 存储引擎注册请求")
public class RedisStorageRequest extends BaseStorageEngineRequest {

    @ApiModelProperty(value = "Redis密码")
    private String password;

    @ApiModelProperty(value = "数据库索引", example = "0")
    private Integer database = 0;

    @ApiModelProperty(value = "连接超时时间(毫秒)", example = "2000")
    private Integer connectionTimeout = 2000;

    @ApiModelProperty(value = "Socket超时时间(毫秒)", example = "2000")
    private Integer socketTimeout = 2000;

    public String buildExtraParams() {
        StringBuilder sb = new StringBuilder();
        sb.append("has_data=").append(getHasData())
                .append(",is_read_only=").append(getIsReadOnly());

        if (password != null && !password.trim().isEmpty()) {
            sb.append(",password=").append(password);
        }
        if (database != null) {
            sb.append(",database=").append(database);
        }
        if (connectionTimeout != null) {
            sb.append(",connectionTimeout=").append(connectionTimeout);
        }
        if (socketTimeout != null) {
            sb.append(",socketTimeout=").append(socketTimeout);
        }
        if (getDataPrefix() != null && !getDataPrefix().trim().isEmpty()) {
            sb.append(",data_prefix=").append(getDataPrefix());
        }
        if (getSchemaPrefix() != null && !getSchemaPrefix().trim().isEmpty()) {
            sb.append(",schema_prefix=").append(getSchemaPrefix());
        }

        return sb.toString();
    }
}