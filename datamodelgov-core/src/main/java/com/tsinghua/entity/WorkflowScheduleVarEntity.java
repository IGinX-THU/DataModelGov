package com.tsinghua.entity;

import lombok.Data;

/**
 * 工作流调度变量行实体
 * 每个工况点一行，保存 MATLAB 零修正回放计算的调度变量和训练分组
 */
@Data
public class WorkflowScheduleVarEntity {
    /**
     * 时间戳（主键，行序号）
     */
    private Long timestamp;

    /**
     * 工作区ID
     */
    private String workspaceId;

    /**
     * 工况点ID
     */
    private String pointId;

    /**
     * 行序号
     */
    private Integer rowIndex;

    /**
     * 数据角色（training/test）
     */
    private String dataRole;

    /**
     * 训练分组（G1/G2/...）
     */
    private String trainingGroup;

    /**
     * AC相对换算转速
     */
    private Double acRelativeCorrectedSpeed;

    /**
     * 进气道换算流量（DLL计算）
     */
    private Double inletCorrectedMassFlow;

    /**
     * 燃烧室进口换算流量（DLL计算）
     */
    private Double burnerInletCorrectedMassFlow;

    /**
     * GT物理压比（DLL计算）
     */
    private Double gtTotalPressureRatio;

    /**
     * GT-PT涵道换算流量（DLL计算）
     */
    private Double gtPtDuctCorrectedMassFlow;

    /**
     * PT物理压比（DLL计算）
     */
    private Double ptTotalPressureRatio;

    /**
     * PT-尾喷管涵道换算流量（DLL计算）
     */
    private Double ptNozzleDuctCorrectedMassFlow;

    /**
     * 测量燃油流量归一化坐标
     */
    private Double measuredFuelNormalizedCoordinate;

    /**
     * DLL计算的AC换算转速
     */
    private Double acCorrectedSpeedDll;

    /**
     * 是否收敛
     */
    private Boolean converged;

    /**
     * 最大模型残差
     */
    private Double maxModelResidual;
}
