package com.tsinghua.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

/**
 * 自动解析源码请求DTO
 */
@ApiModel("自动解析源码请求")
public class AutoParseRequest {
    
    @ApiModelProperty(value = "模型名称", required = true)
    private String name;
    
    @ApiModelProperty(value = "模型版本", required = true)
    private String version;
    
    @ApiModelProperty(value = "源文件路径（相对于解压目录）", required = true)
    private String filePath;
    
    @ApiModelProperty(value = "解析类型：regex / typehint / inspect")
    private String parseType;
    
    @ApiModelProperty(value = "正则表达式（regex模式使用）")
    private String regexPattern;
    
    @ApiModelProperty(value = "Python模块名（inspect模式使用）")
    private String pythonModule;
    
    @ApiModelProperty(value = "Python函数名（inspect模式使用）")
    private String pythonFunction;
    
    @ApiModelProperty(value = "最大扫描行数，默认50")
    private Integer maxLines;

    public AutoParseRequest() {}

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getVersion() { return version; }
    public void setVersion(String version) { this.version = version; }
    public String getFilePath() { return filePath; }
    public void setFilePath(String filePath) { this.filePath = filePath; }
    public String getParseType() { return parseType; }
    public void setParseType(String parseType) { this.parseType = parseType; }
    public String getRegexPattern() { return regexPattern; }
    public void setRegexPattern(String regexPattern) { this.regexPattern = regexPattern; }
    public String getPythonModule() { return pythonModule; }
    public void setPythonModule(String pythonModule) { this.pythonModule = pythonModule; }
    public String getPythonFunction() { return pythonFunction; }
    public void setPythonFunction(String pythonFunction) { this.pythonFunction = pythonFunction; }
    public Integer getMaxLines() { return maxLines; }
    public void setMaxLines(Integer maxLines) { this.maxLines = maxLines; }

    @Override
    public String toString() {
        return "AutoParseRequest{" +
                "name='" + name + '\'' +
                ", version='" + version + '\'' +
                ", filePath='" + filePath + '\'' +
                ", parseType='" + parseType + '\'' +
                ", maxLines=" + maxLines +
                '}';
    }
}
