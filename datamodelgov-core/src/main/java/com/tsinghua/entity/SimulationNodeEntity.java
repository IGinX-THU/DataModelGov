package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

/**
 * 仿真节点实体
 * 表示仿真图中的算法任务节点
 * 每个节点对应一个具体的算法执行任务
 */
@Data
public class SimulationNodeEntity {
    @ApiModelProperty(value = "节点ID")
    private String nodeId;

    @ApiModelProperty(value = "节点显示名称")
    private String nodeName;

    @ApiModelProperty(value = "引用的算法名称")
    private String algorithmName;

    @ApiModelProperty(value = "引用的算法版本")
    private String algorithmVersion;

    @ApiModelProperty(value = "数据时间窗口开始时间（毫秒时间戳）")
    private Long startTime;

    @ApiModelProperty(value = "数据时间窗口结束时间（毫秒时间戳）")
    private Long endTime;

    @ApiModelProperty(value = "节点执行参数（JSON格式）")
    private String executionParams;

    @ApiModelProperty(value = "是否启用该节点")
    private Boolean enabled;

    @ApiModelProperty(value = "节点位置X坐标")
    private Integer positionX;

    @ApiModelProperty(value = "节点位置Y坐标")
    private Integer positionY;

    @ApiModelProperty(value = "节点执行状态：pending/running/completed/failed")
    private String executionStatus;

    @ApiModelProperty(value = "节点执行结果（输出txt文本数据）")
    private String executionOutput;

    @ApiModelProperty(value = "节点执行错误信息")
    private String executionError;
}
