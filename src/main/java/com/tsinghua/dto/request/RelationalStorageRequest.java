package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;
import javax.validation.constraints.NotBlank;
import java.util.Map;

@Data
@EqualsAndHashCode(callSuper = true)
@ApiModel(description = "关系型数据库存储引擎注册请求")
public class RelationalStorageRequest extends StorageEngineRegisterWrapper {

    @NotBlank(message = "数据库引擎不能为空")
    @ApiModelProperty(value = "数据库引擎(mysql/postgresql)", example = "postgresql", required = true)
    private String engine = "postgresql";

    @NotBlank(message = "用户名不能为空")
    @ApiModelProperty(value = "数据库用户名", example = "postgres", required = true)
    private String username = "postgres";

    @ApiModelProperty(value = "数据库密码", example = "postgres")
    private String password = "postgres";

    @ApiModelProperty(value = "元数据配置文件路径（仅mysql需要）", example = "resources/mysql-meta-template.properties")
    private String metaPropertiesPath = "resources/mysql-meta-template.properties";

    @Override
    public Map<String, String> buildExtraParams() {
        Map<String, String> params = buildCommonParams();
        params.put("engine", engine);
        params.put("username", username);

        if (password != null && !password.trim().isEmpty()) {
            params.put("password", password);
        }

        if ("mysql".equalsIgnoreCase(engine)) {
            if (metaPropertiesPath == null || metaPropertiesPath.trim().isEmpty()) {
                throw new IllegalArgumentException("MySQL存储引擎必须提供meta_properties_path参数");
            }
            params.put("meta_properties_path", metaPropertiesPath);
        }

        return params;
    }
}