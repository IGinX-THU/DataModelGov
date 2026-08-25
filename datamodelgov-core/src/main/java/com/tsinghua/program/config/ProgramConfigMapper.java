package com.tsinghua.program.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * ProgramConfig 解析与校验。
 *
 * 校验规则前端一份（即时反馈）、后端一份（安全兜底）共用本类。
 * 校验失败返回非空 errors 列表，调用方据决定是否放行。
 */
@Slf4j
public final class ProgramConfigMapper {

    private static final ObjectMapper MAPPER = new ObjectMapper()
            .enable(SerializationFeature.INDENT_OUTPUT);

    private ProgramConfigMapper() {}

    public static ObjectMapper mapper() { return MAPPER; }

    /** 解析 JSON 字符串为 ProgramConfig；失败返回 null。 */
    public static ProgramConfig parse(String json) {
        if (json == null || json.trim().isEmpty()) return null;
        try {
            return MAPPER.readValue(json, ProgramConfig.class);
        } catch (Exception e) {
            log.warn("ProgramConfig 解析失败: {}", e.getMessage());
            return null;
        }
    }

    /** 序列化为 JSON 字符串。 */
    public static String stringify(ProgramConfig config) {
        try {
            return MAPPER.writeValueAsString(config);
        } catch (Exception e) {
            log.warn("ProgramConfig 序列化失败: {}", e.getMessage());
            return null;
        }
    }

    /**
     * 校验配置完整性。返回错误信息列表（空列表表示通过）。
     * strict=true 时强制要求 setupScript 和 ui；false 时允许骨架配置（自动探测草稿）。
     */
    public static List<String> validate(ProgramConfig config, boolean strict) {
        List<String> errors = new ArrayList<>();
        if (config == null) {
            errors.add("配置为空");
            return errors;
        }
        ProgramConfig.RuntimeConfig rt = config.getRuntime();
        String executionType = rt == null || isBlank(rt.getExecutionType())
                ? "simulinkRealtime" : rt.getExecutionType().trim();
        if ("simulinkRealtime".equals(executionType)) {
            validateSimulinkRealtime(config, rt, strict, errors);
        } else if ("matlabWorkflow".equals(executionType)) {
            validateMatlabWorkflow(config, rt, errors);
        } else {
            errors.add("runtime.executionType 不支持: " + executionType);
        }

        // parameters.key 唯一 + matlabVar 非空（matlabWorkflow 不要求 matlabVar）
        List<ProgramConfig.ParameterSpec> params = config.getParameters();
        if (params != null) {
            Set<String> keys = new HashSet<>();
            for (ProgramConfig.ParameterSpec p : params) {
                if (isBlank(p.getKey())) {
                    errors.add("parameter.key 必填");
                } else if (!keys.add(p.getKey())) {
                    errors.add("parameter.key 重复: " + p.getKey());
                }
                if ("simulinkRealtime".equals(executionType) && isBlank(p.getMatlabVar())) {
                    errors.add("parameter.matlabVar 必填 (key=" + p.getKey() + ")");
                }
            }
        }

        // ui.sections 引用的信号名/参数 key 须存在（仅 strict 模式校验信号名，
        // 因为非 strict 时 setupScript 还没产出 dmg_cols，无法核对）
        ProgramConfig.UiConfig ui = config.getUi();
        if (strict && ui != null && ui.getSections() != null) {
            Set<String> paramKeys = new HashSet<>();
            if (params != null) {
                for (ProgramConfig.ParameterSpec p : params) {
                    if (p.getKey() != null) paramKeys.add(p.getKey());
                }
            }
            Set<String> sectionIds = new HashSet<>();
            for (ProgramConfig.Section s : ui.getSections()) {
                if (isBlank(s.getId())) {
                    errors.add("section.id 必填");
                } else if (!sectionIds.add(s.getId())) {
                    errors.add("section.id 重复: " + s.getId());
                }
                if (isBlank(s.getType())) {
                    errors.add("section.type 必填 (id=" + s.getId() + ")");
                }
                if ("control".equals(s.getType()) && s.getRows() != null) {
                    for (ProgramConfig.Row row : s.getRows()) {
                        if (row.getFields() != null) {
                            for (String f : row.getFields()) {
                                if (!paramKeys.contains(f)) {
                                    errors.add("section.control 引用了不存在的 parameter key: " + f
                                            + " (section=" + s.getId() + ")");
                                }
                            }
                        }
                    }
                }
            }
        }

        // 扩展配置
        ProgramConfig.ExtensionConfig ext = ui == null ? null : ui.getExtension();
        if (strict && "matlabWorkflow".equals(executionType)) {
            if (ext == null || !ext.isEnabled()) {
                errors.add("matlabWorkflow 严格模式要求启用 ui.extension");
            }
            if (ext == null || isBlank(ext.getEntry())) {
                errors.add("matlabWorkflow 严格模式要求 ui.extension.entry");
            }
            if (ext == null || !"override".equals(ext.getMode())) {
                errors.add("matlabWorkflow 严格模式要求 ui.extension.mode=override");
            }
        } else if (ext != null && ext.isEnabled()) {
            if (isBlank(ext.getEntry())) {
                errors.add("ui.extension.enabled=true 时 entry 必填");
            }
            if (isBlank(ext.getMode())) {
                errors.add("ui.extension.mode 必填（slot 或 override）");
            } else if (!"slot".equals(ext.getMode()) && !"override".equals(ext.getMode())) {
                errors.add("ui.extension.mode 取值非法: " + ext.getMode() + "（应为 slot 或 override）");
            }
            if ("slot".equals(ext.getMode()) && isBlank(ext.getSlot())) {
                errors.add("slot 模式下 ui.extension.slot 必填");
            }
        }

        return errors;
    }

