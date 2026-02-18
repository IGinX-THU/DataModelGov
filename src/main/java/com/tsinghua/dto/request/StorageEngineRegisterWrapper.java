package com.tsinghua.dto.request;

import com.fasterxml.jackson.annotation.JsonSubTypes;
import com.fasterxml.jackson.annotation.JsonTypeInfo;
import io.swagger.annotations.ApiModel;
import lombok.Data;
import java.util.Map;

/**
 * 存储引擎注册请求包装器
 * 使用Jackson多态反序列化
 * 这个类实现了buildExtraParams()，但会委托给具体的子类实现
 */
@Data
@ApiModel(description = "存储引擎注册请求包装器")
@JsonTypeInfo(
        use = JsonTypeInfo.Id.NAME,
        include = JsonTypeInfo.As.PROPERTY,
        property = "storageEngineType"
)
@JsonSubTypes({
        @JsonSubTypes.Type(value = Iotdb12StorageRequest.class, name = "1"),
        @JsonSubTypes.Type(value = InfluxdbStorageRequest.class, name = "2"),
        @JsonSubTypes.Type(value = FilesystemStorageRequest.class, name = "3"),
        @JsonSubTypes.Type(value = RelationalStorageRequest.class, name = "4"),
        @JsonSubTypes.Type(value = MongodbStorageRequest.class, name = "5"),
        @JsonSubTypes.Type(value = RedisStorageRequest.class, name = "6")
})
public class StorageEngineRegisterWrapper extends BaseStorageEngineRequest {

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