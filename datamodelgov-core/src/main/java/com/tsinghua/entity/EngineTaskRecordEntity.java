package com.tsinghua.entity;

import cn.edu.tsinghua.iginx.session_v2.annotations.Field;
import cn.edu.tsinghua.iginx.session_v2.annotations.Measurement;
import io.swagger.annotations.ApiModelProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/**
 * 建模任务运行记录(运行记录页的数据源)。
 * 与 engine_projects 同模式:入 IginX relational_system,列表分页/计数走 SQL,
 * 行时间戳主键 = 任务创建时间(id 与 createTime 相等),状态变更按同时间戳覆写(upsert)。
 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.engine_task_records")
public class EngineTaskRecordEntity {

    @ApiModelProperty(value = "行时间戳(=任务创建时间)")
    @Field(timestamp = true)
    private Long id;

    @ApiModelProperty(value = "所属项目ID")
    @Field(name = "projectId")
    private String projectId;

    @ApiModelProperty(value = "任务ID")
    @Field(name = "taskId")
    private String taskId;

    @ApiModelProperty(value = "任务类型:steady|steady_update|transient|flight_steady|flight_transient|evolution")
    @Field(name = "kind")
    private String kind;

    @ApiModelProperty(value = "任务名称")
    @Field(name = "name")
    private String name;

    @ApiModelProperty(value = "最近一次运行标识")
    @Field(name = "runId")
    private String runId;

    @ApiModelProperty(value = "任务状态:READY/PREPARING/RUNNING/COMPLETED/FAILED/STOP_REQUESTED/STOPPED")
    @Field(name = "status")
    private String status;

    @ApiModelProperty(value = "失败分类:SAVE_FAILED|NUMERIC_FAILED;空=未失败")
    @Field(name = "errorKind")
    private String errorKind;

    @ApiModelProperty(value = "最近一次结果说明")
    @Field(name = "message")
    private String message;

    @ApiModelProperty(value = "创建人")
    @Field(name = "owner")
    private String owner;

    @ApiModelProperty(value = "开始时间(毫秒)")
    @Field(name = "startTime")
    private Long startTime;

    @ApiModelProperty(value = "结束时间(毫秒)")
    @Field(name = "endTime")
    private Long endTime;

    @ApiModelProperty(value = "任务创建时间(毫秒)")
    @Field(name = "createTime")
    private Long createTime;
}