    private static void validateSimulinkRealtime(ProgramConfig config, ProgramConfig.RuntimeConfig rt,
                                                  boolean strict, List<String> errors) {
        if (rt == null || isBlank(rt.getSimulinkModel())) {
            errors.add("runtime.simulinkModel 必填");
        }
        if (rt != null && isBlank(rt.getPreRunScript())) {
            errors.add("runtime.preRunScript 必填");
        }
        if (strict && isBlank(config.getSetupScript())) {
            errors.add("setupScript 必填（信号采集脚本）");
        }
    }

    private static void validateMatlabWorkflow(ProgramConfig config, ProgramConfig.RuntimeConfig rt,
                                                List<String> errors) {
        if (rt == null || isBlank(rt.getWorkingDirectory())) {
            errors.add("runtime.workingDirectory 必填");
        }
        if (!isBlank(config.getSetupScript())) {
            errors.add("matlabWorkflow 不允许 setupScript");
        }
        if (rt != null && (!isBlank(rt.getSimulinkModel())
                || (rt.getSimulinkModels() != null && !rt.getSimulinkModels().isEmpty()))) {
            errors.add("matlabWorkflow 不允许 runtime.simulinkModel/simulinkModels");
        }

        ProgramConfig.WorkflowConfig workflow = config.getWorkflow();
        List<ProgramConfig.WorkflowAction> actions = workflow == null ? null : workflow.getActions();
        if (actions == null || actions.isEmpty()) {
            errors.add("workflow.actions 至少需要一项");
        } else {
            Set<String> actionKeys = new HashSet<>();
            for (ProgramConfig.WorkflowAction action : actions) {
                if (action == null || isBlank(action.getKey())) {
                    errors.add("workflow.action.key 必填");
                } else {
                    String key = action.getKey();
                    if (!key.matches("[A-Za-z][A-Za-z0-9_-]*")) {
                        errors.add("workflow.action.key 格式非法: " + key);
                    } else if (!actionKeys.add(key)) {
                        errors.add("workflow.action.key 重复: " + key);
                    }
                }
                if (action == null || isBlank(action.getEntryPoint())) {
                    errors.add("workflow.action.entryPoint 必填");
                } else if (!action.getEntryPoint().matches("[A-Za-z][A-Za-z0-9_]*")) {
                    errors.add("workflow.action.entryPoint 不是合法 MATLAB 标识符: " + action.getEntryPoint());
                }
            }
        }

        if (workflow != null && workflow.getRequiredFiles() != null) {
            for (String file : workflow.getRequiredFiles()) {
                String normalized = file == null ? "" : file.replace('\\', '/');
                if (isBlank(file) || normalized.startsWith("/") || normalized.matches("^[A-Za-z]:/.*")
                        || normalized.equals("..") || normalized.startsWith("../") || normalized.contains("/../")) {
                    errors.add("workflow.requiredFiles 必须是安全的相对路径: " + file);
                }
            }
        }

        List<ProgramConfig.DatasetSpec> datasets = workflow == null ? null : workflow.getDatasets();
        if (datasets != null) {
            Set<String> datasetKeys = new HashSet<>();
            for (ProgramConfig.DatasetSpec dataset : datasets) {
                if (dataset == null || isBlank(dataset.getKey())) {
                    errors.add("workflow.dataset.key 必填");
                } else if (!datasetKeys.add(dataset.getKey())) {
                    errors.add("workflow.dataset.key 重复: " + dataset.getKey());
                }
                if (dataset != null && dataset.getRequiredColumns() != null) {
                    Set<String> columns = new HashSet<>();
                    for (String column : dataset.getRequiredColumns()) {
                        if (isBlank(column)) errors.add("workflow.dataset.requiredColumns 不允许空值");
                        else if (!columns.add(column)) errors.add("workflow.dataset.requiredColumns 重复: " + column);
                    }
                }
            }
        }

    }

    private static boolean isBlank(String s) { return s == null || s.trim().isEmpty(); }
}
