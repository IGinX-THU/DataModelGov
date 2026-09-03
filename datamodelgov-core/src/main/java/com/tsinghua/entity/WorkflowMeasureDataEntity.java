package com.tsinghua.entity;

import lombok.Data;

/**
 * 工作流测量数据行实体
 * 每个工况点一行，保存从训练/测试 Excel 读取的测量变量值
 */
@Data
public class WorkflowMeasureDataEntity {
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
     * 燃气发生器转速
     */
    private Double Np_mean;

    /**
     * 燃气涡轮转速
     */
    private Double Ng_mean;

    /**
     * 燃油流量
     */
    private Double Wf_mean;

    /**
     * 动力涡轮扭矩
     */
    private Double Mkp_mean;

    /**
     * 燃气涡轮扭矩
     */
    private Double Mkg_mean;

    /**
     * 进口总温
     */
    private Double Tt1_mean;

    /**
     * 压气机进口总压
     */
    private Double Pt2_mean;

    /**
     * 压气机出口总压
     */
    private Double Pt3_mean;

    /**
     * 压气机出口总温
     */
    private Double Tt3_mean;

    /**
     * 燃气涡轮出口总温
     */
    private Double Tt45_mean;

    /**
     * 燃气涡轮出口总压
     */
    private Double Pt45_mean;

    /**
     * 环境压力
     */
    private Double Pamb_mean;

    /**
     * 环境温度
     */
    private Double Tamb_mean;

    /**
     * 高度
     */
    private Double Altitude_mean;

    /**
     * 马赫数
     */
    private Double Mach_mean;
}
