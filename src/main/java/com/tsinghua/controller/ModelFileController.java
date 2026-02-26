package com.tsinghua.controller;

import com.tsinghua.dto.ModelMetaDto;
import com.tsinghua.dto.Result;
import com.tsinghua.dto.UploadResult;
import com.tsinghua.service.ModelFileService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import javax.servlet.http.HttpServletResponse;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

@RestController
@RequestMapping("/api/model")
public class ModelFileController {

    @Autowired
    private ModelFileService modelFileService;

    @PostMapping(value = "/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public Result<?> handleFileUpload(
            @RequestPart("file") MultipartFile file,
            @RequestParam("name") String name,
            @RequestParam("version") String version) throws Exception {

        if (file.isEmpty()) {
            return Result.error("上传文件不能为空。");
        }

        UploadResult result = modelFileService.uploadModel(file, name, version);
        return Result.success(result);
    }

    @PostMapping("/download")
    public void handleFileDownload(
            @RequestParam String name,
            @RequestParam String version,
            @RequestParam(value = "fileName", required = false) String fileName,
            HttpServletResponse response) throws Exception {

        byte[] fileData = modelFileService.downloadModel(name, version);
        ModelMetaDto queryMeta = modelFileService.queryMeta(name, version);
        fileName = queryMeta.getFileName();

        // 设置响应头
        String encodedFilename = URLEncoder.encode(fileName, StandardCharsets.UTF_8.name())
                .replace("+", "%20");

        response.setContentType(MediaType.APPLICATION_OCTET_STREAM_VALUE);
        response.setHeader(HttpHeaders.CONTENT_DISPOSITION,
                "attachment; filename=\"" + encodedFilename + "\"; filename*=UTF-8''" + encodedFilename);
        response.setContentLength(fileData.length);

        // 写入响应流
        response.getOutputStream().write(fileData);
        response.flushBuffer();
    }

    @GetMapping( "/metas")
    public Result<ModelMetaDto> queryMeta(
            @RequestParam("name") String name,
            @RequestParam("version") String version) throws Exception {
        ModelMetaDto result = modelFileService.queryMeta(name, version);
        return Result.success(result);
    }

}
