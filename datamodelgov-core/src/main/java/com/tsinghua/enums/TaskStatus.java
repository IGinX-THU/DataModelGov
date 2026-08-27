package com.tsinghua.enums;

/**
 * 统一任务状态（文档第 13 节）。
 *
 * <p>存储用 {@link #name()}（英文），显示用 {@link #getLabel()}（中文）。</p>
 */
public enum TaskStatus {
    // 仿真运行（program-run）兼容
    PENDING("pending", "待配置"),
    QUEUED("queued", "排队中"),
    RUNNING("running", "运行中"),
    STOPPED("stopped", "已停止"),
    SUCCESS("success", "已完成"),
    FAILED("failed", "已失败"),

    // 程序工作流（program-workflow）文档第 13 节
    PENDING_CONFIG("pending_config", "待配置"),
    CREATING("creating", "创建中"),
    INITIALIZING("initializing", "初始化中"),
    READY("ready", "就绪"),
    WORKFLOW_RUNNING("workflow_running", "运行中"),
    CANCELLING("cancelling", "取消中"),
    COMPLETED("completed", "已完成"),
    SKIPPED("skipped", "已跳过"),
    WORKFLOW_FAILED("workflow_failed", "已失败"),
    PENDING_REVIEW("pending_review", "等待审核"),
    PUBLISHED("published", "已发布"),

    // 审核子状态
    REVIEW_APPROVED("review_approved", "已审核通过"),
    REVIEW_REJECTED("review_rejected", "已驳回");

    private final String value;
    private final String label;

    TaskStatus(String value, String label) {
        this.value = value;
        this.label = label;
    }

    public String getValue() { return value; }
    public String getLabel() { return label; }

    /** 按存储值查找枚举，找不到返回 null */
    public static TaskStatus fromValue(String value) {
        if (value == null) return null;
        for (TaskStatus s : values()) {
            if (s.value.equals(value)) return s;
        }
        return null;
    }

    /** 存储值 → 中文标签，找不到原样返回 */
    public static String label(String value) {
        TaskStatus s = fromValue(value);
        return s != null ? s.label : value;
    }

    /** 是否终态 */
    public static boolean isTerminal(String value) {
        TaskStatus s = fromValue(value);
        if (s == null) return false;
        switch (s) {
            case COMPLETED: case WORKFLOW_FAILED: case CANCELLING: case SKIPPED:
            case SUCCESS: case FAILED: case STOPPED:
                return true;
            default:
                return false;
        }
    }
}
