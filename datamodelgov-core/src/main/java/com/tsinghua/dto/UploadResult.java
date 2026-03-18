package com.tsinghua.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 上传结果封装类
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class UploadResult {
    private String name;
    private String version;
    private String fileName;
    private long fileSize;
    private int chunkCount;
    private String storagePath;
    private String fileMd5;
}

