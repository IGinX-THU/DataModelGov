package com.tsinghua.util;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * UQ 失败诊断。
 *
 * <p>MATLAB 侧 UQ 失败时只会抛一串断言文本(如「确定性结果不能用于当前UQ回放：稳态点失败：…」)，
 * 任务记录里看不出失败发生在哪个阶段、哪个物理量超限、越界工况的转速/负载是多少。
 * 生产环境往往不允许登录服务器翻日志，只能靠 status 接口。
 *
 * <p>本类把 MATLAB 日志还原成结构化诊断，供 uqMessage 与 uqResult.diagnostics 使用：
 * 阶段判定、气热平衡收敛四项(ret/tag/valid/残差)、热参考间隙表越界工况、候选统计、关键错误行。
 * 只解析日志，不改变任何 MATLAB 行为。
 *
 * <p>注意：日志中的中文可能残留乱码(JAVA 侧无法还原 MATLAB 已丢弃的字节)，
 * 因此所有识别逻辑都优先锚定 ASCII 结构(变量名、数字、单位)，中文只用于分词提示。
 */
public final class UqDiagnostics {

    private UqDiagnostics() {
    }

    /** 气热平衡判定的四项指标：ret / convergeTag / evaluationValid / maxErr。 */
    private static final Pattern PHYSICAL = Pattern.compile(
            "ret\\s*=\\s*([-\\d.]+)[^\\d-]{0,8}tag\\s*=\\s*([-\\d.]+)[^\\d-]{0,8}valid\\s*=\\s*([-\\d.]+)"
                    + "[^\\d-]{0,24}?([-+]?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)\\s*[。.]?\\s*$");

    /** 二维越界：边界投影/最近点括号内以 rpm/W 成对给出。 */
    private static final Pattern BOUNDARY_2D = Pattern.compile(
            "\\[\\s*([-+]?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)\\s*rpm\\s*[,，]\\s*"
                    + "([-+]?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)\\s*W\\s*\\]");

    /** 候选求值进度：`…完整求值8组，平均12.34s/组，当前有效0。` */
    private static final Pattern CANDIDATES = Pattern.compile(
            "(\\d+)\\s*[^\\d]{0,6}?\\s*[,，]\\s*[^\\d]{0,10}?([\\d.]+)\\s*s\\s*/\\s*[^\\d]{0,6}?"
                    + "\\s*[,，]\\s*[^\\d]{0,6}?(\\d+)\\s*[。.]?\\s*$");

    /** UQ 合同抬头按 `/` 分段取维数，避免多组数字互相吞并。 */
    private static final Pattern CONTRACT_HEAD = Pattern.compile(
            "([\\d\\s\\S]*?)/([\\d\\s\\S]*?)/([\\d\\s\\S]*)");

    private static final String[] NUM_RPM = {"rpm"};
    private static final Pattern ANY_NUMBER = Pattern.compile("[-+]?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?");

    /** 判定「这条日志值得进诊断」的关键词(含常见乱码形态)。 */
    private static final String[] ERROR_HINTS = {
            "失败", "错误", "越界", "不收敛", "残差", "超出",
            "error", "Error", "ERROR", "failed", "Failed", "FAILED",
            "warning", "Warning", "WARNING", "assert", "Assertion",
            // GTESS 物理库加载/thunk 桥接生成失败(生产机环境类),版本号无关,按 ASCII 锚定
            "thunk", "loadlibrary", "LoadLibrary", "loadLibrary", "mex", "MEX",
            "compiler", "Compiler", "SDK", "未找到编译器", "无法生成"
    };

    /** 明确属于「物理回放没通过」的错误标识。 */
    private static final String[] PHYSICAL_HINTS = {
            "ThermalEquilibrium", "气热平衡", "dllEvaluationFailed",
            "TC27:UQ:Point", "稳态点失败", "TC27:Replay:"
    };

    /** 明确属于「GTESS 物理库加载 / thunk 桥接生成」阶段的环境类失败。 */
    private static final String[] LOADLIB_HINTS = {
            "thunk", "loadlibrary", "LoadLibrary", "loadLibrary",
            "mex", "No supported compiler", "mex -setup", "SDK",
            "生成GTESS", "物理库", "桥接", "找不到指定的模块", "加载库"
    };

