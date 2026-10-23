package com.tsinghua.entity;

import cn.edu.tsinghua.iginx.session_v2.annotations.Field;
import cn.edu.tsinghua.iginx.session_v2.annotations.Measurement;
import io.swagger.annotations.ApiModelProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** UQ评估记录清单(IginX 分页;文件 uq/*.json 为唯一事实源)。 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.engine_uq_records")
public class EngineUqRecordEntity {

    @ApiModelProperty(value = "行时间戳(=评估发起时间)")
    @Field(timestamp = true)
    private Long id;

    @ApiModelProperty(value = "所属项目ID")
    @Field(name = "projectId")
    private String projectId;

    @ApiModelProperty(value = "UQ记录ID")
    @Field(name = "uqId")
    private String uqId;

    @ApiModelProperty(value = "来源任务ID")
    @Field(name = "taskId")
    private String taskId;

    @ApiModelProperty(value = "关联模型ID")
    @Field(name = "modelAssetId")
    private String modelAssetId;

    @ApiModelProperty(value = "模型名称")
    @Field(name = "modelName")
    private String modelName;

    @ApiModelProperty(value = "评估方法 B | C | D")
    @Field(name = "method")
    private String method;

    @ApiModelProperty(value = "程序运行标识")
    @Field(name = "runId")
    private String runId;

    @ApiModelProperty(value = "EXECUTING | COMPLETED | FAILED")
    @Field(name = "status")
    private String status;

    @ApiModelProperty(value = "结果说明")
    @Field(name = "message")
    private String message;

    @ApiModelProperty(value = "开始时间(毫秒)")
    @Field(name = "startTime")
    private Long startTime;

    @ApiModelProperty(value = "结束时间(毫秒)")
    @Field(name = "endTime")
    private Long endTime;

    @ApiModelProperty(value = "发起人")
    @Field(name = "owner")
    private String owner;

    @ApiModelProperty(value = "发起时间(毫秒;行时间戳)")
    @Field(name = "createTime")
    private Long createTime;
}
