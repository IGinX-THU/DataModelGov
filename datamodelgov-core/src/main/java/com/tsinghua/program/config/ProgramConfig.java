package com.tsinghua.program.config;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Data;

import java.util.List;

/**
 * 仿真程序配置（对应 program-config.json / ProgramEntity.configJson）。
 *
 * 设计目标：把"每个程序专属的知识"从 Java 代码里抽出来，变成一份可可视化编辑、
 * 可上传下载的 JSON。前后端运行时按这份配置驱动，对具体程序无感知。
 *
 * 三块职责：
 *   runtime     —— 怎么跑 MATLAB（预运行脚本、模型文件、停止时间、固定步长）
 *   parameters  —— 用户可调参数的定义（前端据此渲染表单，runner 据此写 base 变量）
 *   setupScript —— 信号采集脚本文件名（.m），由集成人员按模型结构编写并上传，
 *                   runner 在 load_system 之后 eval 它；脚本须在 base workspace 留下
 *                   dmg_cols（cell 数组，元素为信号名），runner 据此知道取哪些列。
 *   ui          —— 运行页面布局（参数表单排版、图表分组、读数项）+ 可选扩展 JS
 *
 * 信号采集、派生变量等"模型结构相关知识"全部下沉到 setupScript，本配置不认识
 * 任何块路径 / Goto 标签 / 端口号，保持通用。
 */
@Data
@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonIgnoreProperties(ignoreUnknown = true)
public class ProgramConfig {

    /** 运行时配置 */
    private RuntimeConfig runtime;

    /** 用户可调参数定义（前端动态渲染表单） */
    private List<ParameterSpec> parameters;

    /** 派生 MATLAB 变量（在 setupScript 之前 eval，用于把参数映射成模型需要的中间量） */
    private List<DerivedVar> derivedVars;

    /** 信号采集规则（可选；setupScript 为主，本字段用于文档化/probe 草稿） */
    private List<SignalSpec> signals;

    /** 信号采集脚本文件名（如 "dmg_setup.m"），仅用于文档化。
     *  实际脚本内容存在 ProgramEntity.setupScript 字段，运行时写到 taskDir/dmg_setup.m。 */
    private String setupScript;

    /** 页面模板名（引用 resources/templates/<模板名>/template.json）。
     *  运行时加载模板的 ui 配置。如果 ui 字段也有值，ui 优先（用户自定义覆盖模板）。 */
    private String template;

    /** 运行页面 UI 配置 */
    private UiConfig ui;

