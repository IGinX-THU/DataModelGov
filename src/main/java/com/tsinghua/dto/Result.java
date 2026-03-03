package com.tsinghua.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 统一返回结果类
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class Result<T> {
    private int code;       // 状态码：200成功，400参数错误，500系统错误
    private String message;  // 提示信息
    private T data;         // 业务数据

    // 成功响应（无数据）
    public static Result<Void> success(String message) {
        return new Result<>(200, message, null);
    }

    // 成功响应（有数据）
    public static <T> Result<T> success(T data) {
        return new Result<>(200, "操作成功", data);
    }

    // 错误响应
    public static Result<Void> error(String message) {
        return new Result<>(500, message, null);
    }

    // 参数错误响应
    public static Result<Void> paramError(String message) {
        return new Result<>(400, message, null);
    }
}
