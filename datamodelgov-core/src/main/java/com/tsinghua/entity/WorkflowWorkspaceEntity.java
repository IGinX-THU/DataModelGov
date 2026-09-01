package com.tsinghua.entity;

import lombok.Data;

/**
 * 工作流工作区实体
 * 每次创建项目生成一条工作区记录，保存项目信息和数据合同
 */
@Data
public class WorkflowWorkspaceEntity {
    /**
     * 创建时间戳（主键）
     */
    private Long timestamp;

    /**
     * 工作区 ID
     */
    private String id;

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
     * 作业名称（用户输入的项目名称）
     */
    private String jobName;

    /**
     * 备注
     */
    private String notes;

    /**
     * 训练数据文件名
     */
    private String trainingDataFile;

    /**
     * 测试数据文件名
     */
    private String testDataFile;

    /**
     * 状态
     */
    private String status;

    /**
     * 工作目录（相对路径）
     */
    private String workingDirectory;

    /**
     * 工作区目录绝对路径
     */
    private String workspaceDir;

    /**
     * 程序文件 MD5
     */
    private String programFileMd5;

    /**
     * 程序元数据时间戳（ProgramEntity.timestamp，作为外键加强关联）
     */
    private Long programTimestamp;

    /**
     * 配置 SHA256
     */
    private String configSha256;

    /**
     * 创建时间
     */
    private Long createdAt;

    /**
     * 更新时间
     */
    private Long updatedAt;

    /**
     * 初始化状态：SUCCEEDED / FALLBACK / FAILED / INITIALIZING
     */
    private String initStatus;

    /**
     * 初始化消息（失败/降级时的错误信息）
     */
    private String initMessage;

    /**
     * 工况行数
     */
    private Integer initRowCount;

    /**
     * 训练分组数
     */
    private Integer initGroupCount;

    /**
     * DLL 哈希
     */
    private String initDllHash;

    /**
     * 数据合同是否有效
     */
    private Boolean initValid;

    /**
     * 零修正回放是否全部有效
     */
    private Boolean initBaselineValid;

    /**
     * 缺失字段（逗号分隔）
     */
    private String initMissingColumns;

    /**
     * 初始化开始时间
     */
    private String initStartedAt;

    /**
     * 初始化完成时间
     */
    private String initCompletedAt;

    /**
     * 上传数据集记录（JSON）
     */
    private String uploadedDatasets;

    /**
     * 数据合同（JSON）
     */
    private String dataContract;

    /**
     * 必需文件哈希（JSON）
     */
    private String requiredFileHashes;
}
