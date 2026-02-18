package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;
import javax.validation.constraints.NotBlank;

/**
 * InfluxDB 存储引擎注册请求
 * 基于文档 3.3.1 节
 */
@Data
@EqualsAndHashCode(callSuper = true)
@ApiModel(description = "InfluxDB 存储引擎注册请求")
public class InfluxdbStorageRequest extends BaseStorageEngineRequest {

    @NotBlank(message = "InfluxDB URL不能为空")
    @ApiModelProperty(value = "InfluxDB连接URL", example = "http://localhost:8086/", required = true)
    private String url = "http://localhost:8086/";

    @NotBlank(message = "InfluxDB用户名不能为空")
    @ApiModelProperty(value = "InfluxDB用户名", example = "user", required = true)
    private String username = "user";

    @NotBlank(message = "InfluxDB密码不能为空")
    @ApiModelProperty(value = "InfluxDB密码", example = "12345678", required = true)
    private String password = "12345678";

    @ApiModelProperty(value = "访问令牌")
    private String token = "testToken";

    @ApiModelProperty(value = "组织名称")
    private String organization = "testOrg";

    public String buildExtraParams() {
        StringBuilder sb = new StringBuilder();
        sb.append("has_data=").append(getHasData())
                .append(",is_read_only=").append(getIsReadOnly())
                .append(",url=").append(url)
                .append(",username=").append(username)
                .append(",password=").append(password);

        if (token != null && !token.trim().isEmpty()) {
            sb.append(",token=").append(token);
        }
        if (organization != null && !organization.trim().isEmpty()) {
            sb.append(",organization=").append(organization);
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