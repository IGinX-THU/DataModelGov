package com.tsinghua.program.extension;

import lombok.Data;

/**
 * 前端扩展/插件元数据。
 * 插件文件（JS/CSS）存储在后端文件系统，前端通过 ID 引用。
 * 一个插件可被多个程序配置引用（通过 ProgramConfig.ui.extension.entry）。
 */
@Data
public class PluginEntity {
    /** 插件 ID（唯一，如 "afo-extra"） */
    private String id;
    /** 显示名 */
    private String name;
    /** 描述 */
    private String description;
    /** 关联的仿真程序名（方便开发者识别归属） */
    private String program;
    /** 入口 JS 文件名（固定 "entry.js"） */
    private String entryFile;
    /** 可选 CSS 文件名（固定 "style.css"） */
    private String cssFile;
    /** 版本号 */
    private String version;
    /** 作者 */
    private String author;
    /** 引用该插件的程序配置数量（由服务端统计，只读） */
    private transient int referenceCount;
}
