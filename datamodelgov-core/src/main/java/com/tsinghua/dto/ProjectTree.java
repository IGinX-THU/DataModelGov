package com.tsinghua.dto;

import com.alibaba.fastjson2.annotation.JSONField;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import java.util.List;

@Data
public class ProjectTree {

    @ApiModelProperty(value = "项目名称")
    private String name;

    @ApiModelProperty(value = "关联的算法列表")
    private List<String> algorithms;

    @ApiModelProperty(value = "关联的模型列表")
    private List<String> models;

    @ApiModelProperty(value = "关联的数据源列表")
    private List<String> datas;

    @ApiModelProperty(value = "关联的仿真程序列表")
    private List<String> programs;

}
