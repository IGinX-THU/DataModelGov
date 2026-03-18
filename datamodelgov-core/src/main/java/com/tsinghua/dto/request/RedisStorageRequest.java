package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;
import org.springframework.util.StringUtils;

import javax.validation.constraints.NotBlank;
import java.util.Map;

/**
 * Redis 存储引擎注册请求
 * 基于文档 12.3.3 节
 */
@Data
@EqualsAndHashCode(callSuper = true)
@ApiModel(description = "Redis 存储引擎注册请求")
public class RedisStorageRequest extends BaseStorageEngineRequest {

    @ApiModelProperty(value = "用户名", example = "user")
    private String username;

    @ApiModelProperty(value = "Redis密码")
    private String password;

    @ApiModelProperty(value = "Redis客户端请求超时时间(毫秒)", example = "5000")
    private Integer timeout = 2000;

    @Override
    public Map<String, String> buildExtraParams() {
        Map<String, String> params = buildCommonParams();
        if (StringUtils.hasText(username)) {
            params.put("username", username);
        }
        if (StringUtils.hasText(password)) {
            params.put("password", password);
        }
        if (timeout != null) {
            params.put("timeout", String.valueOf(timeout));
        }
        return params;
    }
}