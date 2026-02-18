package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;
import java.util.Map;

@Data
@EqualsAndHashCode(callSuper = true)
@ApiModel(description = "MongoDB 存储引擎注册请求")
public class MongodbStorageRequest extends BaseStorageEngineRequest {

    @ApiModelProperty(value = "MongoDB用户名")
    private String username;

    @ApiModelProperty(value = "MongoDB密码")
    private String password;

    @ApiModelProperty(value = "认证数据库", example = "admin")
    private String authDatabase = "admin";

    @ApiModelProperty(value = "目标数据库名称")
    private String database;

    @Override
    public Map<String, String> buildExtraParams() {
        Map<String, String> params = buildCommonParams();

        if (username != null && !username.trim().isEmpty()) {
            params.put("username", username);
        }
        if (password != null && !password.trim().isEmpty()) {
            params.put("password", password);
        }
        if (authDatabase != null && !authDatabase.trim().isEmpty()) {
            params.put("authDatabase", authDatabase);
        }
        if (database != null && !database.trim().isEmpty()) {
            params.put("database", database);
        }

        return params;
    }
}