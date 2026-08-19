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
        if (rt == null || isBlank(rt.getSimulinkModel())) {
            errors.add("runtime.simulinkModel 必填");
        }
        if (rt != null && isBlank(rt.getPreRunScript())) {
            errors.add("runtime.preRunScript 必填");
        }
        if (strict && isBlank(config.getSetupScript())) {
            errors.add("setupScript 必填（信号采集脚本）");
        }

        // parameters.key 唯一 + matlabVar 非空
        List<ProgramConfig.ParameterSpec> params = config.getParameters();
        if (params != null) {
            Set<String> keys = new HashSet<>();
            for (ProgramConfig.ParameterSpec p : params) {
                if (isBlank(p.getKey())) {
                    errors.add("parameter.key 必填");
                } else if (!keys.add(p.getKey())) {
                    errors.add("parameter.key 重复: " + p.getKey());
                }
                if (isBlank(p.getMatlabVar())) {
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
        if (ui != null && ui.getExtension() != null && ui.getExtension().isEnabled()) {
            ProgramConfig.ExtensionConfig ext = ui.getExtension();
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

    private static boolean isBlank(String s) { return s == null || s.trim().isEmpty(); }
}
