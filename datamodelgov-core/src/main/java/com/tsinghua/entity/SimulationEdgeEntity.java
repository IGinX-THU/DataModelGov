package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

/**
 * 仿真边实体
 * 表示仿真图中的边（数据流向关系）
 */
@Data
public class SimulationEdgeEntity {
    @ApiModelProperty(value = "边ID")
    private String edgeId;

    @ApiModelProperty(value = "源节点ID")
    private String sourceNodeId;

    @ApiModelProperty(value = "目标节点ID")
    private String targetNodeId;

    @ApiModelProperty(value = "数据映射配置（JSON格式）")
    private String dataMapping;

    @ApiModelProperty(value = "所属仿真档案ID")
    private Long archiveId;
}
