package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

/**
 * 仿真节点实体
 * 表示仿真图中的节点（算法、模型、数据）
 */
@Data
public class SimulationNodeEntity {
    @ApiModelProperty(value = "节点ID")
    private String nodeId;

    @ApiModelProperty(value = "节点名称")
    private String nodeName;

    @ApiModelProperty(value = "节点类型：algorithm-算法，model-模型，data-数据")
    private String nodeType;

    @ApiModelProperty(value = "关联的资源名称（算法名称、模型名称、数据表名等）")
    private String resourceName;

    @ApiModelProperty(value = "关联的资源版本（模型版本等）")
    private String resourceVersion;

    @ApiModelProperty(value = "节点配置（JSON格式）")
    private String nodeConfig;

    @ApiModelProperty(value = "节点位置X坐标")
    private Integer positionX;

    @ApiModelProperty(value = "节点位置Y坐标")
    private Integer positionY;

    @ApiModelProperty(value = "所属仿真档案ID")
    private Long archiveId;

    @ApiModelProperty(value = "算法名称（当nodeType为algorithm时使用）")
    private String algorithmName;

    @ApiModelProperty(value = "算法版本（当nodeType为algorithm时使用）")
    private String algorithmVersion;

    @ApiModelProperty(value = "输入数据源（当nodeType为algorithm时使用）")
    private String inputDataSource;

    @ApiModelProperty(value = "输入数据表（当nodeType为algorithm时使用）")
    private String inputDataTable;
}