    /** loadlib 子类A:DLL 或其依赖运行库缺失(装了 VS 也无用)——Windows ERROR_MOD_NOT_FOUND。 */
    private static final String[] DLL_DEPENDENCY_HINTS = {
            "找不到指定的模块", "找不到指定的文件", "加载库", "找不到依赖项",
            "126", "specified module could not be found", "VCRUNTIME140",
            "api-ms-win-crt", "MSVCP", "dependent dll"
    };

    /** loadlib 子类B:thunk 桥接生成本身失败(需要 mex C 编译器/头文件/可写目录)。
     *  仅用强锚点,不用裸 "compiler"/"SDK" 这类会在无关日志里误命中的宽泛词。 */
    private static final String[] COMPILER_HINTS = {
            "No supported compiler", "mex -setup", "未找到编译器", "无法生成thunk",
            "生成thunk失败", "fatal error", "未找到支持的编译器"
    };

    /**
     * 解析一次 UQ 运行的日志。
     *
     * @param kind   任务类型(steady / steady_update / flight_steady …)
     * @param method 评估方法(C/D)
     * @param log    该任务的完整日志缓冲(可为 null)
     */
    public static Map<String, Object> analyze(String kind, String method, List<String> log) {
        List<String> lines = log == null ? Collections.emptyList() : log;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kind", kind == null ? "" : kind);
        out.put("method", method == null ? "" : method);

        List<Map<String, Object>> outOfRange = new ArrayList<>();
        List<String> keyErrors = new ArrayList<>();
        List<String> samples = new ArrayList<>();
        Map<String, Object> physical = null;
        Map<String, Object> candidates = null;
        Map<String, Object> contract = null;
        String stage = "未识别阶段";
        boolean loadlibFailure = false;
        boolean dllDependencyMissing = false;
        boolean compilerMissing = false;

        for (int i = 0; i < lines.size(); i++) {
            String raw = lines.get(i);
            if (raw == null || raw.isEmpty()) {
                continue;
            }
            String line = MojibakeUtil.repair(raw);
            // 已被结构化字段消费的行不再重复进 keyErrors，避免摘要是同一条信息的复读
            boolean consumed = false;

            // 1) 气热平衡四项
            if (physical == null) {
                Matcher m = PHYSICAL.matcher(line.trim());
                if (m.find()) {
                    physical = new LinkedHashMap<>();
                    physical.put("ret", num(m.group(1)));
                    physical.put("convergeTag", num(m.group(2)));
                    physical.put("evaluationValid", num(m.group(3)));
                    physical.put("residual", num(m.group(4)));
                    physical.put("line", line.trim());
                    consumed = true;
                }
            }

            // 2) 热参考间隙表越界(每部件首次提示一次，含查询坐标与回退坐标)
            if (line.contains("rpm")) {
                Map<String, Object> item = parseOutOfRange(line);
                if (item != null) {
                    boolean dup = false;
                    for (Map<String, Object> e : outOfRange) {
                        if (String.valueOf(e.get("line")).equals(String.valueOf(item.get("line")))) {
                            dup = true;
                            break;
                        }
                    }
                    if (!dup) {
                        outOfRange.add(item);
                    }
                    consumed = true;
                }
            }

            // 3) 候选统计 / 合同抬头
            if (candidates == null && line.contains("s/")) {
                Matcher m = CANDIDATES.matcher(line.trim());
                if (m.find()) {
                    candidates = new LinkedHashMap<>();
                    candidates.put("groups", num(m.group(1)));
                    candidates.put("avgSeconds", num(m.group(2)));
                    candidates.put("validGroups", num(m.group(3)));
                    consumed = true;
                }
            }
            if (contract == null && line.contains("UQ") && countChar(line, '/') >= 2) {
                contract = parseContract(line.trim());
                if (contract != null) {
                    consumed = true;
                }
            }

            // 4) 阶段判定
            if ("未识别阶段".equals(stage)) {
                // GTESS 物理库/thunk 桥接失败优先判定：它发生在基准回放之前，属环境类失败
                if (containsHint(line, LOADLIB_HINTS)) {
                    stage = "UQ基准回放(GTESS物理库加载/thunk桥接生成)";
                    loadlibFailure = true;
                } else if (line.contains("sht_tc27_uq_covariance") || line.contains("不能用于当前UQ回放")
                        || line.contains("基准")) {
                    stage = "UQ基准回放(确定性估计值复算)";
                } else if (line.contains("Start_TC27_UQ") || line.contains("Start_FlightModelAdapt_15")) {
                    stage = "UQ程序入口(preflight与合同核对)";
                } else if (line.contains("sht_tc27_uq_evaluator") || line.contains("候选")) {
                    stage = "UQ候选评估(参数扰动回放)";
                }
            } else if (containsHint(line, LOADLIB_HINTS)) {
                // 阶段已被其它行命中，但同一日志里出现库加载失败也是明确信号
                loadlibFailure = true;
            }
            // loadlib 子类:区分「DLL依赖缺失」与「mex编译器/头文件缺失」——修复方向完全不同。
            // 仅在这行本身已是 loadlib 信号时归类,避免普通日志里的偶然词误判子类。
            if (loadlibFailure || containsHint(line, LOADLIB_HINTS)) {
                if (containsHint(line, DLL_DEPENDENCY_HINTS)) dllDependencyMissing = true;
                if (containsHint(line, COMPILER_HINTS)) compilerMissing = true;
            }

            // 5) 关键错误行
            if (!consumed && containsHint(line, ERROR_HINTS) && keyErrors.size() < 10) {
                String t = compact(line);
                if (!keyErrors.contains(t)) {
                    keyErrors.add(t);
                }
            }

            // 6) 原始样例(带上游上下文，便于人工核对；结构化行也保留，摘要外仍有原文可查)
            if (samples.size() < 40 && containsHint(line, ERROR_HINTS)) {
                samples.add(compact(line));
            }
        }

        if (loadlibFailure && "UQ基准回放(GTESS物理库加载/thunk桥接生成)".equals(stage)) {
            stage = dllDependencyMissing ? "UQ基准回放(GTESS.dll加载失败:DLL/运行库依赖缺失)"
                    : "UQ基准回放(GTESS thunk桥接生成失败:编译器/头文件/目录)";
        }
        if (physical != null && "未识别阶段".equals(stage)) {
            stage = "UQ基准回放(确定性估计值复算)";
        }
        if (physical != null && outOfRange.isEmpty()) {
            stage = stage + "；未见热参考间隙表越界提示";
        }

        out.put("stage", stage);
        out.put("physicalFailure", physical);
        out.put("outOfRange", outOfRange);
        out.put("candidateStats", candidates);
        out.put("contract", contract);
        out.put("keyErrors", keyErrors);
        out.put("samples", samples);
        // loadlib 子类:DLL/运行库缺失是最具体根因,优先于编译器缺失(用户装了VS还失败多属此类)
        if (loadlibFailure) {
            out.put("loadlibSubclass", dllDependencyMissing ? "dll_missing"
                    : (compilerMissing ? "compiler" : "unknown"));
        }
        out.put("failureClass", classify(physical, outOfRange, keyErrors, loadlibFailure));
        out.put("suggestions", suggestions(out, physical, outOfRange, keyErrors));
        return out;
    }

