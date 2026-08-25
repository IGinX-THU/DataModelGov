package com.tsinghua.program.extension;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 前端插件管理（classpath 方案）。
 *
 * 插件放在 resources/plugins/<pluginId>/ 下，每个目录包含：
 *   entry.js   —— 入口 JS（ES module，export default 类或工厂函数）
 *   style.css  —— 可选 CSS
 *   meta.json  —— 元数据 { id, name, description, program, version, author }
 *
 * 启动时扫描 classpath:plugins/*meta.json 加载索引，运行时通过 /api/program/plugin/{id}/entry.js 动态加载。
 */
@Slf4j
@Service
public class PluginService {

    private final Map<String, PluginEntity> plugins = new LinkedHashMap<>();
    private final ObjectMapper mapper = new ObjectMapper();

    @PostConstruct
    public void init() {
        loadFromClasspath();
    }

    /** 扫描 classpath:plugins/*meta.json，加载所有插件元数据 */
    private void loadFromClasspath() {
        plugins.clear();
        try {
            PathMatchingResourcePatternResolver resolver = new PathMatchingResourcePatternResolver();
            Resource[] resources = resolver.getResources("classpath:plugins/*/meta.json");
            for (Resource res : resources) {
                try (InputStream is = res.getInputStream()) {
                    PluginEntity entity = mapper.readValue(is, PluginEntity.class);
                    // 从 URL 推断 pluginId（目录名）
                    String url = res.getURL().toString();
                    String id = extractPluginId(url);
                    if (id == null && entity.getId() != null) id = entity.getId();
                    if (id == null) continue;
                    entity.setId(id);
                    // 检测 entry.js 和 style.css 是否存在
                    String base = "classpath:plugins/" + id + "/";
                    Resource entryRes = resolver.getResource(base + "entry.js");
                    entity.setEntryFile(entryRes.exists() ? "entry.js" : null);
                    Resource cssRes = resolver.getResource(base + "style.css");
                    entity.setCssFile(cssRes.exists() ? "style.css" : null);
                    plugins.put(id, entity);
                    log.info("加载插件: id={}, name={}, program={}", id, entity.getName(), entity.getProgram());
                } catch (Exception e) {
                    log.warn("加载插件元数据失败: {}", res.getFilename(), e);
                }
            }
        } catch (IOException e) {
            log.warn("扫描插件目录失败: {}", e.getMessage());
        }
    }

    /** 从资源 URL 提取插件 ID（目录名） */
    private String extractPluginId(String url) {
        // URL 形如 .../plugins/afo-extra/meta.json 或 jar:file:.../plugins/afo-extra/meta.json
        int idx = url.lastIndexOf("/plugins/");
        if (idx < 0) return null;
        String tail = url.substring(idx + "/plugins/".length());
        int slash = tail.indexOf('/');
        if (slash < 0) return null;
        return tail.substring(0, slash);
    }

    /** 列出全部插件 */
    public List<PluginEntity> list() {
        return new ArrayList<>(plugins.values());
    }

    /** 获取单个插件元数据 */
    public PluginEntity get(String id) {
        return plugins.get(id);
    }

    /** 读取插件入口 JS 内容（供 Controller 直接返回） */
    public String readEntryJs(String id) throws IOException {
        PluginEntity p = plugins.get(id);
        String entryFile = p != null ? p.getEntryFile() : null;
        if (entryFile == null) entryFile = "entry.js";
        String content = readClasspathResource("plugins/" + id + "/" + entryFile);
        if (content == null && p != null && p.getEntryFile() != null) {
            // 回退尝试默认文件名
            content = readClasspathResource("plugins/" + id + "/entry.js");
        }
        return content;
    }

    /** 读取插件 CSS 内容 */
    public String readCss(String id) throws IOException {
        PluginEntity p = plugins.get(id);
        String cssFile = p != null ? p.getCssFile() : null;
        if (cssFile != null) {
            String content = readClasspathResource("plugins/" + id + "/" + cssFile);
            if (content != null) return content;
        }
        // 回退尝试默认文件名
        return readClasspathResource("plugins/" + id + "/style.css");
    }

    private String readClasspathResource(String path) throws IOException {
        PathMatchingResourcePatternResolver resolver = new PathMatchingResourcePatternResolver();
        Resource res = resolver.getResource("classpath:" + path);
        if (!res.exists()) return null;
        try (InputStream is = res.getInputStream()) {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = is.read(buf)) > 0) out.write(buf, 0, n);
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        }
    }
}
