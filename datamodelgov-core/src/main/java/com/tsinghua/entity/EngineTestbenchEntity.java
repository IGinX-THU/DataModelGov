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
 * 数字试车台记录清单(IginX 分页;文件 testbench/*.json 为唯一事实源)。
 * kind 覆盖:design_point | startstop | fullmode(与 TestbenchService.listMeta 的 kind 过滤一致)。
 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.engine_testbench_records")
public class EngineTestbenchEntity {

    @ApiModelProperty(value = "行时间戳(=记录创建时间)")
    @Field(timestamp = true)
    private Long id;

    @ApiModelProperty(value = "所属项目ID")
    @Field(name = "projectId")
    private String projectId;

    @ApiModelProperty(value = "记录键(taskId或runId)")
    @Field(name = "taskKey")
    private String taskKey;

    @ApiModelProperty(value = "记录类型:design_point | startstop | fullmode")
    @Field(name = "kind")
    private String kind;

    @ApiModelProperty(value = "阶段:PENDING|RUNNING|ENDED|FAILED|COMMITTED")
    @Field(name = "phase")
    private String phase;

    @ApiModelProperty(value = "阶段说明")
    @Field(name = "message")
    private String message;

    @ApiModelProperty(value = "是否有交付Excel(1/0)")
    @Field(name = "hasExcel")
    private Integer hasExcel;

    @ApiModelProperty(value = "展示用配置摘要(JSON:modelMode/initialKind/duration等)")
    @Field(name = "summary")
    private String summary;

    @ApiModelProperty(value = "发起人")
    @Field(name = "owner")
    private String owner;

    @ApiModelProperty(value = "创建时间(毫秒;行时间戳)")
    @Field(name = "createTime")
    private Long createTime;

    @ApiModelProperty(value = "结束时间(毫秒)")
    @Field(name = "finishedTime")
    private Long finishedTime;
}