    /** 一句话结论：失败主因归类。 */
    public static String headline(Map<String, Object> diag) {
        String cls = String.valueOf(diag.get("failureClass"));
        switch (cls) {
            case "physical":
                return "稳态点物理回放未通过(DLL气热平衡未收敛)";
            case "out_of_range":
                return "稳态工况超出热参考间隙表覆盖域";
            case "input":
                return "输入合同不满足(缺少/不匹配输入文件)";
            case "cache":
                return "物理回放缓存与当前执行包不一致";
            case "loadlib":
                if ("dll_missing".equals(diag.get("loadlibSubclass"))) {
                    return "GTESS.dll 加载失败(找不到指定的模块=DLL或其依赖运行库缺失,并非缺编译器;"
                            + "装了VS仍会失败,需补 VC++ Redistributable x64 与 Win7 的 UCRT/KB2999226)";
                }
                return "GTESS物理库/thunk桥接生成失败(需 mex C 编译器/头文件齐全/目录可写)";
            default:
                return "UQ程序返回失败";
        }
    }

    /** 生成写进 uqMessage 的中文摘要(控制长度，关键信息优先)。 */
    public static String summaryText(Map<String, Object> diag) {
        StringBuilder sb = new StringBuilder();
        sb.append("UQ评估失败：").append(headline(diag));
        sb.append("\n- 失败阶段：").append(diag.get("stage"));

        Map<String, Object> physical = asMap(diag.get("physicalFailure"));
        if (physical != null) {
            String detail = "ret=" + intOf(physical.get("ret")) + "，tag=" + intOf(physical.get("convergeTag"))
                    + "，valid=" + intOf(physical.get("evaluationValid"))
                    + "，DLL残差=" + sci(physical.get("residual"));
            sb.append("\n- 气热平衡：").append(detail);
            sb.append("(判定要求 ret=0、tag=0、valid=1、残差≤").append("1e-05");
            double r = asDouble(physical.get("residual"), Double.NaN);
            if (!Double.isNaN(r) && r > 0) {
                sb.append("，当前超限 ").append(ratio(r, 1e-5)).append(" 倍");
            }
            sb.append(")");
        }

        List<Map<String, Object>> oor = asList(diag.get("outOfRange"));
        if (oor != null && !oor.isEmpty()) {
            sb.append("\n- 热参考间隙表越界 ").append(oor.size()).append(" 处：");
            int shown = 0;
            for (Map<String, Object> e : oor) {
                if (shown++ >= 3) {
                    sb.append("；…");
                    break;
                }
                sb.append("\n  · ").append(e.get("component")).append(" ");
                if (e.get("queryPowerW") != null) {
                    sb.append("Np=").append(fmt(e.get("querySpeedRpm"))).append(" rpm / 负载=")
                            .append(fmt(e.get("queryPowerW"))).append(" W → 回退到 [")
                            .append(fmt(e.get("boundarySpeedRpm"))).append(" rpm, ")
                            .append(fmt(e.get("boundaryPowerW"))).append(" W]");
                } else {
                    sb.append("Ng=").append(fmt(e.get("querySpeedRpm"))).append(" rpm → 最近表点 ")
                            .append(fmt(e.get("nearestSpeedRpm"))).append(" rpm");
                }
            }
        }

        List<Map<String, Object>> sus = asList(diag.get("suspectedPoints"));
        if (sus != null && !sus.isEmpty()) {
            sb.append("\n- 疑似对应稳态点(").append("由越界坐标在本次稳态均值表内匹配)：");
            for (int i = 0; i < sus.size() && i < 3; i++) {
                Map<String, Object> e = sus.get(i);
                if (i > 0) {
                    sb.append("；");
                }
                sb.append(e.get("pointId")).append("(Np=").append(fmt(e.get("np")))
                        .append(", Ng=").append(fmt(e.get("ng"))).append(")");
            }
        }

        Map<String, Object> cand = asMap(diag.get("candidateStats"));
        if (cand != null) {
            sb.append("\n- 候选评估：已完整求值 ").append(intOf(cand.get("groups"))).append(" 组，平均 ")
                    .append(cand.get("avgSeconds")).append(" s/组，有效 ")
                    .append(intOf(cand.get("validGroups"))).append(" 组");
        }

        Map<String, Object> contract = asMap(diag.get("contract"));
        if (contract != null) {
            sb.append("\n- 回放规模：").append(intOf(contract.get("parameterDims"))).append(" 维主参数 / ")
                    .append(intOf(contract.get("steadyPoints"))).append(" 个稳态点 / ")
                    .append(intOf(contract.get("historySegments"))).append(" 段历程 / ")
                    .append(intOf(contract.get("residualDims"))).append(" 维残差");
        }

        List<String> sug = asStrList(diag.get("suggestions"));
        if (sug != null && !sug.isEmpty()) {
            sb.append("\n- 处理建议：");
            for (int i = 0; i < sug.size() && i < 3; i++) {
                sb.append("\n  ").append(i + 1).append(") ").append(sug.get(i));
            }
        }

        Object report = diag.get("reportFile");
        if (report != null && !String.valueOf(report).isEmpty()) {
            sb.append("\n- 诊断报告：").append(report);
        }
        String text = sb.toString();
        return text.length() > 1800 ? text.substring(0, 1800) + "…" : text;
    }

