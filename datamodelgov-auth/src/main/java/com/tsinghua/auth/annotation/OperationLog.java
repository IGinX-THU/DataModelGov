package com.tsinghua.auth.annotation;

import java.lang.annotation.*;

/**
 * 操作日志注解
 * 用于标记需要记录操作日志的方法
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface OperationLog {
    
    /**
     * 操作描述
     */
    String value() default "";
    
    /**
     * 操作类型
     */
    OperationType type() default OperationType.OTHER;
    
    /**
     * 是否记录请求参数
     */
    boolean recordParams() default true;
    
    /**
     * 是否记录返回结果
     */
    boolean recordResult() default true;
    
    /**
     * 操作类型枚举
     */
    enum OperationType {
        CREATE,    // 创建
        UPDATE,    // 更新
        DELETE,    // 删除
        QUERY,     // 查询
        LOGIN,     // 登录
        LOGOUT,    // 登出
        EXPORT,    // 导出
        IMPORT,    // 导入
        OTHER      // 其他
    }
}
