package com.tsinghua.controller;

import com.tsinghua.dto.*;
import com.tsinghua.model.Result;
import com.tsinghua.service.DataTableService;
import com.tsinghua.service.RelationalDataService;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.annotation.OperationLog;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import io.swagger.annotations.ApiParam;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import javax.servlet.http.HttpServletResponse;
import javax.validation.Valid;
import java.io.IOException;
import java.io.OutputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/**
 * 数据查询与管理接口
 */
@Api(tags = "数据查询与管理")
@Slf4j
@RestController
@RequestMapping("/api/data")
public class DataTableController {

    @Autowired
    private RelationalDataService relationalDataService;

    @Autowired
    private DataTableService dataTableService;

    /**
     * 数据查询
     */
    @ApiOperation("数据查询")
    @PostMapping("/query")
    @RequirePermission(Permission.DATA_READ)
    public com.tsinghua.model.Result<TableDto> queryData(@Validated @RequestBody DataQueryRequest request) {
        return com.tsinghua.model.Result.success(dataTableService.queryData(request));
    }

    /**
     * 导入数据
     */
    @ApiOperation("导入数据")
    @PostMapping(value = "/import", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @RequirePermission(Permission.DATA_CREATE)
    @OperationLog(value = "导入数据", type = OperationLog.OperationType.IMPORT, recordParams = false)
    public com.tsinghua.model.Result<Void> importData(// 使用 @RequestPart 接收JSON格式的配置参数
                                                      @RequestPart("config") @Valid DataImportRequest config,
                                                      @ApiParam(value = "数据文件", required = true) @RequestPart("file") MultipartFile file) throws Exception {
        long recordsNum =  dataTableService.importData(file, config);
        return Result.success(String.format("数据导入成功，导入记录数: %d", recordsNum));

    }

    /**
     * 导出数据
     */
    @ApiOperation("导出数据")
    @PostMapping("/export")
    @RequirePermission(Permission.DATA_READ)
    @OperationLog(value = "导出数据", type = OperationLog.OperationType.EXPORT, recordResult = false)
    public void exportData(@Validated @RequestBody DataQueryRequest request, HttpServletResponse response) {
        try {
            dataTableService.exportData(request, response);
        } catch (RuntimeException e) {
            log.error("数据导出失败", e);
            // 重置响应状态
            response.reset();
            response.setContentType("application/json;charset=UTF-8");
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            try {
                OutputStream outputStream = response.getOutputStream();
                String errorMessage = "{\"success\":false,\"message\":\"数据导出失败: " + e.getMessage() + "\"}";
                outputStream.write(errorMessage.getBytes("UTF-8"));
                outputStream.flush();
            } catch (IOException ex) {
                log.error("写入错误响应失败", ex);
            }
        } catch (Exception e) {
            log.error("数据导出异常", e);
            // 重置响应状态
            response.reset();
            response.setContentType("application/json;charset=UTF-8");
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            try {
                OutputStream outputStream = response.getOutputStream();
                String errorMessage = "{\"success\":false,\"message\":\"数据导出异常: " + e.getMessage() + "\"}";
                outputStream.write(errorMessage.getBytes("UTF-8"));
                outputStream.flush();
            } catch (IOException ex) {
                log.error("写入错误响应失败", ex);
            }
        }
    }

    /**
     * 数据删除
     */
    @ApiOperation("数据删除")
    @PostMapping("/delete")
    @RequirePermission(Permission.DATA_DELETE)
    @OperationLog(value = "删除数据", type = OperationLog.OperationType.DELETE)
    public com.tsinghua.model.Result<Void> deleteData(@Validated @RequestBody DataQueryRequest request) {
        dataTableService.deleteData(request);
        return com.tsinghua.model.Result.success("删除成功");
    }

    /**
     * 关系数据查询
     */
    @ApiOperation("关系数据查询")
    @PostMapping("/relational/query")
    @RequirePermission(Permission.DATA_READ)
    public com.tsinghua.model.Result<TableDto> queryData(@Validated @RequestBody RelationalQueryRequest request) {
        return com.tsinghua.model.Result.success(relationalDataService.queryData(request));
    }

    /**
     * 关系数据总量查询
     */
    @ApiOperation("关系数据总量查询")
    @PostMapping("/relational/count")
    @RequirePermission(Permission.DATA_READ)
    public com.tsinghua.model.Result<Object> countData(@Validated @RequestBody RelationalQueryRequest request) {
        return com.tsinghua.model.Result.success(relationalDataService.countData(request));
    }

    /**
     * 关系数据Excel导出
     */
    @ApiOperation("关系数据Excel导出")
    @PostMapping("/relational/export")
    @RequirePermission(Permission.DATA_READ)
    @OperationLog(value = "关系数据Excel导出", type = OperationLog.OperationType.EXPORT, recordResult = false)
    public void exportRelationalDataToExcel(@Validated @RequestBody RelationalQueryRequest request, 
                                         HttpServletResponse response) throws IOException {
        try {
            log.info("开始Excel导出请求，表名: {}", request.getTableName());
            
            // 设置响应头
            String fileName = request.getTableName() + "_" + System.currentTimeMillis() + ".xlsx";
            String encodedFileName = URLEncoder.encode(fileName, StandardCharsets.UTF_8.name())
                    .replace("+", "%20");
            
            response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
            response.setCharacterEncoding("UTF-8");
            response.setHeader(HttpHeaders.CONTENT_DISPOSITION, 
                    "attachment; filename=\"" + encodedFileName + "\"; filename*=UTF-8''" + encodedFileName);
            response.setHeader(HttpHeaders.CACHE_CONTROL, "no-cache, no-store, must-revalidate");
            response.setHeader(HttpHeaders.PRAGMA, "no-cache");
            response.setHeader(HttpHeaders.EXPIRES, "0");
            
            // 确保响应流立即开始
            response.flushBuffer();
            
            // 流式导出Excel
            relationalDataService.exportDataToExcelStream(request, response.getOutputStream());
            
            log.info("Excel导出完成，表名: {}", request.getTableName());
            
        } catch (NoClassDefFoundError e) {
            log.error("POI类加载异常，Excel导出失败", e);
            // 重置响应状态
            response.reset();
            response.setContentType("application/json;charset=UTF-8");
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"success\":false,\"message\":\"Excel导出功能异常，请检查系统依赖: " + e.getMessage() + "\"}");
            response.getWriter().flush();
        } catch (AbstractMethodError e) {
            log.error("XML解析器版本冲突，Excel导出失败", e);
            // 重置响应状态
            response.reset();
            response.setContentType("application/json;charset=UTF-8");
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"success\":false,\"message\":\"XML解析器版本冲突，请检查系统依赖: " + e.getMessage() + "\"}");
            response.getWriter().flush();
        } catch (Exception e) {
            log.error("Excel导出失败", e);
            // 重置响应状态
            response.reset();
            response.setContentType("application/json;charset=UTF-8");
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"success\":false,\"message\":\"Excel导出失败: " + e.getMessage() + "\"}");
            response.getWriter().flush();
        }
    }

}
