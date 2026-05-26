package com.tsinghua.entity;

import lombok.Data;

/**
 * 仿真执行实体
 * 记录仿真的执行状态和结果
 */
@Data
public class SimulationExecutionEntity {
    /**
     * 执行ID（使用archiveId）
     */
    private Long archiveId;

    /**
     * 档案名称
     */
    private String archiveName;

    /**
     * 开始时间
     */
    private Long startTime;

    /**
     * 结束时间
     */
    private Long endTime;

    /**
     * 执行状态：running, completed, failed
     */
    private String status;

    /**
     * 执行结果
     */
    private Object result;

    /**
     * 错误信息
     */
    private String error;
}
