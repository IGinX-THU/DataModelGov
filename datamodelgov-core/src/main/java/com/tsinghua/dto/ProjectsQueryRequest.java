package com.tsinghua.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
@ApiModel("項目查询请求")
public class ProjectsQueryRequest {

    @ApiModelProperty(value = "页码", example = "1")
    private Integer pageNum;

    @ApiModelProperty(value = "每页大小", example = "6")
    private Integer pageSize;

    @ApiModelProperty(value = "名称（模糊查询）", example = "名称")
    private String name;

    @ApiModelProperty(value = "算法")
    private String algorithm;

    @ApiModelProperty(value = "模型")
    private String model;

    @ApiModelProperty(value = "数据")
    private String data;

}
