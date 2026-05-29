package com.tsinghua.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

/**
 * 自动解析源码请求DTO（通用，接收文件内容）
 */
@ApiModel("自动解析源码请求")
public class AutoParseRequest {
    
    @ApiModelProperty(value = "源文件内容", required = true)
    private String fileContent;
    
    @ApiModelProperty(value = "源文件名", required = true)
    private String fileName;
    
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

    public String getFileContent() { return fileContent; }
    public void setFileContent(String fileContent) { this.fileContent = fileContent; }
    public String getFileName() { return fileName; }
    public void setFileName(String fileName) { this.fileName = fileName; }
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
                "fileName='" + fileName + '\'' +
                ", parseType='" + parseType + '\'' +
                ", maxLines=" + maxLines +
                '}';
    }
}
