package com.tsinghua.engine;

import java.util.regex.Pattern;

/**
 * 生产机环境类失败的识别、分类与诊断。
 *
 * <p>覆盖三类"重跑无效"的失败:
 * <ol>
 *   <li>MATLAB/Simulink 内置 DLL 加载失败(Bundle#N start failed、loadlibrary);</li>
 *   <li>工作目录创建失败(路径过长、父路径只读/占用/杀软锁定);</li>
 *   <li>Excel 文件无法读写(被 Excel 占用、只读/密码保护、文件损坏、扩展名不符)。</li>
 * </ol>
 * 这些都不是模型数值发散,归为 NUMERIC_FAILED 会误导用户反复重跑;同时 MATLAB 日志里
 * readtable 的「表变量名称已修改」警告会被误当成错误定位展示,必须过滤掉。
 */
public final class MatlabErrorDiagnostics {

    private MatlabErrorDiagnostics() {}

    /** Bundle#N start failed: Loading ...\builtins\...\xxx_builtinimpl.dll failed with error: */
    private static final Pattern BUNDLE_FAIL = Pattern.compile(
            "Bundle\\s*#\\s*\\d+\\s+start\\s+failed", Pattern.CASE_INSENSITIVE);

    /** 原生模块加载失败的典型文案(中英文/Windows 错误码)。 */
    private static final Pattern NATIVE_FAIL = Pattern.compile(
            "(failed\\s+with\\s+error|failed\\s+to\\s+load|could\\s+not\\s+load|"
            + "loadlibrary|LoadLibrary|"
            + "找不到指定的模块|找不到指定的程序|不是有效的\\s*Win32|"
            + "the\\s+specified\\s+module\\s+could\\s+not\\s+be\\s+found|"
            + "%1\\s+is\\s+not\\s+a\\s+valid\\s+Win32|"
            + "0x[0-9a-fA-F]{8})", Pattern.CASE_INSENSITIVE);

    private static final Pattern MATLAB_NATIVE = Pattern.compile(
            "(nativemvm|UnsatisfiedLinkError|native\\s+library|mwl[a-z0-9_]*\\.dll)",
            Pattern.CASE_INSENSITIVE);

    /** 工作目录/文件系统权限类。 */
    private static final Pattern FS_FAIL = Pattern.compile(
            "无法创建.{0,30}目录|父路径不可写|被占用|目录路径过长|路径过长|"
            + "permission\\s+denied|access\\s+is\\s+denied|read-only\\s+file\\s+system|"
            + "磁盘权限|杀软锁定", Pattern.CASE_INSENSITIVE);

    /** Excel 读写类(MATLAB xlswrite/writetable/readtable 原生错误)。 */
    private static final Pattern EXCEL_FAIL = Pattern.compile(
            "无法写入文件|有效的电子表格文件|不受密码保护|密码保护|"
            + "password\\s+protected|工作表.{0,40}不存在|"
            + "unable\\s+to\\s+write\\s+file", Pattern.CASE_INSENSITIVE);

    /** 是否为环境类失败(而非数值/数据问题)。 */
    public static boolean isEnvironmentFailure(String message) {
        if (message == null || message.isEmpty()) return false;
        String s = message.replace('\r', ' ').replace('\n', ' ');
        if (BUNDLE_FAIL.matcher(s).find()) return true;
        if (MATLAB_NATIVE.matcher(s).find() && NATIVE_FAIL.matcher(s).find()) return true;
        if (FS_FAIL.matcher(s).find()) return true;
        if (EXCEL_FAIL.matcher(s).find()) return true;
        return false;
    }

    /** 返回具体子类,供前端给出针对性指引;非环境类返回 null。 */
    public static String category(String message) {
        if (!isEnvironmentFailure(message)) return null;
        String s = message.replace('\r', ' ').replace('\n', ' ');
        if (BUNDLE_FAIL.matcher(s).find()
                || (MATLAB_NATIVE.matcher(s).find() && NATIVE_FAIL.matcher(s).find())) {
            return "MATLAB_DLL";
        }
        if (EXCEL_FAIL.matcher(s).find()) return "EXCEL_FILE";
        if (FS_FAIL.matcher(s).find()) return "FS_PERMISSION";
        return "ENV_OTHER";
    }

    /** 环境类失败覆盖为 ENV_FAILED,其余沿用原分类。 */
    public static String classify(String message, String fallback) {
        return isEnvironmentFailure(message)
                ? EngineModels.ModelingTask.ERR_ENV
                : (fallback == null ? EngineModels.ModelingTask.ERR_NUMERIC : fallback);
    }

    /** 在错误信息末尾追加简短诊断,详细步骤由前端失败页展示。 */
    public static String decorate(String message) {
        String base = message == null ? "" : message;
        String cat = category(base);
        if (cat == null) return base;
        String hint;
        if ("MATLAB_DLL".equals(cat)) {
            hint = "MATLAB/Simulink 内置 DLL 加载失败,属本机 MATLAB 安装/依赖问题,重跑无效;请按失败页操作指引修复环境。";
        } else if ("EXCEL_FILE".equals(cat)) {
            hint = "Excel 文件被占用/只读/受密码保护或已损坏,重跑无效;请关闭 Excel 进程并检查文件读写权限后重试。";
        } else {
            hint = "工作目录创建失败(路径过长或父目录不可写/被占用),重跑无效;请把项目保存位置改到浅层短路径并检查写权限。";
        }
        return base + "\n[环境诊断] " + hint;
    }

    /** 仅用于判断日志行是否是纯粹的警告(警告本身不是失败原因)。 */
    public static boolean isWarningLine(String line) {
        if (line == null) return false;
        String t = line.trim();
        return t.startsWith("警告:")
                || t.startsWith("警告：")
                || t.startsWith("Warning:")
                || t.startsWith("Warning：")
                || t.startsWith("[警告]")
                || t.startsWith("[Warning]");
    }

    /** 警告后跟随的 MATLAB 调用栈行,例如 "&gt; In sht_xxx (line 12)"。 */
    private static boolean isStackLine(String line) {
        String t = line == null ? "" : line.trim();
        return t.startsWith("> In ") || t.startsWith(">> In ");
    }

    /**
     * 从日志尾部提取真正说明原因的行,过滤 readtable 的「表变量名称已修改」等警告
     * 及其调用栈,避免把噪声当成 MATLAB 错误定位。
     */
    public static String cleanLogTail(java.util.List<String> lines, int maxLines, int maxChars) {
        if (lines == null || lines.isEmpty()) return "";
        int start = -1;
        for (int i = lines.size() - 1; i >= 0; i--) {
            if (lines.get(i).contains("[stderr]")) { start = i; break; }
        }
        if (start < 0) return "";
        int from = Math.max(start - 1, 0);
        StringBuilder sb = new StringBuilder();
        int count = 0;
        boolean inWarning = false;
        // 从头走一遍只为维护"是否处于警告块"状态;从 from 开始收集,
        // 否则若 from 恰好落在警告的调用栈行上,会误把警告栈当成错误定位。
        for (int i = 0; i < lines.size() && count < maxLines; i++) {
            String line = lines.get(i)
                    .replace("[stderr] ", "").replace("[stdout] ", "")
                    .replace("[stderr]", "").replace("[stdout]", "");
            if (isWarningLine(line)) { inWarning = true; continue; }
            if (inWarning && isStackLine(line)) continue;
            inWarning = false;
            if (line.trim().isEmpty() || i < from) continue;
            sb.append(line).append('\n');
            count++;
        }
        String out = sb.toString().trim();
        return out.length() > maxChars ? out.substring(0, maxChars) : out;
    }
}
