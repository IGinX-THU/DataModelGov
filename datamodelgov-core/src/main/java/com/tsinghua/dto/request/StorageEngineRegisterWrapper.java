package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;
import javax.validation.constraints.*;
import java.util.Map;

/**
 * 存储引擎注册请求包装器
 * 手动处理多态反序列化
 */
@Data
@EqualsAndHashCode(callSuper = true)
@ApiModel(description = "存储引擎注册请求包装器")
public class StorageEngineRegisterWrapper extends BaseStorageEngineRequest {

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

    /**
     * 构建额外参数字典
     * 这个方法会被调用，但实际上会根据具体的子类实现执行
     */
    @Override
    public Map<String, String> buildExtraParams() {
        // 这个方法不应该被直接调用
        // 实际的反序列化会根据storageEngineType创建具体的子类实例
        throw new IllegalStateException("这个方法不应该被直接调用。请确保使用具体的子类实例。");
    }
}
