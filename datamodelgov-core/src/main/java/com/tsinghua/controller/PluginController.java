package com.tsinghua.controller;

import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.model.Result;
import com.tsinghua.program.extension.PluginEntity;
import com.tsinghua.program.extension.PluginService;
import com.tsinghua.service.ProgramService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.PrintWriter;
import java.util.List;
import java.util.Map;

/**
 * 前端插件管理（只读）。
 * 插件由开发者在 resources/plugins/<id>/ 下维护，随 jar 发布。
 * 前端通过 GET /api/program/plugin 列表，GET /api/program/plugin/{id}/entry.js 动态加载。
 */
@Slf4j
@RestController
@RequestMapping("/api/program/plugin")
@Api(tags = "仿真程序插件管理")
public class PluginController {

    @Autowired
    private PluginService pluginService;

    @Autowired
    private ProgramService programService;

    @ApiOperation("列出全部插件")
    @GetMapping
    @RequirePermission(Permission.READ)
    public Result<List<PluginEntity>> list() {
        List<PluginEntity> list = pluginService.list();
        // 统计引用计数
        Map<String, Integer> refCounts = programService.countPluginReferences();
        list.forEach(p -> p.setReferenceCount(refCounts.getOrDefault(p.getId(), 0)));
        return Result.success("操作成功", list);
    }

    @ApiOperation("获取插件元数据")
    @GetMapping("/{id}")
    @RequirePermission(Permission.READ)
    public Result<PluginEntity> get(@PathVariable("id") String id) {
        PluginEntity p = pluginService.get(id);
        if (p == null) return Result.error("插件不存在");
        return Result.success("操作成功", p);
    }

    @ApiOperation("下载插件入口 JS（供前端动态 import）")
    @GetMapping("/{id}/entry.js")
    public void downloadEntryJs(@PathVariable("id") String id, HttpServletResponse response) throws IOException {
        String content = pluginService.readEntryJs(id);
        if (content == null) {
            response.sendError(404, "插件入口 JS 不存在");
            return;
        }
        response.setContentType("application/javascript; charset=UTF-8");
        response.setHeader("Cache-Control", "no-cache");
        PrintWriter writer = response.getWriter();
        writer.write(content);
        writer.flush();
    }

    @ApiOperation("下载插件 CSS")
    @GetMapping("/{id}/style.css")
    public void downloadCss(@PathVariable("id") String id, HttpServletResponse response) throws IOException {
        String content = pluginService.readCss(id);
        if (content == null) {
            response.sendError(404, "插件 CSS 不存在");
            return;
        }
        response.setContentType("text/css; charset=UTF-8");
        response.setHeader("Cache-Control", "no-cache");
        PrintWriter writer = response.getWriter();
        writer.write(content);
        writer.flush();
    }
}
