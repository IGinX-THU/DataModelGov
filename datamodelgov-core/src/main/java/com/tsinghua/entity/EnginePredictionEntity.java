package com.tsinghua.entity;

import cn.edu.tsinghua.iginx.session_v2.annotations.Field;
import cn.edu.tsinghua.iginx.session_v2.annotations.Measurement;
import io.swagger.annotations.ApiModelProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** 输出预测记录清单(IginX 分页;文件 predictions/*.json 为唯一事实源)。 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.engine_predictions")
public class EnginePredictionEntity {

    @ApiModelProperty(value = "行时间戳(=预测发起时间)")
    @Field(timestamp = true)
    private Long id;

    @ApiModelProperty(value = "所属项目ID")
    @Field(name = "projectId")
    private String projectId;

    @ApiModelProperty(value = "预测记录ID")
    @Field(name = "recId")
    private String recId;

    @ApiModelProperty(value = "关联模型ID")
    @Field(name = "modelAssetId")
    private String modelAssetId;

    @ApiModelProperty(value = "模型名称")
    @Field(name = "modelName")
    private String modelName;

    @ApiModelProperty(value = "程序运行标识")
    @Field(name = "runId")
    private String runId;

    @ApiModelProperty(value = "EXECUTING | COMPLETED | FAILED")
    @Field(name = "status")
    private String status;

    @ApiModelProperty(value = "结果说明")
    @Field(name = "message")
    private String message;

    @ApiModelProperty(value = "工况数")
    @Field(name = "conditionCount")
    private Integer conditionCount;

    @ApiModelProperty(value = "显式选择的UQ记录ID(空=确定性预测)")
    @Field(name = "uqRecordId")
    private String uqRecordId;

    @ApiModelProperty(value = "发起人")
    @Field(name = "owner")
    private String owner;

    @ApiModelProperty(value = "发起时间(毫秒;行时间戳)")
    @Field(name = "createTime")
    private Long createTime;

    @ApiModelProperty(value = "完成时间(毫秒)")
    @Field(name = "finishedTime")
    private Long finishedTime;
}
