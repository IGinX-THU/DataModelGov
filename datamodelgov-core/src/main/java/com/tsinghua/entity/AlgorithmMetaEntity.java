package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
public class AlgorithmMetaEntity {
    @ApiModelProperty(value = "算法名称")
    private String name;
    
    @ApiModelProperty(value = "版本号")
    private String version;
    
    @ApiModelProperty(value = "文件名")
    private String fileName;
    
    private Long fileSize;
    
    private Integer chunkCount;
    
    private String storagePath;
    
    private String fileMd5;
    
    @ApiModelProperty(value = "开发者")
    private String author;
    
    @ApiModelProperty(value = "场景描述")
    private String scene;
    
    @ApiModelProperty(value = "输入参数json")
    private String inputs;
    
    @ApiModelProperty(value = "输出参数json")
    private String outputs;
    
    @ApiModelProperty(value = "创建时间")
    private Long timestamp;
    
    @ApiModelProperty(value = "运行命令")
    private String cmd;

    @ApiModelProperty(value = "输入数据csv文件名")
    private String inputCsvName;

    @ApiModelProperty(value = "输出结果csv文件名")
    private String outputCsvName;

    @ApiModelProperty(value = "算法类型：python/java/shell")
    private String algorithmType;

    @ApiModelProperty(value = "依赖库列表（json）")
    private String dependencies;

    @ApiModelProperty(value = "项目名称")
    private String projectName;

    @ApiModelProperty(value = "描述信息")
    private String description;

    @ApiModelProperty(value = "数据源")
    private String tableName;

    @ApiModelProperty(value = "数据源字段全路径")
    private String inputData;

    @ApiModelProperty(value = "调用的模型（json）")
    private String calledModels;

    @ApiModelProperty(value = "输出格式")
    private String outputFormat;

    @ApiModelProperty(value = "输入参数绑定json")
    private String inputsBind;

    @ApiModelProperty(value = "输出参数绑定json")
    private String outputsBind;

    @ApiModelProperty(value = "结果回写路径前缀")
    private String outputTable;
}
