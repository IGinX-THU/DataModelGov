package com.tsinghua.entity;

import cn.edu.tsinghua.iginx.session_v2.annotations.Field;
import cn.edu.tsinghua.iginx.session_v2.annotations.Measurement;
import io.swagger.annotations.ApiModelProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** 多系统联合仿真会话清单(IginX 分页;文件 afo/<runId>.json 为唯一事实源)。 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.engine_afo_sessions")
public class EngineAfoSessionEntity {

    @ApiModelProperty(value = "行时间戳(=会话创建时间)")
    @Field(timestamp = true)
    private Long id;

    @ApiModelProperty(value = "所属项目ID")
    @Field(name = "projectId")
    private String projectId;

    @ApiModelProperty(value = "运行编号(会话身份)")
    @Field(name = "runId")
    private String runId;

    @ApiModelProperty(value = "发动机编号")
    @Field(name = "engineId")
    private String engineId;

    @ApiModelProperty(value = "会话阶段:READY|RUNNING|PAUSED|ENDED|FAILED")
    @Field(name = "phase")
    private String phase;

    @ApiModelProperty(value = "阶段说明")
    @Field(name = "message")
    private String message;

    @ApiModelProperty(value = "是否已生成结果(1/0)")
    @Field(name = "hasResult")
    private Integer hasResult;

    @ApiModelProperty(value = "是否有交付Excel(1/0)")
    @Field(name = "hasExcel")
    private Integer hasExcel;

    @ApiModelProperty(value = "展示用配置摘要(JSON:loadMode/externalAir/pace/duration等)")
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
