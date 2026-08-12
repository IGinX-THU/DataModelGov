package com.tsinghua.controller;

import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.io.File;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.nio.file.Paths;

@RestController
@RequestMapping("/api/doc")
public class DocController {

    @GetMapping("/user-manual/file")
    public ResponseEntity<Resource> getUserManualFile() throws Exception {
        Path docPath = resolveDocPath();
        File docFile = docPath.toFile();

        if (!docFile.exists()) {
            return ResponseEntity.notFound().build();
        }

        String encodedFileName = URLEncoder.encode(docFile.getName(), StandardCharsets.UTF_8.name()).replace("+", "%20");
        Resource resource = new FileSystemResource(docFile);

        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType("application/vnd.openxmlformats-officedocument.wordprocessingml.document"))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename*=UTF-8''" + encodedFileName)
                .contentLength(docFile.length())
                .body(resource);
    }

    private Path resolveDocPath() {
        Path current = Paths.get(System.getProperty("user.dir"));
        Path directPath = current.resolve("doc").resolve("数据与模型一体化管理软件-用户手册.docx");
        if (directPath.toFile().exists()) {
            return directPath;
        }
        return current.getParent().resolve("doc").resolve("数据与模型一体化管理软件-用户手册.docx");
    }
}
