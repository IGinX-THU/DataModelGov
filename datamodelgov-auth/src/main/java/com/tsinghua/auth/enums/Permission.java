package com.tsinghua.auth.enums;

/**
 * 权限枚举 - 按资源类型分组的CRUD权限
 */
public enum Permission {
    // 数据源管理权限
    DATASOURCE_CREATE,
    DATASOURCE_READ,
    DATASOURCE_UPDATE,
    DATASOURCE_DELETE,
    
    // 数据表管理权限
    DATA_CREATE,
    DATA_READ,
    DATA_UPDATE,
    DATA_DELETE,
    
    // 模型文件管理权限
    MODEL_CREATE,
    MODEL_READ,
    MODEL_UPDATE,
    MODEL_DELETE,
    
    // 关联规则管理权限
    ASSOCIATION_RULES_CREATE,
    ASSOCIATION_RULES_READ,
    ASSOCIATION_RULES_UPDATE,
    ASSOCIATION_RULES_DELETE,
    
    // 解析规则管理权限
    PARSING_RULES_CREATE,
    PARSING_RULES_READ,
    PARSING_RULES_UPDATE,
    PARSING_RULES_DELETE,
    
    // 运行任务管理权限
    RUN_TASK_CREATE,
    RUN_TASK_READ,
    RUN_TASK_UPDATE,
    RUN_TASK_DELETE,
    
    // 用户管理权限
    USER_CREATE,
    USER_READ,
    USER_UPDATE,
    USER_DELETE,

    // 通用权限
    CREATE,
    READ,
    UPDATE,
    DELETE;
    
    /**
     * 获取权限描述（用于错误提示）
     */
    public String getDescription() {
        switch (this) {
            // 数据源管理权限
            case DATASOURCE_CREATE: return "创建数据源";
            case DATASOURCE_READ: return "查看数据源";
            case DATASOURCE_UPDATE: return "更新数据源";
            case DATASOURCE_DELETE: return "删除数据源";
            
            // 数据表管理权限
            case DATA_CREATE: return "创建数据";
            case DATA_READ: return "查看数据";
            case DATA_UPDATE: return "更新数据";
            case DATA_DELETE: return "删除数据";
            
            // 模型文件管理权限
            case MODEL_CREATE: return "上传模型";
            case MODEL_READ: return "查看模型";
            case MODEL_UPDATE: return "更新模型";
            case MODEL_DELETE: return "删除模型";
            
            // 关联规则管理权限
            case ASSOCIATION_RULES_CREATE: return "创建关联规则";
            case ASSOCIATION_RULES_READ: return "查看关联规则";
            case ASSOCIATION_RULES_UPDATE: return "更新关联规则";
            case ASSOCIATION_RULES_DELETE: return "删除关联规则";
            
            // 解析规则管理权限
            case PARSING_RULES_CREATE: return "创建解析规则";
            case PARSING_RULES_READ: return "查看解析规则";
            case PARSING_RULES_UPDATE: return "更新解析规则";
            case PARSING_RULES_DELETE: return "删除解析规则";
            
            // 运行任务管理权限
            case RUN_TASK_CREATE: return "创建运行任务";
            case RUN_TASK_READ: return "查看运行任务";
            case RUN_TASK_UPDATE: return "更新运行任务";
            case RUN_TASK_DELETE: return "删除运行任务";
            
            // 用户管理权限
            case USER_CREATE: return "创建用户";
            case USER_READ: return "查看用户";
            case USER_UPDATE: return "更新用户";
            case USER_DELETE: return "删除用户";

            // 通用权限
            case CREATE: return "创建";
            case READ: return "查看";
            case UPDATE: return "更新";
            case DELETE: return "删除";

            default: return this.name();
        }
    }
}
