package com.tsinghua.entity;

import lombok.Data;

/**
 * 仿真程序运行任务实体
 * 每次运行生成一条任务记录，保存输入参数和输出结果
 */
@Data
public class ProgramTaskEntity {
    /**
     * 任务时间戳（主键）
     */
    private Long timestamp;

    /**
     * 程序名称
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
     * 开始时间
     */
    private Long startTime;

    /**
     * 结束时间
     */
    private Long endTime;

    /**
     * 执行状态：RUNNING/SUCCESS/ERROR/STOPPED
     */
    private String status;

    /**
     * 错误信息
     */
    private String error;

    /**
     * 输入参数 - 仿真停止时间
     */
    private String stopTime;

    /**
     * 输入参数 - 固定步长
     */
    private String fixedStep;

    /**
     * 输入参数 - NP指令（旧字段，兼容历史数据；新任务用 paramsJson）
     */
    private String npCommand;

    /**
     * 输入参数 - 负载功率（旧字段，兼容历史数据；新任务用 paramsJson）
     */
    private String loadPower;

    /**
     * 动态参数 JSON（新字段，存储 ProgramConfig.parameters 定义的全部参数值）
     */
    private String paramsJson;

    /**
     * 模型文件
     */
    private String modelFile;

    /**
     * 结果CSV路径
     */
    private String resultCsvPath;

    /**
     * 运行日志路径
     */
    private String logPath;

    /**
     * 结果目录路径
     */
    private String resultDir;

    /**
     * 结果CSV导入IGinX的表全路径
     */
    private String outputTable;

    /**
     * 运行日志内容（最后20000字符）
     */
    private String runLog;
}