    /** 把诊断与完整日志落到任务目录，便于事后追溯(不影响评估结论)。 */
    public static File writeReport(File dir, String prefix, Map<String, Object> diag, List<String> log)
            throws IOException {
        if (dir == null) {
            return null;
        }
        if (!dir.exists() && !dir.mkdirs()) {
            return null;
        }
        File f = new File(dir, prefix + "-uq-diagnostics.txt");
        StringBuilder sb = new StringBuilder();
        sb.append("UQ 失败诊断报告\n");
        sb.append("生成时间: ").append(new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new java.util.Date())).append('\n');
        sb.append("任务类型: ").append(diag.get("kind")).append("  方法: ").append(diag.get("method")).append('\n');
        sb.append("失败归类: ").append(diag.get("failureClass")).append('\n');
        sb.append("失败阶段: ").append(diag.get("stage")).append('\n');
        sb.append("\n===== 摘要 =====\n").append(summaryText(diag)).append('\n');

        Map<String, Object> physical = asMap(diag.get("physicalFailure"));
        if (physical != null) {
            sb.append("\n===== 气热平衡判定 =====\n").append(physical.get("line")).append('\n');
            sb.append("判定要求: ret=0, convergeTag=0, evaluationValid=1, maxErr<=1e-05\n");
        }
        List<Map<String, Object>> oor = asList(diag.get("outOfRange"));
        if (oor != null && !oor.isEmpty()) {
            sb.append("\n===== 热参考间隙表越界 =====\n");
            for (Map<String, Object> e : oor) {
                sb.append(e.get("line")).append('\n');
            }
        }
        List<Map<String, Object>> sus = asList(diag.get("suspectedPoints"));
        if (sus != null && !sus.isEmpty()) {
            sb.append("\n===== 疑似对应稳态点(启发式匹配，仅供定位) =====\n");
            for (Map<String, Object> e : sus) {
                sb.append(e.get("pointId")).append("  Np=").append(e.get("np"))
                        .append("  Ng=").append(e.get("ng"))
                        .append("  命中越界条数=").append(e.get("matchScore"))
                        .append("  相对误差=").append(e.get("relativeError")).append('\n');
            }
        }
        List<String> errs = asStrList(diag.get("keyErrors"));        if (errs != null && !errs.isEmpty()) {
            sb.append("\n===== 关键错误行 =====\n");
            for (String s : errs) {
                sb.append(s).append('\n');
            }
        }
        sb.append("\n===== 完整日志(").append(log == null ? 0 : log.size()).append(" 行) =====\n");
        if (log != null) {
            for (String l : log) {
                sb.append(MojibakeUtil.repair(l)).append('\n');
            }
        }
        Files.write(f.toPath(), sb.toString().getBytes(StandardCharsets.UTF_8));
        return f;
    }

    // ------------------------------------------------------------------ 解析辅助

    private static Map<String, Object> parseOutOfRange(String line) {
        String trimmed = line.trim();
        String component = componentOf(trimmed);
        if (component == null) {
            return null;
        }
        Map<String, Object> item = new LinkedHashMap<>();
        item.put("component", component);
        item.put("line", compact(trimmed));

        Matcher b2 = BOUNDARY_2D.matcher(trimmed);
        int boundaryAt = -1;
        if (b2.find()) {
            boundaryAt = b2.start();
            item.put("boundarySpeedRpm", num(b2.group(1)));
            item.put("boundaryPowerW", num(b2.group(2)));
        }
        Double querySpeed = firstAfter(trimmed, "Np=");
        Double queryPower = firstPowerBefore(trimmed, boundaryAt < 0 ? trimmed.length() : boundaryAt);
        if (querySpeed != null) {
            item.put("querySpeedRpm", querySpeed);
        }
        if (queryPower != null) {
            item.put("queryPowerW", queryPower);
        }

        if (item.get("querySpeedRpm") == null) {
            Double ng = firstAfter(trimmed, "Ng=");
            if (ng != null) {
                item.put("querySpeedRpm", ng);
            }
        }

        if (item.get("queryPowerW") != null) {
            // 二维：需要查询坐标 + 回退坐标齐备，否则视为无法识别
            if (item.get("querySpeedRpm") == null || item.get("boundarySpeedRpm") == null) {
                return null;
            }
            item.put("mode", "2d");
            return item;
        }

        // 一维：`Ng=<query> rpm；采用最近表点 <nearest> rpm 的热参考间隙 <gap>。`
        List<Double> rpms = numbersWithUnit(trimmed, NUM_RPM[0]);
        if (item.get("querySpeedRpm") == null && !rpms.isEmpty()) {
            item.put("querySpeedRpm", rpms.get(0));
        }
        if (rpms.size() >= 2) {
            item.put("nearestSpeedRpm", rpms.get(1));
        }
        Double gap = lastPlainNumber(trimmed);
        if (gap != null) {
            item.put("thermalGap", gap);
        }
        if (item.get("querySpeedRpm") == null || item.get("nearestSpeedRpm") == null) {
            return null;
        }
        item.put("mode", "1d");
        return item;
    }

    /**
     * 抬头 `…14维主参数…，10维附加参数，18个稳态点/0段完整小幅历程/162维残差。`
     * 按 `/` 分三段取数：第一段末位是稳态点数，第二段是历程段数，第三段是残差维数。
     */
    private static Map<String, Object> parseContract(String line) {
        int a = line.indexOf('/');
        int b = a < 0 ? -1 : line.indexOf('/', a + 1);
        if (a < 0 || b < 0) {
            return null;
        }
        List<Double> head = allNumbers(line.substring(0, a));
        if (head.isEmpty()) {
            return null;
        }
        // 抬头形如 `TC27-UQ: 14维主参数…`，前缀里的型号数字(27)必须剔除，否则维数整体错位
        int colon = line.lastIndexOf(':', a);
        if (colon >= 0) {
            head = allNumbers(line.substring(colon + 1, a));
            if (head.isEmpty()) {
                return null;
            }
        }
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("parameterDims", head.get(0));
        if (head.size() >= 2) {
            m.put("nuisanceDims", head.get(1));
        }
        m.put("steadyPoints", head.get(head.size() - 1));
        List<Double> seg1 = allNumbers(line.substring(a + 1, b));
        if (!seg1.isEmpty()) {
            m.put("historySegments", seg1.get(0));
        }
        List<Double> seg2 = allNumbers(line.substring(b + 1));
        if (!seg2.isEmpty()) {
            m.put("residualDims", seg2.get(0));
        }
        return m;
    }

    private static List<Double> allNumbers(String s) {
        List<Double> vals = new ArrayList<>();
        Matcher m = ANY_NUMBER.matcher(s);
        while (m.find()) {
            Double d = num(m.group());
            if (d != null) {
                vals.add(d);
            }
        }
        return vals;
    }

    private static int countChar(String s, char c) {
        int n = 0;
        for (int i = 0; i < s.length(); i++) {
            if (s.charAt(i) == c) {
                n++;
            }
        }
        return n;
    }

    private static String componentOf(String line) {        for (String c : new String[]{"PT", "HPC", "GT"}) {
            int i = line.indexOf(c);
            if (i >= 0 && i < 24) {
                // 必须是独立词：前后不是字母数字
                boolean leftOk = i == 0 || !Character.isLetterOrDigit(line.charAt(i - 1));
                boolean rightOk = i + c.length() >= line.length()
                        || !Character.isLetterOrDigit(line.charAt(i + c.length()));
                if (leftOk && rightOk) {
                    return c;
                }
            }
        }
        return null;
    }

    private static Double firstAfter(String s, String anchor) {
        int i = s.indexOf(anchor);
        if (i < 0) {
            return null;
        }
        Matcher m = ANY_NUMBER.matcher(s.substring(i + anchor.length()));
        return m.find() ? num(m.group()) : null;
    }

    private static Double firstPowerBefore(String s, int end) {
        Matcher m = Pattern.compile("([-+]?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)\\s*W").matcher(s);
        while (m.find()) {
            if (m.start() >= end) {
                break;
            }
            return num(m.group(1));
        }
        return null;
    }

    private static List<Double> numbersWithUnit(String s, String unit) {
        List<Double> vals = new ArrayList<>();
        Matcher m = Pattern.compile("([-+]?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)\\s*" + unit).matcher(s);
        while (m.find()) {
            vals.add(num(m.group(1)));
        }
        return vals;
    }

    private static Double lastPlainNumber(String s) {
        String t = s.replaceAll("[。.]\\s*$", "").trim();
        Matcher m = Pattern.compile("([-+]?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)\\s*[。.]?\\s*$").matcher(t);
        return m.find() ? num(m.group(1)) : null;
    }

    // ------------------------------------------------------------------ 归类

    private static String classify(Map<String, Object> physical, List<Map<String, Object>> oor,
                                   List<String> errors, boolean loadlibFailure) {
        String joined = String.join(" ", errors);
        // 库加载/thunk 生成失败必须先于 physical 判定：库都没加载成功不可能进入气热平衡回放
        if (loadlibFailure || joined.contains("thunk") || joined.contains("loadlibrary")
                || joined.contains("LoadLibrary") || joined.contains("mex")
                || joined.contains("No supported compiler") || joined.contains("生成GTESS")
                || joined.contains("物理库")) {
            return "loadlib";
        }
        if (joined.contains("CacheExecution") || joined.contains("缓存与实际执行包不一致")) {
            return "cache";
        }
        if (joined.contains("缺少") || joined.contains("不存在") || joined.contains("StalePreprocessing")
                || joined.contains("身份不一致")) {
            return "input";
        }
        if (physical != null) {
            return "physical";
        }
        if (oor != null && !oor.isEmpty()) {
            return "out_of_range";
        }
        return "unknown";
    }

    private static List<String> suggestions(Map<String, Object> diag, Map<String, Object> physical,
                                            List<Map<String, Object>> oor, List<String> errors) {
        List<String> out = new ArrayList<>();
        String cls = String.valueOf(diag.get("failureClass"));
        if ("input".equals(cls)) {
            out.add("核对本次评估绑定的模型交付Excel、身份JSON与训练数据是否与当前任务一致；换过数据需重新执行准备与建模");
        }
        if (oor != null && !oor.isEmpty()) {
            out.add("越界工况的转速/负载已超出 epsilon_ss 热参考间隙表覆盖域：剔除或替换该稳态窗口后重新准备数据、重新登记模型成果，再发起评估");
        }
        if (physical != null) {
            out.add("该稳态点的 DLL 共同工作未收敛，属物理求解层面的失败：若窗口数据必须保留，需扩展热参考间隙表覆盖域(需改MATLAB资源，超出当前约束)");
        }
        if ("cache".equals(cls)) {
            out.add("清理该任务输出目录下的 uq_replay_* 物理回放缓存后重新发起评估");
        }
        if ("loadlib".equals(cls)) {
            if ("dll_missing".equals(diag.get("loadlibSubclass"))) {
                // 根因是 GTESS.dll 的运行时依赖,不是编译器——用户装了 VS 仍失败正属此类。
                out.add("【装了VS仍报此错的原因】GTESS.dll(x64)依赖 VCRUNTIME140.dll 与 api-ms-win-crt-*.dll(UCRT),"
                        + "这些是运行时库(Redistributable),和 Visual Studio 的编译工具链是两回事;装VS不代表装了它们");
                out.add("修复1:安装 Visual C++ 2015-2022 Redistributable 的 x64 版(vc_redist.x64.exe),"
                        + "注意必须 x64——装成 x86 版仍会报『找不到指定的模块』");
                out.add("修复2:Win7 原生没有 UCRT,须安装 KB2999226(Windows Update)补齐 api-ms-win-crt-*.dll;"
                        + "Win7 SP1 且未打此补丁是最常见根因");
                out.add("验证:在生产机 MATLAB 执行 "
                        + "[~,o]=loadlibrary('GTESS.dll','GTESS.h'); 若仍报『找不到指定的模块』,用 Dependencies/depends.exe "
                        + "打开 GTESS.dll 看哪个依赖标红,补装对应运行库即可;本机正常说明交付DLL本身无误");
            } else {
                out.add("这是生产机环境问题而非模型问题(本机正常可佐证):在该机 MATLAB 命令行执行 mex -setup C,"
                        + "确认已配置可用的 C 编译器(MinGW-w64 或受支持的 Visual Studio),再重跑评估");
                out.add("核对程序目录 GTESS.dll 与 GTESS.h、blockAndFunctions.h、types_TMATS.H、"
                        + "matlab_loadlibrary_include/stdio.h 齐全且可读,程序目录非只读;本机可正常生成 thunk 说明交付包本身无误");
            }
        }
        if (out.isEmpty()) {
            out.add("查看诊断报告中的完整日志，确认是输入合同、物理求解还是输出扫描问题");
        }
        out.add("UQ 结果与确定性模型结果相互独立：本次失败不影响已交付的确定性模型");
        return out;
    }

    // ------------------------------------------------------------------ 杂项

    private static boolean containsHint(String line, String[] hints) {
        for (String h : hints) {
            if (line.contains(h)) {
                return true;
            }
        }
        return false;
    }

    private static String compact(String line) {
        String t = line.replaceAll("\\s+", " ").trim();
        return t.length() > 400 ? t.substring(0, 400) + "…" : t;
    }

    private static Double num(String s) {
        try {
            return Double.valueOf(s.trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static double asDouble(Object o, double dft) {
        if (o instanceof Number) {
            return ((Number) o).doubleValue();
        }
        try {
            return Double.parseDouble(String.valueOf(o));
        } catch (Exception e) {
            return dft;
        }
    }

    private static String fmt(Object o) {
        double d = asDouble(o, Double.NaN);
        if (Double.isNaN(d)) {
            return String.valueOf(o);
        }
        if (Math.abs(d - Math.rint(d)) < 1e-9) {
            return String.valueOf((long) Math.rint(d));
        }
        if (Math.abs(d) >= 1000) {
            return String.format("%.2f", d);
        }
        return String.format("%.4g", d);
    }

    /** 计数量(组数/维数/点数)统一按整数显示，避免出现 `8.0 组`。 */
    private static String intOf(Object o) {
        return fmt(o);
    }

    private static String sci(Object o) {
        double d = asDouble(o, Double.NaN);
        return Double.isNaN(d) ? String.valueOf(o) : String.format("%.3e", d);
    }

    private static String ratio(double v, double limit) {
        double r = v / limit;
        if (r >= 1e5) {
            return String.format("%.0f", r);
        }
        if (r >= 100) {
            return String.format("%.0f", r);
        }
        return String.format("%.1f", r);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object o) {
        return o instanceof Map ? (Map<String, Object>) o : null;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> asList(Object o) {
        return o instanceof List ? (List<Map<String, Object>>) o : null;
    }

    @SuppressWarnings("unchecked")
    private static List<String> asStrList(Object o) {
        return o instanceof List ? (List<String>) o : null;
    }

    /** 便于单元自测：把一组日志直接跑一遍。 */
    public static void main(String[] args) throws Exception {
        List<String> log = new ArrayList<>();
        log.add("TC27-UQ: 14维主参数(包括Wf_bias)，10维附加参数，18个稳态点/0段完整小幅历程/162维残差。");
        log.add("[警告] PT epsilon_ss查询超出二维覆盖域：修正Np=20896.2973825037 rpm，负载=2177967.57221873 W；"
                + "连续投影到边界[20900 rpm, 2176600 W]，热参考间隙0.0012。 PT 后续连续越界点不再重复提示。");
        log.add("[警告] HPC epsilon_ss 查询超出一维线性插值域：进口基准修正 Ng=21327.4989996535 rpm；"
                + "采用最近表点 21339.479273898 rpm 的热参考间隙 0.0008。 HPC 后续连续越界点不再重复提示。");
        log.add("TC27-UQ当前进程候选完整求值8组，平均12.34s/组，当前有效0。");
        log.add("错误使用 sht_tc27_uq_covariance (line 12)");
        log.add("确定性结果不能用于当前UQ回放：稳态点失败：气热平衡物理求值失败：ret=0，tag=1，valid=0，"
                + "DLL残差=4.694e-01。");
        Map<String, Object> d = analyze("steady_update", "D", log);
        SetPrinter.print(d);
        System.out.println("\n---- summary ----\n" + summaryText(d));

        System.out.println("\n===== 用例2: Win7 生产机缺 mex 编译器导致 thunk 生成失败 =====");
        List<String> log2 = new ArrayList<>();
        log2.add("正在加载 GTESS.dll 公共接口,生成 thunk 桥接库...");
        log2.add("错误使用 loadlibrary (line 1234)");
        log2.add("No supported compiler or SDK was found. You can install the MinGW-w64 compiler");
        log2.add("生成 GTESS.thunk 失败,失败阶段: UQ基准回放(确定性估计值复算)。");
        Map<String, Object> d2 = analyze("steady", "D", log2);
        System.out.println("failureClass = " + d2.get("failureClass"));
        System.out.println("subclass = " + d2.get("loadlibSubclass"));
        System.out.println("stage = " + d2.get("stage"));
        System.out.println("---- summary ----\n" + summaryText(d2));

        System.out.println("\n===== 用例3: 装了VS仍失败=GTESS.dll依赖运行库缺失(ERROR_MOD_NOT_FOUND) =====");
        List<String> log3 = new ArrayList<>();
        log3.add("错误使用 loadlibrary");
        log3.add("加载库 \"C:\\proj\\...\\GTESS.dll\" 时出错");
        log3.add("找不到指定的模块。");
        log3.add("出错 sht_load_engine_library (line 26)");
        log3.add("生成 GTESS.thunk 失败,失败阶段: UQ基准回放(确定性估计值复算)。");
        Map<String, Object> d3 = analyze("steady", "D", log3);
        System.out.println("failureClass = " + d3.get("failureClass"));
        System.out.println("subclass = " + d3.get("loadlibSubclass"));
        System.out.println("stage = " + d3.get("stage"));
        System.out.println("---- summary ----\n" + summaryText(d3));
    }

    private static final class SetPrinter {
        static void print(Map<String, Object> m) {
            for (Map.Entry<String, Object> e : new LinkedHashSet<>(m.entrySet())) {
                System.out.println(e.getKey() + " = " + e.getValue());
            }
        }
    }
}
