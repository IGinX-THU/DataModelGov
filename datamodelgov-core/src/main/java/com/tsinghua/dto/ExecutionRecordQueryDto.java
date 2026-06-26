package com.tsinghua.dto;

import lombok.Data;

/**
 * 仿真执行记录查询DTO
 */
@Data
public class ExecutionRecordQueryDto {
    private String archiveName;
    private Long archiveId;
    private String projectName;
    private String status;
    private Long startTime;
    private Long endTime;
    private Integer pageNum;
    private Integer pageSize;
}
