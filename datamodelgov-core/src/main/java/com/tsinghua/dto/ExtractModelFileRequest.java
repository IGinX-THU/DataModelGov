package com.tsinghua.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

/**
 * 提取模型文件请求DTO
 */
@ApiModel("提取模型文件请求")
public class ExtractModelFileRequest {
    
    @ApiModelProperty(value = "模型名称", required = true)
    private String name;
    
    @ApiModelProperty(value = "模型版本", required = true)
    private String version;
    
    public ExtractModelFileRequest() {}
    
    public ExtractModelFileRequest(String name, String version) {
        this.name = name;
        this.version = version;
    }
    
    public String getName() {
        return name;
    }
    
    public void setName(String name) {
        this.name = name;
    }
    
    public String getVersion() {
        return version;
    }
    
    public void setVersion(String version) {
        this.version = version;
    }
    
    @Override
    public String toString() {
        return "ExtractModelFileRequest{" +
                "name='" + name + '\'' +
                ", version='" + version + '\'' +
                '}';
    }
}
