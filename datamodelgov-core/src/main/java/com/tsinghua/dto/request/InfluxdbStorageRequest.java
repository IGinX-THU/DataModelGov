package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;
import org.springframework.util.StringUtils;

import javax.validation.constraints.NotBlank;
import java.util.Map;

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
    private String url;

    @NotBlank(message = "InfluxDB用户名不能为空")
    @ApiModelProperty(value = "InfluxDB用户名", example = "user", required = true)
    private String username;

    @NotBlank(message = "InfluxDB密码不能为空")
    @ApiModelProperty(value = "InfluxDB密码", example = "12345678", required = true)
    private String password;

    @ApiModelProperty(value = "访问令牌")
    private String token;

    @ApiModelProperty(value = "组织名称")
    private String organization;

    @Override
    public Map<String, String> buildExtraParams() {
        Map<String, String> params = buildCommonParams();
        if (StringUtils.hasText(url)) {
            params.put("url", url);
        }
        if (StringUtils.hasText(username)) {
            params.put("username", username);
        }
        if (StringUtils.hasText(password)) {
            params.put("password", password);
        }
        if (token != null && !token.trim().isEmpty()) {
            params.put("token", token);
        }
        if (organization != null && !organization.trim().isEmpty()) {
            params.put("organization", organization);
        }
        return params;
    }
}