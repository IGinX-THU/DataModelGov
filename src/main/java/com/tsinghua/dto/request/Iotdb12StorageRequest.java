package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;
import org.springframework.util.StringUtils;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.Min;
import java.util.Map;

@Data
@EqualsAndHashCode(callSuper = true)
@ApiModel(description = "IoTDB 12.x 存储引擎注册请求")
public class Iotdb12StorageRequest extends StorageEngineRegisterWrapper {

    @ApiModelProperty(value = "IoTDB用户名", example = "root")
    private String username;

    @ApiModelProperty(value = "IoTDB密码", example = "root")
    private String password;

    @Min(value = 1, message = "会话池大小必须大于0")
    @ApiModelProperty(value = "会话池大小", example = "130")
    private Integer sessionPoolSize;

    @Override
    public Map<String, String> buildExtraParams() {
        Map<String, String> params = buildCommonParams();
        if (StringUtils.hasText(username)) {
            params.put("username", username);
        }
        if (StringUtils.hasText(password)) {
            params.put("password", password);
        }
        if (sessionPoolSize != null) {
            params.put("sessionPoolSize", String.valueOf(sessionPoolSize));
        }
        return params;
    }
}