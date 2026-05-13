package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import javax.validation.constraints.*;
import java.util.HashMap;
import java.util.Map;

/**
 * 存储引擎注册请求基类
 */
@Data
@ApiModel(description = "存储引擎注册请求基类")
public abstract class BaseStorageEngineRequest {

    @NotBlank(message = "主机地址不能为空")
    @ApiModelProperty(value = "存储引擎服务器IP地址", example = "127.0.0.1", required = true)
    private String ip;

    @NotNull(message = "端口号不能为空")
    @Min(value = 1, message = "端口号必须大于0")
    @Max(value = 65535, message = "端口号不能超过65535")
    @ApiModelProperty(value = "存储引擎服务器端口", example = "6667", required = true)
    private Integer port;

    /**
     * 存储引擎类型 (数字代码)
     * 0: unknown, 1: iotdb12, 2: influxdb, 3: filesystem, 4: relational, 5: mongodb, 6: redis
     */
    @NotNull(message = "存储引擎类型不能为空")
    @Min(value = 1, message = "存储引擎类型代码无效")
    @Max(value = 6, message = "存储引擎类型代码无效")
    @ApiModelProperty(
            value = "存储引擎类型代码: 1-iotdb12, 2-influxdb, 3-filesystem, 4-relational, 5-mongodb, 6-redis",
            example = "1",
            required = true
    )
    private Integer storageEngineType;

    @ApiModelProperty(value = "是否读取原有数据", example = "false", required = true)
    private Boolean hasData = true;

    @ApiModelProperty(value = "是否只读", example = "false", required = true)
    private Boolean isReadOnly = true;

    @ApiModelProperty(value = "数据前缀")
    private String dataPrefix;

    @NotBlank(message = "请为数据源起个模式前缀")
    @ApiModelProperty(value = "模式前缀")
    private String schemaPrefix;

    /**
     * 构建额外参数字典
     */
    public abstract Map<String, String> buildExtraParams();

    /**
     * 构建通用参数字典
     */
    protected Map<String, String> buildCommonParams() {
        Map<String, String> params = new HashMap<>();
        params.put("has_data", String.valueOf(hasData));
        params.put("is_read_only", String.valueOf(isReadOnly));

        if (dataPrefix != null && !dataPrefix.trim().isEmpty()) {
            params.put("data_prefix", dataPrefix);
        }
        if (schemaPrefix != null && !schemaPrefix.trim().isEmpty()) {
            params.put("schema_prefix", schemaPrefix);
        }

        return params;
    }
}