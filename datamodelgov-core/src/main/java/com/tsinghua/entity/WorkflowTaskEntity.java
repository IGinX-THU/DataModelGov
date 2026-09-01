package com.tsinghua.entity;

import lombok.Data;

/**
 * 工作流任务实体
 * 每次执行工作流动作生成一条任务记录，保存输入和输出结果
 */
@Data
public class WorkflowTaskEntity {
    /**
     * 创建时间戳（主键）
     */
    private Long timestamp;

    /**
     * 任务 ID
     */
    private String taskId;

    /**
     * 工作区 ID
     */
    private String workspaceId;

    /**
     * 程序名称（与 ProgramTaskEntity 一致，用于按程序过滤任务）
     */
    private String programName;

    /**
     * 程序版本
     */
    private String programVersion;

    /**
     * 项目名称
     */
    private String projectName;

    /**
     * 动作 Key
     */
    private String actionKey;

    /**
     * 入口点
     */
    private String entryPoint;

    /**
     * 阶段
     */
    private String stage;

    /**
     * 结果类型
     */
    private String resultType;

    /**
     * 执行状态
     */
    private String status;

    /**
     * 错误信息
     */
    private String error;

    /**
     * 创建时间
     */
    private Long createdAt;

    /**
     * 开始时间
     */
    private Long startedAt;

    /**
     * 完成时间
     */
    private Long finishedAt;

    /**
     * 日志路径
     */
    private String logPath;

    /**
     * 状态消息（进度信息）
     */
    private String statusMessage;

    /**
     * 审核状态
     */
    private String reviewStatus;

    /**
     * 发布状态
     */
    private String publicationStatus;

    /**
     * 结果（JSON，分块存储）
     */
    private String result;
}
