package com.tsinghua.dto;

import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;
import javax.validation.constraints.Min;
import javax.validation.constraints.Max;
import java.util.Map;

/**
 * 数据源注册请求DTO
 * 用于接收前端参数，然后转换为IGinX Storage对象
 */
@Data
public class DataSourceRequest {

    @NotBlank(message = "数据源名称不能为空")
    private String alias;

    @NotBlank(message = "主机地址不能为空")
    private String ip;

    @NotNull(message = "端口号不能为空")
    @Min(value = 1, message = "端口号必须大于0")
    @Max(value = 65535, message = "端口号不能超过65535")
    private Integer port;

    /**
     *     unknown(0),
     *     iotdb12(1),
     *     influxdb(2),
     *     filesystem(3),
     *     relational(4),
     *     mongodb(5),
     *     redis(6);
     */
    @NotNull(message = "存储引擎类型不能为空")
    private Integer storageEngineType;
    private String engine;
    private String description;
    private String username;
    private String password;
    private String database;
    
    // 扩展参数，用于接收特定数据源类型的额外参数
    private Map<String, String> extraParams;

    /**
     * 构建完整的额外参数Map
     */
    public Map<String, String> buildExtraParams() {
        if (extraParams == null) {
            extraParams = new java.util.HashMap<>();
        }
        
        // 添加基本参数
//        if (alias != null) extraParams.put("alias", alias);
//        if (description != null) extraParams.put("description", description);
        if (username != null) extraParams.put("username", username);
        if (password != null) extraParams.put("password", password);
        if (engine != null) extraParams.put("engine", engine);
        
        return extraParams;
    }
}
