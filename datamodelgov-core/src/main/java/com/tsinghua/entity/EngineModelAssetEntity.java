package com.tsinghua.entity;

import cn.edu.tsinghua.iginx.session_v2.annotations.Field;
import cn.edu.tsinghua.iginx.session_v2.annotations.Measurement;
import io.swagger.annotations.ApiModelProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/** 模型成果清单(IginX 分页;文件 models/*.json 为唯一事实源,本表仅承载列表查询)。 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.engine_model_assets")
public class EngineModelAssetEntity {

    @ApiModelProperty(value = "行时间戳(=模型登记时间)")
    @Field(timestamp = true)
    private Long id;

    @ApiModelProperty(value = "所属项目ID")
    @Field(name = "projectId")
    private String projectId;

    @ApiModelProperty(value = "模型ID")
    @Field(name = "modelId")
    private String modelId;

    @ApiModelProperty(value = "来源任务ID")
    @Field(name = "taskId")
    private String taskId;

    @ApiModelProperty(value = "模型名称")
    @Field(name = "name")
    private String name;

    @ApiModelProperty(value = "来源业务")
    @Field(name = "sourceBusiness")
    private String sourceBusiness;

    @ApiModelProperty(value = "来源阶段:2.4 基础建模 | 2.7 数据更新")
    @Field(name = "stage")
    private String stage;

    @ApiModelProperty(value = "计算路径:稳态方程 | 瞬态时刻方程")
    @Field(name = "route")
    private String route;

    @ApiModelProperty(value = "结果状态:已交付 | 诊断(未收敛但有效) | 已导入")
    @Field(name = "resultStatus")
    private String resultStatus;

    @ApiModelProperty(value = "发动机编号")
    @Field(name = "engineId")
    private String engineId;

    @ApiModelProperty(value = "父模型ID(空=基准配置)")
    @Field(name = "parentModelId")
    private String parentModelId;

    @ApiModelProperty(value = "关联UQ记录数")
    @Field(name = "uqCount")
    private Integer uqCount;

    @ApiModelProperty(value = "交付Excel绝对路径")
    @Field(name = "deliveryFile")
    private String deliveryFile;

    @ApiModelProperty(value = "登记人")
    @Field(name = "owner")
    private String owner;

    @ApiModelProperty(value = "登记时间(毫秒;行时间戳)")
    @Field(name = "createTime")
    private Long createTime;
}
