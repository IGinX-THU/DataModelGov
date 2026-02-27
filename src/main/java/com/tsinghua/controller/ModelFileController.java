package com.tsinghua.controller;

import com.tsinghua.dto.ModelMetaDto;
import com.tsinghua.dto.Result;
import com.tsinghua.dto.UploadResult;
import com.tsinghua.service.ModelFileService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import javax.servlet.http.HttpServletResponse;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.List;

@Api(tags = "模型资产管理")
@RestController
@RequestMapping("/api/model")
public class ModelFileController {

    @Autowired
    private ModelFileService modelFileService;

    @ApiOperation("上传模型")
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

    @ApiOperation("下载模型")
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

    @ApiOperation("模型元数据详情")
    @GetMapping( "/metas")
    public Result<ModelMetaDto> queryMeta(
            @RequestParam("name") String name,
            @RequestParam("version") String version) throws Exception {
        ModelMetaDto result = modelFileService.queryMeta(name, version);
        return Result.success(result);
    }

    @ApiOperation("保存模型元数据")
    @PostMapping("/metas")
    public Result<?> saveMeta(@RequestBody ModelMetaDto modelMetaDto) throws Exception {
        modelFileService.saveModelMetadata(modelMetaDto);
        return Result.success("元数据保存成功");
    }

    @ApiOperation("模型元数据历史")
    @GetMapping( "/history")
    public Result<List<ModelMetaDto>> queryMetaList(
            @RequestParam("name") String name) {
        return Result.success(modelFileService.queryMetaList(name));
    }

}
