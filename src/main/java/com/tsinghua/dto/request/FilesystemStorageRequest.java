package com.tsinghua.dto.request;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;
import javax.validation.constraints.NotNull;
import java.util.Map;

@Data
@EqualsAndHashCode(callSuper = true)
@ApiModel(description = "文件系统存储引擎注册请求")
public class FilesystemStorageRequest extends StorageEngineRegisterWrapper {

    @ApiModelProperty(value = "数据写入目录（非只读时必须提供）", example = "/path/to/your/parquet")
    private String dir;

    @ApiModelProperty(value = "原有数据目录（has_data=true时必需）", example = "/path/to/your/data")
    private String dummyDir;

    @NotNull(message = "iginx_port参数不能为空")
    @ApiModelProperty(value = "IGinX节点端口", example = "6888", required = true)
    private Integer iginxPort;

    @ApiModelProperty(value = "历史数据的数据路径前缀", example = "/path/to/your/data")
    private String embeddedPrefix;

    @Override
    public Map<String, String> buildExtraParams() {
        Map<String, String> params = buildCommonParams();
        params.put("iginx_port", String.valueOf(iginxPort));

        // 验证参数组合
        if (!getIsReadOnly() && (dir == null || dir.trim().isEmpty())) {
            throw new IllegalArgumentException("非只读模式下必须提供数据目录(dir)参数");
        }
        if (dir != null && !dir.trim().isEmpty()) {
            params.put("dir", dir);
        }

        if (getHasData()) {
            if (dummyDir == null || dummyDir.trim().isEmpty()) {
                throw new IllegalArgumentException("读取原有数据时(has_data=true)必须提供原有数据目录(dummy_dir)参数");
            }
            params.put("dummy_dir", dummyDir);
        }

        return params;
    }
}