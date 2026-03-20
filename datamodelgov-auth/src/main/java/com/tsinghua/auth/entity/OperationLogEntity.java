package com.tsinghua.auth.entity;

import lombok.Data;
import lombok.Builder;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 操作日志实体
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OperationLogEntity {
    
    /**
     * 日志ID
     */
    private Long id;
    
    /**
     * 操作人
     */
    private String operator;
    
    /**
     * 操作人IP地址
     */
    private String clientIp;
    
    /**
     * 操作描述
     */
    private String description;
    
    /**
     * 操作类型
     */
    private String operationType;
    
    /**
     * 请求方法
     */
    private String method;
    
    /**
     * 请求参数
     */
    private String params;
    
    /**
     * 返回结果
     */
    private String result;
    
    /**
     * 执行状态（成功/失败）
     */
    private String status;
    
    /**
     * 执行耗时（毫秒）
     */
    private Long executionTime;
    
    /**
     * 错误信息（如果有）
     */
    private String errorMessage;
    
    /**
     * 操作时间
     */
    private LocalDateTime operationTime;
    
    /**
     * 用户代理
     */
    private String userAgent;
    
    /**
     * 请求URI
     */
    private String requestUri;
    
    @Override
    public String toString() {
        return String.format(
            "=== 操作日志 ===\n" +
            "操作人: %s\n" +
            "IP地址: %s\n" +
            "操作描述: %s\n" +
            "操作类型: %s\n" +
            "接口方法: %s\n" +
            "请求参数: %s\n" +
            "执行状态: %s\n" +
            "执行耗时: %dms\n" +
//            "返回结果: %s\n" +
            "错误信息: %s\n" +
            "操作时间: %s\n" +
            "请求URI: %s\n" +
            "用户代理: %s\n" +
            "================",
            operator,
            clientIp,
            description,
            operationType,
            method,
            params != null && params.length() > 500 ? params.substring(0, 500) + "...[截断]" : params,
            status,
            executionTime,
//            result != null && result.length() > 500 ? result.substring(0, 500) + "...[截断]" : result,
            errorMessage,
            operationTime,
            requestUri,
            userAgent != null && userAgent.length() > 200 ? userAgent.substring(0, 200) + "...[截断]" : userAgent
        );
    }
}
