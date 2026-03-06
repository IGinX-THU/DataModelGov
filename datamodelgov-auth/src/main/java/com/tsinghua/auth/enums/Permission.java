package com.tsinghua.auth.enums;

/**
 * 权限枚举 - 精简版
 */
public enum Permission {
    // 数据源管理权限
    DATASOURCE_REGISTER,
    DATASOURCE_REMOVE,
    DATASOURCE_LIST,
    DATASOURCE_TREE,
    
    // 数据表管理权限
    DATA_QUERY,
    DATA_IMPORT,
    DATA_EXPORT,
    DATA_DELETE,
    DATA_RELATIONAL_QUERY,
    DATA_RELATIONAL_COUNT,
    DATA_RELATIONAL_EXPORT,
    
    // 模型文件管理权限
    MODEL_UPLOAD,
    MODEL_DOWNLOAD,
    MODEL_QUERY_META,
    MODEL_SAVE_META,
    MODEL_HISTORY,
    MODEL_DELETE,
    
    // 关联规则管理权限
    ASSOCIATION_RULES_SAVE,
    ASSOCIATION_RULES_QUERY,
    ASSOCIATION_RULES_COUNT,
    ASSOCIATION_RULES_DETAIL,
    ASSOCIATION_RULES_DELETE,
    
    // 用户管理权限
    USER_MANAGE;
    
    /**
     * 获取权限描述（用于错误提示）
     */
    public String getDescription() {
        switch (this) {
            case DATASOURCE_REGISTER: return "注册数据源";
            case DATASOURCE_REMOVE: return "移除数据源";
            case DATASOURCE_LIST: return "数据源列表";
            case DATASOURCE_TREE: return "数据源树";
            case DATA_QUERY: return "数据查询";
            case DATA_IMPORT: return "数据导入";
            case DATA_EXPORT: return "数据导出";
            case DATA_DELETE: return "数据删除";
            case DATA_RELATIONAL_QUERY: return "关系数据查询";
            case DATA_RELATIONAL_COUNT: return "关系数据总量查询";
            case DATA_RELATIONAL_EXPORT: return "关系数据Excel导出";
            case MODEL_UPLOAD: return "上传模型";
            case MODEL_DOWNLOAD: return "下载模型";
            case MODEL_QUERY_META: return "模型元数据详情";
            case MODEL_SAVE_META: return "保存模型元数据";
            case MODEL_HISTORY: return "模型元数据历史";
            case MODEL_DELETE: return "移除模型资产";
            case ASSOCIATION_RULES_SAVE: return "创建关联规则";
            case ASSOCIATION_RULES_QUERY: return "分页查询关联规则";
            case ASSOCIATION_RULES_COUNT: return "查询关联规则总数";
            case ASSOCIATION_RULES_DETAIL: return "关联规则详情";
            case ASSOCIATION_RULES_DELETE: return "删除关联规则";
            case USER_MANAGE: return "用户管理";
            default: return this.name();
        }
    }
}
