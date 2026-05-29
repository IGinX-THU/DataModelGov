package com.tsinghua.entity;

import lombok.Data;

/**
 * 仿真执行实体
 * 记录仿真的执行状态和结果
 */
@Data
public class SimulationExecutionEntity {
    /**
     * 执行时间戳（作为主键，每次执行都有唯一的时间戳）
     */
    private Long timestamp;

    /**
     * 档案ID
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
     * 输入测点路径（JSON数组，首节点输入）
     */
    private String inputMeasurements;

    /**
     * 输出测点路径（JSON数组，末节点输出）
     */
    private String outputMeasurements;

    /**
     * 结果回写路径前缀
     */
    private String outputTable;

    /**
     * 执行结果
     */
    private Object result;

    /**
     * 错误信息
     */
    private String error;

    /**
     * 进程运行日志
     */
    private String processLog;
}