    // ==================== 嵌套配置类 ====================

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class RuntimeConfig {
        /** 预运行脚本名（如 "RunCtrlSysModelSHT"），在 cd(programDir) 后执行 */
        private String preRunScript;
        /** Simulink 模型文件名（如 "Dll_Control_AFO_V8_2_R2019b.slx"），默认选中项 */
        private String simulinkModel;
        /** 可选模型文件列表（下拉选），为空时回退到 simulinkModel 单项 */
        private java.util.List<String> simulinkModels;
        /** 默认停止时间（秒） */
        private double stopTime;
        /** 固定步长（可以是表达式如 "Ts"，由 base workspace 求值） */
        private String fixedStep;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class ParameterSpec {
        /** HTTP 参数名 / 前端字段 key，全程序内唯一 */
        private String key;
        /** UI 显示标签 */
        private String label;
        /** 单位（如 "rpm"、"N·m"） */
        private String unit;
        /** 值类型：number | string | select */
        private String type;
        /** 默认值（字符串形式，runner 写入 base workspace 时原样拼接） */
        private String defaultValue;
        /** 写入 MATLAB base workspace 的变量名（如 "NpReferenceRpm"） */
        private String matlabVar;
        /** 绑定的信号名：前端用该信号当前值回填输入框（可选） */
        private String bindSignal;
        /** 控件类型：input | slider | select | checkbox（默认 input） */
        private String widget;
        /** slider/select 用：最小值 */
        private Double min;
        /** slider/select 用：最大值 */
        private Double max;
        /** slider 用：步长 */
        private Double step;
        /** select 用：可选值列表 */
        private List<String> enumValues;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class UiConfig {
        /** 页面标题 */
        private String title;
        /** 布局方式：tabs | stacked */
        private String layout;
        /** 布局分区（tab 内容区：图表/控制/读数） */
        private List<Section> sections;
        /** 左侧面板列表（按从上到下顺序渲染） */
        private List<PanelSpec> leftPanels;
        /** 右侧面板列表（按从上到下顺序渲染） */
        private List<PanelSpec> rightPanels;
        /** 流程图配置（main 区域顶部静态流程图） */
        private FlowSpec flow;
        /** 可选扩展 JS（程序级，独立上传/下载） */
        private ExtensionConfig extension;
    }

    /** 面板配置（左侧/右侧 aside 里的一个个 panel） */
    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class PanelSpec {
        /** 面板类型：runtime | params | moduleTree | varTree | kpi | statusTable | alertPanel | custom */
        private String type;
        /** 面板标题 */
        private String title;
        /** moduleTree 用：模块树节点 */
        private List<ModuleNode> modules;
        /** varTree 用：变量分组（每组对应一个 tab） */
        private List<VarGroup> varGroups;
        /** kpi 用：KPI 读数项 */
        private List<ReadoutItem> kpiItems;
        /** statusTable 用：状态表行 */
        private List<StatusRow> statusRows;
        /** alertPanel 用：告警检查的信号阈值（前端据此判断告警） */
        private List<AlertRule> alertRules;
        /** custom 用：原始 HTML */
        private String html;
    }

    /** 模块树节点 */
    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class ModuleNode {
        /** 图标（emoji 或文字） */
        private String icon;
        /** 模块名 */
        private String name;
        /** 子模块名列表 */
        private List<String> children;
    }

    /** 变量分组（变量选择树的一个分组，对应一个 tab） */
    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class VarGroup {
        /** 分组名 */
        private String group;
        /** 对应的 tab 标题（用于按 tab 过滤显示） */
        private String tab;
        /** 变量列表 */
        private List<VarSpec> vars;
    }

    /** 变量定义（变量选择树的一个条目） */
    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class VarSpec {
        /** 变量标识 */
        private String name;
        /** 中文显示名 */
        private String cnName;
        /** 对应的 CSV 列名列表 */
        private List<String> csvs;
        /** 单位 */
        private String unit;
        /** 输入/输出标记：input | output（可选） */
        private String io;
    }

    /** 状态表行 */
    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class StatusRow {
        /** 图标（emoji） */
        private String icon;
        /** 系统名 */
        private String name;
        /** 关联的 CSV 信号名列表（用于判断接线状态） */
        private List<String> csvs;
        /** 说明 */
        private String desc;
    }

    /** 告警规则 */
    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class AlertRule {
        /** 信号名 */
        private String signal;
        /** 限制信号名（与 signal 比较，超过则告警） */
        private String limitSignal;
        /** 显示标签 */
        private String label;
        /** 单位 */
        private String unit;
        /** 描述 */
        private String desc;
        /** 一级告警阈值（超过则一级告警） */
        private Double threshold1;
        /** 二级告警阈值（超过则二级告警） */
        private Double threshold2;
        /** 比较方式：gt（大于）| lt（小于）| eq（等于） */
        private String compare;
    }

    /** 流程图配置 */
    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class FlowSpec {
        /** 上方流程块列表（从左到右） */
        private List<FlowBlock> topRow;
        /** 下方流程块列表（从左到右） */
        private List<FlowBlock> bottomRow;
    }

    /** 流程图块 */
    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class FlowBlock {
        /** 图标（emoji） */
        private String icon;
        /** 标签 */
        private String label;
        /** 颜色：purple | orange | cyan | blue | green | red | yellow */
        private String color;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class DerivedVar {
        /** MATLAB 变量名 */
        private String matlabVar;
        /** MATLAB 表达式（在 base workspace 求值后赋给 matlabVar） */
        private String expr;
        /** 说明（可选） */
        private String note;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class SignalSpec {
        /** 信号名（须与 setupScript 产出的 dmg_cols 列名一致） */
        private String name;
        /** 采集类型：block | goto | subsystemOut | subsystemAllOuts | sfuncExtra | auto */
        private String type;
        /** block 路径（type=block 时） */
        private String blockPath;
        /** Goto 标签（type=goto 时） */
        private String gotoTag;
        /** 子系统路径（type=subsystemOut/subsystemAllOuts 时） */
        private String subsystemPath;
        /** 输出端口索引（type=subsystemOut 时，1-based） */
        private Integer outIndex;
        /** 输出名称列表（type=subsystemOut 时，按名称取端口） */
        private List<String> outNames;
        /** S-Function 块路径 + 输出索引（type=sfuncExtra 时） */
        private String sfuncPath;
        private Integer sfuncOutIndex;
        /** 通用路径兜底（前端编辑器用单字段输入时存这里） */
        private String path;
        /** 显示名（可选，默认用 name） */
        private String label;
        /** 单位（可选） */
        private String unit;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Section {
        /** 分区 id（程序内唯一） */
        private String id;
        /** 分区标题 */
        private String title;
        /** 分区类型：control（参数表单）| charts（实时曲线）| readouts（数值/仪表读数） */
        private String type;
        /** control 用：字段排版，每个 Row 一行，fields 引用 parameters[].key */
        private List<Row> rows;
        /** charts 用：图表分组 */
        private List<ChartGroup> groups;
        /** readouts 用：读数项 */
        private List<ReadoutItem> items;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Row {
        /** 该行包含的参数 key 列表 */
        private List<String> fields;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class ChartGroup {
        /** 图表标题 */
        private String title;
        /** 该图包含的信号列表（字符串形式，简单场景用） */
        private List<String> signals;
        /** 该图包含的信号详细定义（对象形式，需要指定颜色/虚线/csv映射时用） */
        private List<SeriesSpec> series;
        /** Y 轴最小值 */
        private Double yMin;
        /** Y 轴最大值 */
        private Double yMax;
        /** 双 Y 轴：右轴最小值 */
        private Double y2Min;
        /** 双 Y 轴：右轴最大值 */
        private Double y2Max;
        /** Y 轴单位标签 */
        private String unit;
        /** Y 轴配置（旧字段，兼容用） */
        private YAxisConfig yAxis;
        /** 图表高度（px） */
        private Integer height;
    }

    /** 图表系列定义（每个信号一条线） */
    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class SeriesSpec {
        /** 显示名（图例文字） */
        private String name;
        /** 颜色（十六进制如 "#FFB84D" 或颜色名 "yellow"） */
        private String color;
        /** 是否虚线 */
        private Boolean dashed;
        /** 对应的 CSV 列名（与信号名不同时用） */
        private String csv;
        /** Y 轴位置：left（默认）| right */
        private String axis;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class YAxisConfig {
        /** 是否自动范围（默认 true） */
        private Boolean auto;
        /** 最小值 */
        private Double min;
        /** 最大值 */
        private Double max;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class ReadoutItem {
        /** 绑定的信号名 */
        private String signal;
        /** 显示标签 */
        private String label;
        /** 单位 */
        private String unit;
        /** 控件类型：value（数值）| gauge（仪表）| bar（进度条） */
        private String widget;
        /** gauge/bar 用：最小值 */
        private Double min;
        /** gauge/bar 用：最大值 */
        private Double max;
        /** 关联的参数 key（用于显示初始值） */
        private String paramKey;
        /** 初始默认值（无 paramKey 时用） */
        private String defaultValue;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class ExtensionConfig {
        /** 是否启用扩展 */
        private boolean enabled;
        /** 扩展 JS 文件名（相对程序扩展目录，如 "afo-extra.js"） */
        private String entry;
        /** 扩展 CSS 文件名（可选） */
        private String css;
        /** 模式：slot（增量，挂到指定锚点）| override（覆盖，接管整个运行区） */
        private String mode;
        /** slot 模式用：挂载锚点 after-charts | before-control | tab-extra */
        private String slot;
    }
}
