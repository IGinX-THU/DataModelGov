package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

/**
 * 仿真档案实体
 * 用于描述算法、模型和数据之间的关系
 */
@Data
public class SimulationArchiveEntity {
    @ApiModelProperty(value = "仿真档案名称")
    private String name;

    @ApiModelProperty(value = "仿真档案描述")
    private String description;

    @ApiModelProperty(value = "有向图JSON结构（包含节点和边）")
    private String graphJson;

    @ApiModelProperty(value = "状态：active-启用，inactive-禁用")
    private Boolean status;

    @ApiModelProperty(value = "创建时间")
    private Long createTime;

    @ApiModelProperty(value = "更新时间")
    private Long updateTime;

    @ApiModelProperty(value = "创建人")
    private String owner;

    @ApiModelProperty(value = "调度表达式（cron表达式，用于定期运行）")
    private String scheduleCron;

    @ApiModelProperty(value = "输出API配置（JSON格式，包含URL、headers等）")
    private String outputApiConfig;

    @ApiModelProperty(value = "最后执行时间")
    private Long lastExecutionTime;

    @ApiModelProperty(value = "执行次数")
    private Long executionCount;

    @ApiModelProperty(value = "是否正在运行")
    private Boolean isRunning;
}
