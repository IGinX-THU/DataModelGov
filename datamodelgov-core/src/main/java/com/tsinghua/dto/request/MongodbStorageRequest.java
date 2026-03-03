package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;

import javax.validation.constraints.NotBlank;
import java.util.Map;

@Data
@EqualsAndHashCode(callSuper = true)
@ApiModel(description = "MongoDB 存储引擎注册请求")
public class MongodbStorageRequest extends BaseStorageEngineRequest {

    @ApiModelProperty(value = "Mongodb 连接字符串", example = "http://localhost:8086/")
    private String uri;

    @ApiModelProperty(value = "每次采样的文档数量", example = "1000")
    private Integer schemaSampleSize;

    @ApiModelProperty(value = "每次采样的文档", example = "0")
    private Integer dummySampleSize;

    @Override
    public Map<String, String> buildExtraParams() {
        Map<String, String> params = buildCommonParams();

        if (uri != null && !uri.trim().isEmpty()) {
            params.put("uri", uri);
        }
        if (schemaSampleSize != null) {
            params.put("schema.sample.size", String.valueOf(schemaSampleSize));
        }
        if (dummySampleSize != null) {
            params.put("dummy.sample.size", String.valueOf(dummySampleSize));
        }

        return params;
    }
}