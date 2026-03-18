package com.tsinghua.auth.enums;

/**
 * 用户角色常量类 - 便于数据库存储
 */
public final class UserRole {
    
    public static final String ADMIN = "ADMIN";
    public static final String DATA_ENGINEER = "DATA_ENGINEER";
    public static final String MODEL_ENGINEER = "MODEL_ENGINEER";
    public static final String SIMULATION_ENGINEER = "SIMULATION_ENGINEER";
    
    /**
     * 获取角色描述（用于错误提示）
     */
    public static String getDescription(String role) {
        switch (role) {
            case ADMIN: return "管理员";
            case DATA_ENGINEER: return "数据工程师";
            case MODEL_ENGINEER: return "模型工程师";
            case SIMULATION_ENGINEER: return "仿真工程师";
            default: return role;
        }
    }
    
    /**
     * 验证角色是否有效
     */
    public static boolean isValid(String role) {
        return ADMIN.equals(role) || DATA_ENGINEER.equals(role) || 
               MODEL_ENGINEER.equals(role) || SIMULATION_ENGINEER.equals(role);
    }
    
    /**
     * 获取所有角色列表
     */
    public static String[] getAllRoles() {
        return new String[]{ADMIN, DATA_ENGINEER, MODEL_ENGINEER, SIMULATION_ENGINEER};
    }
}
