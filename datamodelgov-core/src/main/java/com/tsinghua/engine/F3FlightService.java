package com.tsinghua.engine;

import com.tsinghua.matlab.MatlabFunctionRunner;
import com.tsinghua.service.ProgramService;
import com.tsinghua.entity.EngineModelAssetEntity;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.Stream;

/**
 * 飞参建模接入层(F-04 稳态飞参 / F-05 过渡态飞参,同底座 sht_f3_*_task)。
 *
 * 合同为 action 状态机:
 *   A 阶段(数据意图,禁父模型): confirmData → 冻结窗口凭据 confirmationFile
 *   B 阶段(执行): run(configuration 含 confirmationFile + 父模型) → delivery 产物
 *   只读: readResult(结果目录扫描,无 DLL)
 * 结果交付: outputRoot/delivery/ 下 model.xlsx(results.xlsx 等) + f3_result_manifest.json。
 */
@Slf4j
@Service
public class F3FlightService {

    @Autowired
    private ProgramService programService;

    @Autowired
    private EngineProjectStore store;

    @Autowired
    private com.tsinghua.engine.EngineModelRecordService modelRecordService;

    private final ExecutorService executor = Executors.newFixedThreadPool(2);
    private final Map<String, MatlabFunctionRunner> running = new ConcurrentHashMap<>();
    private final Map<String, List<String>> logBuffers = new ConcurrentHashMap<>();
    /** F3通道(稳态飞参/自演化)UQ日志的SSE订阅;TC24通道在Tc24Service里另有一份,按kind分流。 */
    private final Map<String, SseEmitter> uqLogEmitters = new ConcurrentHashMap<>();

    /** F3 运行包清单SHA占位值(适配器会在MATLAB侧用 sht_f3_three_component_assets('manifest')
     *  实测覆盖——local_selection 按包身份切换:legacy R036=2977A31D...CB3,DLL_MAIN_20261010=71EBF628...E13,
     *  此值仅作兜底;不得再从交付源码猜常量)。 */
    private static final String F3_RUNTIME_MANIFEST_SHA256 =
            "71EBF628AD3F8B0EFDB98F736754766EB1F879BA3F7D32A5C10DCAC7F6452E13";

    /** 文件 SHA-256(大写hex,与MATLAB local_hash 输出一致;strcmpi 不区分大小写)。 */
    private static String sha256Hex(File f) throws IOException {
        java.security.MessageDigest d;
        try { d = java.security.MessageDigest.getInstance("SHA-256"); }
        catch (java.security.NoSuchAlgorithmException e) { throw new IOException("SHA-256不可用", e); }
        try (java.io.InputStream in = java.nio.file.Files.newInputStream(f.toPath())) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) d.update(buf, 0, n);
        }
        StringBuilder sb = new StringBuilder();
        for (byte b : d.digest()) sb.append(String.format("%02X", b));
        return sb.toString();
    }

    /** F3 飞参测量Excel合同列(sht_f3_steady_task L207 targets;readtable 要求 Sheet 名恰为 Data)。 */
    private static final String[] F3_MEASUREMENT_COLUMNS = {
            "sample_id", "time_s", "Ps0", "Tt1", "Pt3_eq", "Ng", "Np",
            "Mkp", "Wf", "Tt45", "Altitude", "Mach", "Ts_amb"};

    /**
     * 前置校验飞参Excel:必须有名为 Data 的工作表,且表头含全部合同列。
     * 不校验则MATLAB在 readtable 处报「工作表名称 'Data' 不存在」或映射断言,用户无从修复;
     * 此处给可读错误并列出实际sheet名/缺失列,让用户能自查模板。
     */
    private static void validateMeasurementExcel(File f, String label) throws IOException {
        if (f == null || !f.isFile()) return;
        try (java.io.InputStream in = java.nio.file.Files.newInputStream(f.toPath());
             org.apache.poi.ss.usermodel.Workbook wb = org.apache.poi.ss.usermodel.WorkbookFactory.create(in)) {
            List<String> sheets = new ArrayList<>();
            for (int i = 0; i < wb.getNumberOfSheets(); i++) sheets.add(wb.getSheetName(i));
            int idx = sheets.indexOf("Data");
            if (idx < 0) {
                throw new IllegalStateException(label + "必须包含名为 Data 的工作表(当前工作表: "
                        + String.join(", ", sheets) + ");请使用飞参模板格式(首行表头: "
                        + String.join(", ", F3_MEASUREMENT_COLUMNS) + ")。");
            }
            org.apache.poi.ss.usermodel.Row head = wb.getSheetAt(idx).getRow(0);
            List<String> header = new ArrayList<>();
            if (head != null) {
                for (int c = 0; c < head.getLastCellNum(); c++) {
                    org.apache.poi.ss.usermodel.Cell cell = head.getCell(c);
                    if (cell == null) continue;
                    String v = cell.getCellType() == org.apache.poi.ss.usermodel.CellType.NUMERIC
                            ? String.valueOf((long) cell.getNumericCellValue()) : cell.getStringCellValue().trim();
                    if (!v.isEmpty()) header.add(v);
                }
            }
            List<String> missing = new ArrayList<>();
            for (String col : F3_MEASUREMENT_COLUMNS) {
                if (!header.contains(col)) missing.add(col);
            }
            if (!missing.isEmpty()) {
                throw new IllegalStateException(label + " 的 Data 工作表缺少必填列: "
                        + String.join(", ", missing) + "(当前表头: " + String.join(", ", header) + ")。");
            }
        } catch (IllegalStateException e) {
            throw e;
        } catch (Exception e) {
            throw new IOException(label + " 无法解析为 Excel(.xlsx): " + e.getMessage(), e);
        }
    }

    /** kind → {结果子目录, 任务函数, 适配器文件, 交付Excel名} */
    private static final Map<String, String[]> KIND_DIRS;
    static {
        Map<String, String[]> m = new java.util.HashMap<>();
        m.put("flight_steady", new String[]{"f3-steady", "sht_f3_steady_task", "dmg_f3_steady_task.m", "model.xlsx"});
        m.put("flight_transient", new String[]{"f3-transient", "sht_f3_transient_task", "dmg_f3_transient_task.m", "flight_transient_model.xlsx"});
        // F-06 自演化:同一 m_program_adaptive_tune 目录,入口 Start_Stage4_02_EvolutionTask
        m.put("evolution", new String[]{"evolution", "sht_stage4_evolution_task", "dmg_evolution_task.m", "model.xlsx"});
        KIND_DIRS = java.util.Collections.unmodifiableMap(m);
    }

    private String[] kindDirs(String kind) {
        String[] d = KIND_DIRS.get(kind);
        if (d == null) throw new IllegalArgumentException("未知飞参任务类型: " + kind);
        return d;
    }

    /** 生成 dmg_f3_task.m(action 状态机转发 + 自含 dmg_jsonable 定义)。 */
    private synchronized void writeF3Adapter(File adapterDir, File programCopy, String taskFn) throws IOException {
        StringBuilder m = new StringBuilder();
        m.append("function r = dmg_f3_task(configFile)\n");
        m.append("% F3 flight modeling adapter (generated by DataModelGov)\n");
        m.append("% ASCII-only: engine charset is GBK; keep this file free of non-ASCII text.\n");
        m.append("c = jsondecode(fileread(configFile));\n");
        m.append("addpath('").append(programCopy.getAbsolutePath().replace('\\', '/')).append("', '-begin');\n");
        m.append("rehash;\n");
        m.append("cfg = c.configuration;\n");
        boolean steadyTask = !"sht_f3_transient_task".equals(taskFn);
        // 运行包清单SHA必须由交付资产模块运行时实测(local_selection会按包身份切换目录与SHA,
        // Java侧硬编码常量会随交付包版本漂移——实测legacy=2977A31D...,DLL_MAIN=71EBF628...),
        // workbookSha256是普通文件SHA由Java实测不变,这里仅覆盖runtimeManifestSha256。
        // 仅steady做enrichment:transient任务不消费该字段,且sht_f3_three_component_assets属三部件资产模块
        if (steadyTask) {
            m.append("if isfield(cfg,'parentRuntimeBinding') && ~isempty(fieldnames(cfg.parentRuntimeBinding))\n");
            m.append("    cfg.parentRuntimeBinding.runtimeManifestSha256 = sht_f3_three_component_assets('manifest').sha256;\n");
            m.append("end\n");
        }
        if ("sht_f3_transient_task".equals(taskFn)) {
            // transient 合同(F3:TF:Config 白名单:runId/modelId/trainingFile/testFile/parentWorkbook/sheets/roots/...)与 steady
            // (taskId/identificationFile/engineId/sortieId/...)完全不同;按白名单重建 cfg,忽略 Java 业务字段
            m.append("tf = struct('runId',char(string(cfg.runId)),'modelId',char(string(cfg.modelId)), ...\n");
            m.append("    'trainingFile',char(string(cfg.identificationFile)),'testFile',char(string(cfg.validationFile)), ...\n");
            m.append("    'trainingSheet','Data','testSheet','Data', ...\n");
            m.append("    'outputRoot',cfg.outputRoot,'reportRoot',cfg.reportRoot);\n");
            m.append("if isfield(cfg,'parentWorkbook'), tf.parentWorkbook = char(string(cfg.parentWorkbook)); end\n");
            // parentRuntimeBinding不透传:transient的local_config白名单不接受该字段
            // (sht_f3_transient_task L351仅在"独立验证"action的入参上消费binding,不在任务cfg上),
            // 透传会被"未知任务配置字段"拒绝;瞬态父模型链接只有parentWorkbook,绑定信息保留在configuration.json备查
            // businessIdentity:local_business必查(编号/用途/逐字段basis);交付与训练文件通常不携带业务编号,
            // 值取发起配置,basis如实记录来源(纯ASCII,适配器文件引擎字符集GBK)
            m.append("if ~isfield(cfg,'engineId'), cfg.engineId = 'E-001'; end\n");
            m.append("if ~isfield(cfg,'sortieId'), cfg.sortieId = 'SORTIE-01'; end\n");
            m.append("tf.businessIdentity = struct('engineId',char(string(cfg.engineId)), ...\n");
            m.append("    'sortieId',char(string(cfg.sortieId)), ...\n");
            m.append("    'parentModelId',char(string(cfg.modelId)), ...\n");
            m.append("    'purpose','production', ...\n");
            m.append("    'basis',struct('engineId','engineId from task launch configuration; delivery/training files carry no business id fields', ...\n");
            m.append("        'sortieId','sortie id registered at task creation; training data has no sortie_id column', ...\n");
            m.append("        'parentModelId','parent model asset id; delivery workbook carries no model_id'));\n");
            m.append("cfg = tf;\n");
        } else {
            // steady 合同(local_execution_config 白名单:confirmationFile/runId/outputRoot/reportRoot/maximumIterations/plotEnabled)
            // Java业务字段(parentSource/parentRoute/parentWorkbook/parentRuntimeBinding/identificationFile/validationFile等)
            // 在confirm阶段已经保存到receipt,run阶段只传执行时参数
            m.append("if strcmp(lower(c.action),'run')\n");
            m.append("    tf = struct('confirmationFile',char(string(cfg.confirmationFile)), ...\n");
            m.append("        'runId',char(string(cfg.taskId)), ...\n");
            m.append("        'outputRoot',cfg.outputRoot,'reportRoot',cfg.reportRoot, ...\n");
            m.append("        'maximumIterations',10,'plotEnabled',false);\n");
            m.append("    cfg = tf;\n");
            m.append("end\n");
        }
        // 注意:不得把 selection 塞进 cfg——sht_f3_*_task 的 local_config 白名单会拒"未知配置:selection";
        // 窗口选择由 confirm 分支第三参数 sel 单独传递
        m.append("switch lower(c.action)\n");
        m.append("    case 'readresult'\n");
        m.append("        r = ").append(taskFn).append("('readResult', struct('resultDirectory', c.resultDirectory));\n");
        m.append("    case 'config'\n");
        m.append("        r = ").append(taskFn).append("('config');\n");
        m.append("    case 'confirm'\n");
        if ("sht_f3_transient_task".equals(taskFn)) {
            // transient 的 selection 合同恰一个字段 sourceSegmentIds(sht_f3_transient_task L216,
            // fieldnames 必须恰好 {'sourceSegmentIds'},值=候选事件中被选中的 source_segment_id,事件级非数据段);
            // 不能用 dmg_auto_windows(稳态合同 {identification,independent_validation})。
            // 先无 selection preview 拿程序默认选中的事件集,再按合同包装回传
            m.append("        pv0 = ").append(taskFn).append("('preview', cfg);\n");
            m.append("        ev = pv0.events; ids = ev.source_segment_id(ev.selected);\n");
            m.append("        r = ").append(taskFn).append("('confirm', cfg, struct('sourceSegmentIds', ids));\n");
        } else {
            // steady 的 selection 合同:segment_id 列表(identification/independent_validation),
            // 全部可选窗口(steady_window + small_change, usable_fraction==1)
            m.append("        pv = ").append(taskFn).append("('preview', cfg);\n");
            m.append("        sel = dmg_auto_windows(pv);\n");
            m.append("        r = ").append(taskFn).append("('confirm', cfg, sel);\n");
        }
        m.append("    otherwise, r = ").append(taskFn).append("(lower(c.action), cfg, struct());\n");
        m.append("end\n");
        m.append("r = dmg_jsonable(r);\n");
        m.append("payload = jsonencode(r);\n");
        m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
        m.append("fwrite(fid, payload, 'char');\n");
        m.append("fclose(fid);\n");
        m.append("r = 'ok';\n");
        m.append("end\n");
        m.append(autoWindowsFn());
        m.append(matlabJsonableFn());
        Files.write(new File(adapterDir, "dmg_f3_task.m").toPath(), m.toString().getBytes(StandardCharsets.UTF_8));
    }

    private String matlabJsonableFn() {
        return matlabJsonableFnStatic();
    }

    /** 自动窗口选择:取全部可选段(steady_window/small_change 且 usable_fraction==1)。 */
    private static String autoWindowsFn() {
        StringBuilder m = new StringBuilder();
        m.append("function sel = dmg_auto_windows(pv)\n");
        m.append("% ASCII-only helper: collect all selectable segment ids from a preview task.\n");
        m.append("sel = struct('identification', string([]), 'independent_validation', string([]));\n");
        m.append("if ~isfield(pv, 'result') || ~isfield(pv.result, 'datasets'), return; end\n");
        m.append("ds = pv.result.datasets;\n");
        m.append("for k = 1:numel(ds)\n");
        m.append("    seg = ds(k).segmentation.segments;\n");
        m.append("    ok = ismember(string(seg.segment_class), {'steady_window','small_change'})");
        m.append(" & seg.usable_fraction == 1;\n");
        m.append("    ids = string(seg.segment_id(ok));\n");
        m.append("    if isfield(ds(k), 'role') && strcmp(ds(k).role, 'identification')\n");
        m.append("        sel.identification = ids;\n");
        m.append("    else\n");
        m.append("        sel.independent_validation = ids;\n");
        m.append("    end\n");
        m.append("end\n");
        m.append("end\n");
        return m.toString();
    }

    /** 生成 dmg_evolution_task.m(F-06:preview→自动确认→run 编排 + 只读转发)。 */
    private synchronized void writeEvolutionAdapter(File adapterDir, File programCopy) throws IOException {
        StringBuilder m = new StringBuilder();
        m.append("function r = dmg_evolution_task(configFile)\n");
        m.append("% F-06 evolution adapter (generated by DataModelGov)\n");
        m.append("% ASCII-only: engine charset is GBK; keep this file free of non-ASCII text.\n");
        m.append("c = jsondecode(fileread(configFile));\n");
        m.append("addpath('").append(programCopy.getAbsolutePath().replace('\\', '/')).append("', '-begin');\n");
        m.append("rehash;\n");
        // UQ等独立动作不携带config(建模配置模板),合并块按需执行
        m.append("if isfield(c, 'config')\n");
        m.append("ev = Start_Stage4_02_EvolutionTask();\n"); // 完整 T4_EVOLUTION_V2 模板
        m.append("cfg = ev;\n");
        m.append("ov = c.config;\n");
        m.append("f = fieldnames(ov);\n");
        m.append("for k = 1:numel(f), cfg.(f{k}) = ov.(f{k}); end\n");
        // root补全模板字段(JSON只传业务字段;runtimeBinding/definition等模板字段保留,
        // 否则configuration校验 root 字段数与模板不一致报"请明确选择完整的试车根配置")
        m.append("if isfield(ov, 'root') && isstruct(ov.root)\n");
        m.append("    rt = ev.root;\n");
        m.append("    fn = fieldnames(ov.root);\n");
        m.append("    for k = 1:numel(fn), rt.(fn{k}) = ov.root.(fn{k}); end\n");
        m.append("    cfg.root = rt;\n");
        m.append("end\n");
        // 架次列表补全模板字段(JSON 只传业务字段;selected/order 等由模板+序号补齐)
        m.append("sj = cfg.sorties;\n");
        m.append("n = numel(sj);\n");
        m.append("ts = ev.sorties;\n");
        m.append("for i = 1:n\n");
        m.append("    s = ts; s.order = i;\n");
        m.append("    fn = fieldnames(sj);\n");
        m.append("    for k = 1:numel(fn), s.(fn{k}) = sj(i).(fn{k}); end\n");
        m.append("    if i == 1, cfg.sorties = s; else, cfg.sorties(i) = s; end\n");
        m.append("end\n");
        m.append("end\n");
        m.append("switch lower(c.action)\n");
        m.append("    case 'uqassessment'\n");
        // 自演化UQ(独立任务):uqpreview→自动完整窗口→uqconfirm→uqrun。
        // 配置合同见uq_action:method限C/D;sourceStage=2p4时sourceWorkbook为概率先验
        // (2p4参数化交付);businessIdentity须与已交付模型一致(engineId/sortieId/parentModelId)
        m.append("        uq = c.uqConfig;\n");
        m.append("        pv = Start_Stage4_02_EvolutionTask('uqpreview', uq);\n");
        m.append("        sel = dmg_auto_windows(pv);\n");
        m.append("        Start_Stage4_02_EvolutionTask('uqconfirm', uq, struct('windows', sel, 'sortieId', uq.sortieId));\n");
        m.append("        r = Start_Stage4_02_EvolutionTask('uqrun', uq);\n");
        m.append("    case 'uqstatus'\n");
        m.append("        r = Start_Stage4_02_EvolutionTask('uqstatus', struct('uqDirectory', c.uqDirectory));\n");
        m.append("    case 'status'\n");
        m.append("        r = Start_Stage4_02_EvolutionTask('status', struct('resultDirectory', c.resultDirectory));\n");
        m.append("    case 'readresult'\n");
        // read_action合同:readResult必须指定架次
        m.append("        rd = struct('resultDirectory', c.resultDirectory);\n");
        m.append("        if isfield(c, 'sortieId'), rd.sortieId = c.sortieId; end\n");
        m.append("        r = Start_Stage4_02_EvolutionTask('readResult', rd);\n");
        m.append("    case 'exportindex'\n");
        m.append("        r = Start_Stage4_02_EvolutionTask('exportIndex', struct('resultDirectory', c.resultDirectory));\n");
        m.append("    case 'run'\n");
        // run前每个选中架次必须已确认数据意图(execute断言SHT:T4:Confirmation):
        // preview→自动窗口→confirm,再整批run(程序自身按父链顺序bind_parent生成绑定)。
        // 三者共用同一cfg.outputRoot:own_plan对已有同身份计划幂等(sht_stage4_evolution_task
        // own_plan L335-340),preview首次创建计划目录,confirm/run复用;「新计划目录必须
        // 不存在」只拦无主目录,不拦同身份续用——不能省略preview/confirm,否则intentFile
        // 为空,run直接报「F-xxx缺少完整数据段的合法确认」。
        m.append("        for i = 1:n\n");
        m.append("            if ~cfg.sorties(i).selected, continue; end\n");
        m.append("            sid = cfg.sorties(i).sortieId;\n");
        m.append("            pv = Start_Stage4_02_EvolutionTask('preview', cfg, struct('sortieId', sid));\n");
        m.append("            sel = dmg_auto_windows(pv);\n");
        m.append("            Start_Stage4_02_EvolutionTask('confirm', cfg, struct('sortieId', sid, 'windows', sel));\n");
        m.append("        end\n");
        m.append("        r = Start_Stage4_02_EvolutionTask('run', cfg);\n");
        m.append("    otherwise\n");
        m.append("        r = Start_Stage4_02_EvolutionTask(lower(c.action), cfg);\n");
        m.append("end\n");
        m.append("r = dmg_jsonable(r);\n");
        m.append("payload = jsonencode(r);\n");
        m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
        m.append("fwrite(fid, payload, 'char');\n");
        m.append("fclose(fid);\n");
        m.append("r = 'ok';\n");
        m.append("end\n");
        m.append(autoWindowsFn());
        m.append(matlabJsonableFnStatic());
        Files.write(new File(adapterDir, "dmg_evolution_task.m").toPath(), m.toString().getBytes(StandardCharsets.UTF_8));
    }

    /** 独立 dmg_jsonable 定义(适配器目录自含;与 Tc24Service.matlabJsonableFn 同源)。 */
    private static String matlabJsonableFnStatic() {
        StringBuilder m = new StringBuilder();
        m.append("function s = dmg_jsonable(v)\n");
        m.append("if isa(v,'table')\n");
        m.append("    s = dmg_jsonable(table2struct(v));\n");
        m.append("elseif isstruct(v)\n");
        // 原位遍历(与Tc24Service.matlabJsonableFn同模式):空结构体时numel(s)=0循环自然跳过,
        // 避免取值重建模式下 v.(f{i}) 对空结构体数组展开为零元素逗号列表→零参递归调用报"输入参数的数目不足"
        m.append("    s = v; f = fieldnames(s);\n");
        m.append("    for i = 1:numel(s)\n");
        m.append("        for j = 1:numel(f)\n");
        m.append("            s(i).(f{j}) = dmg_jsonable(s(i).(f{j}));\n");
        m.append("        end\n");
        m.append("    end\n");
        m.append("elseif iscell(v)\n");
        m.append("    for i = 1:numel(v), v{i} = dmg_jsonable(v{i}); end\n");
        m.append("    s = v;\n");
        m.append("else\n");
        m.append("    s = v;\n");
        m.append("end\n");
        m.append("end\n");
        return m.toString();
    }

    private void emitLog(String taskId, String line) {
        // 与 TC24 服务同一口径：日志缓冲/SSE 回放前统一还原 MATLAB 中文乱码。
        line = com.tsinghua.util.MojibakeUtil.repair(line);
        com.tsinghua.engine.MatlabLogRing.append(line);
        List<String> buf = logBuffers.get(taskId);
        if (buf == null) return;
        synchronized (buf) {
            buf.add(line);
            if (buf.size() > 200) buf.remove(0);
        }
        // F3通道UQ的实时日志:原来只进缓冲(/status轮询能读到),SSE订阅拿不到——补齐推送
        SseEmitter emitter = uqLogEmitters.get(taskId);
        if (emitter != null) {
            try {
                emitter.send(SseEmitter.event().data(line));
            } catch (Exception e) {
                log.warn("发送F3 UQ日志到SSE失败: {}", taskId, e);
                uqLogEmitters.remove(taskId);
                try { emitter.complete(); } catch (Exception ignore) { }
            }
        }
    }

    public List<String> logTail(String taskId) {
        List<String> buf = logBuffers.get(taskId);
        return buf == null ? new ArrayList<>() : new ArrayList<>(buf);
    }

    /** F3通道UQ日志流订阅:首次连接先回放已有缓冲,再接实时推送。 */
    public void subscribeUqLogs(String taskId, SseEmitter emitter) {
        uqLogEmitters.put(taskId, emitter);
        try {
            List<String> buf = logBuffers.get(taskId);
            if (buf != null) {
                synchronized (buf) {
                    for (String line : buf) emitter.send(SseEmitter.event().data(line));
                }
            }
            if (buf == null || buf.isEmpty()) {
                emitter.send(SseEmitter.event().data("[系统] 已连接F3通道UQ日志流,等待程序输出..."));
            }
        } catch (Exception e) {
            log.warn("F3 UQ日志回放失败: {}", taskId, e);
            uqLogEmitters.remove(taskId);
            try { emitter.complete(); } catch (Exception ignore) { }
        }
    }

    /** F3 准备(A 阶段): confirmData 冻结窗口凭据(数据意图阶段禁父模型);
     *  evolution(F-06) 准备=check(全批输入与依赖核验,不计算)。 */
    public EngineModels.ModelingTask prepare(EngineModels.ModelingTask task) throws IOException {
        final String key = task.getId();
        boolean evo = "evolution".equals(task.getKind());
        if (running.get(key + ":f3") != null) {
            // 同一任务正在 MATLAB 里跑 run:此时重新确认会与在跑的批次抢同一批文件
            // (它用 diary 占着输出目录的 session 日志),既腾不空目录也会让在跑的 run 失据。
            // 只拦「本进程内确有活跃 run」这一确定情况;进程重启后的残留 RUNNING 不拦,可正常重新确认。
            throw new IOException("当前任务仍在执行建模(run),请等它结束或先停止后再重新确认数据意图");
        }
        task.setStatus(EngineModels.ModelingTask.ST_PREPARING);
        task.setStartedAt(System.currentTimeMillis()); // check/confirm也调MATLAB:必须留执行痕迹,否则完成回READY后运行记录行被清理
        task.setMessage(evo ? "自演化批输入核验中(check)" : "F3数据意图确认中(confirmData)");
        store.saveTask(task);
        logBuffers.put(key, new ArrayList<>());
        emitLog(key, evo ? "发起自演化输入核验(check)" : "发起F3数据意图确认(confirmData)");
        executor.submit(() -> f3Exec(task, evo ? "check" : "confirm"));
        return task;
    }

    /** F3 执行(B 阶段): run(确认凭据+父模型);evolution 为整批编排(适配器内自动确认)。 */
    public EngineModels.ModelingTask run(EngineModels.ModelingTask task) throws IOException {
        final String key = task.getId();
        boolean evo = "evolution".equals(task.getKind());
        if (evo && (task.getIdentificationFile() == null || task.getIdentificationFile().trim().isEmpty())) {
            // 同步拦截:避免先把任务置RUNNING再由异步线程标FAILED
            throw new IOException("请先上传架次试车测量Excel(Data表),再执行整批执行");
        }
        if (!evo && (task.getConfirmationFile() == null || task.getConfirmationFile().isEmpty())) {
            // 自愈兜底:凭据文件实际在盘但实体未记录(如旧版本confirm成功未落库凭据路径)时,
            // 扫描输出目录补挂,避免用户重跑4分钟的检查流程;真没确认过才拒
            File outRoot = new File(store.taskWorkDir(task.getProjectId(), task.getId()), kindDirs(task.getKind())[0]);
            File conf = findConfirmationFile(outRoot);
            if (conf == null) {
                throw new IOException("缺少A阶段确认凭据(confirmationFile),请先执行数据意图确认(检查数据与模型)");
            }
            task.setConfirmationFile(conf.getAbsolutePath().replace('\\', '/'));
            store.saveTask(task);
            log.info("F3任务{}凭据实体缺失,已从输出目录自愈补挂: {}", key, conf.getName());
        }
        task.setStatus(EngineModels.ModelingTask.ST_RUNNING);
        task.setMessage("F3建模执行中(run)");
        task.setStartedAt(System.currentTimeMillis());
        store.saveTask(task);
        logBuffers.putIfAbsent(key, new ArrayList<>());
        emitLog(key, "发起F3建模执行(run)");
        executor.submit(() -> f3Exec(task, "run"));
        return task;
    }

    private void f3Exec(EngineModels.ModelingTask task, String action) {
        final String key = task.getId();
        String[] kd = kindDirs(task.getKind());
        String subDir = kd[0], taskFn = kd[1];
        boolean evo = "evolution".equals(task.getKind());
        // evolution: check=输入核验(READY);run=整批执行(适配器内逐架次自动确认)
        boolean isConfirm = "confirm".equals(action);
        boolean isCheck = "check".equals(action);
        try {
            File programCopy = ensureF3Source(task.getProjectId());
            File workDir = store.taskWorkDir(task.getProjectId(), task.getId());
            File adapterDir = new File(workDir, subDir + "-work");
            // 交给 MATLAB 的 xlsx 副本目录(补齐 OPC docProps 部件,见 XlsxDocPropsCompat);
            // 固定路径保证 confirm/run 用同一份副本,父工作簿 SHA 与 clean identity 保持一致
            File compatDir = new File(workDir, "input-compat");
            // 每次执行前删除旧的适配器目录，确保使用最新代码
            if (adapterDir.exists()) {
                deleteDirectory(adapterDir);
            }
            if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建F3适配器目录");
            File outputRoot = new File(workDir, subDir);
            File reportRoot = new File(workDir, subDir + "-report");
            if (!isConfirm && !isCheck) {
                if ("run".equals(action) && !evo && "sht_f3_transient_task".equals(taskFn)) {
                    // transient 合同(sht_f3_transient_task L36/L58):confirmation.mat 必须位于
                    // cfg.outputRoot 下,run/estimate 从 outputRoot/confirmation.mat 恢复任务状态,
                    // 交付也写进该根——必须复用 confirm 的输出根;像 steady 那样换新时间戳目录
                    // 会报「请先preview并confirm本任务事件」
                    File confFile = new File(task.getConfirmationFile().replace('\\', '/'));
                    if (!confFile.isFile()) throw new IOException("确认凭据不存在: " + confFile);
                    outputRoot = confFile.getParentFile();
                    // 关键:MATLAB 的 check.identity 把整份 cfg(含 outputRoot/reportRoot 绝对路径)算进哈希,
                    // run 若换了报告根就会报 F3:TF:Stale「数据、父模型、配置、源码或物理包已变化」。
                    // 因此两个根必须与 confirm 那次完全一致——直接取确认落盘的 configuration.json 为准。
                    reportRoot = readConfirmedReportRoot(outputRoot, new File(workDir, subDir + "-report"));
                    if (!reportRoot.exists() && !reportRoot.mkdirs()) throw new IOException("无法创建F3报告目录");
                } else if ("run".equals(action)) {
                    // steady/evolution:run必须用独立的全新批次目录——MATLAB合同(local_new_root/own_plan)
                    // 要求run启动时输出目录不存在,由程序自建;Java预创建或复用旧目录(内含上次失败残留)
                    // 会直接报「辨识目录已存在/新计划目录必须不存在」——这里只计算路径,不建目录。
                    // transient不在此列:confirmation.mat必须与交付同根,复用confirm输出根(见上)。
                    String stamp = new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
                    outputRoot = new File(workDir, subDir + "-run-" + stamp);
                    reportRoot = new File(workDir, subDir + "-report-run-" + stamp);
                } else {
                    if (!outputRoot.exists() && !outputRoot.mkdirs()) throw new IOException("无法创建F3输出目录");
                    if (!reportRoot.exists() && !reportRoot.mkdirs()) throw new IOException("无法创建F3报告目录");
                }
            }
            if (isConfirm && !evo) {
                // 重新确认:MATLAB合同(sht_f3_transient_task L39-42)要求 outputRoot/reportRoot 为空
                // 且 <outputRoot>/confirmation.mat 不存在,否则「必须使用空的新输出目录」。
                // 不能靠「把旧内容挪到 -prev-」来腾空:上一次 run 可能仍在 MATLAB 引擎里执行
                // (它用 diary 打开着 <outputRoot>/session_*.log),移动会因文件占用整批失败,
                // 更糟的是凭据已被挪走一半——正在跑的 run / 紧接着的 run 会报「确认凭据不存在」。
                // 因此旧目录一律原样保留(可追溯),重新确认直接换一个全新批次子目录。
                if (!isBlankConfirmRoot(outputRoot)) {
                    String stamp = new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
                    // 子目录挂在 subDir 下,保证 f3-artifacts / 交付定位的目录扫描(subDir 深度3-4)仍能命中
                    outputRoot = new File(new File(workDir, subDir), "confirm-" + stamp);
                    reportRoot = new File(new File(workDir, subDir + "-report"), "confirm-" + stamp);
                    log.info("F3重新确认:旧输出目录非空或已有凭据,改用新批次目录 {} (task={})", outputRoot, key);
                    emitLog(key, "重新确认:改用新批次目录 " + subDir + "/confirm-" + stamp);
                }
            }
            if (evo) {
                writeEvolutionAdapter(adapterDir, programCopy);
            } else {
                writeF3Adapter(adapterDir, programCopy, taskFn);
            }

            Map<String, Object> call = new LinkedHashMap<>();
            call.put("action", action);
            call.put("resultDirectory", outputRoot.getAbsolutePath().replace('\\', '/'));
            if (evo) {
                // T4_EVOLUTION_V2:只传业务字段,模板字段由适配器补全
                // 测量文件(sorties.measurementFile)合同必填非空,空时前置给可读错误,不让MATLAB报合同错
                if (task.getIdentificationFile() == null || task.getIdentificationFile().trim().isEmpty()) {
                    throw new IllegalStateException("请先上传架次试车测量Excel(Data表),再执行核验/整批执行");
                }
                String runId = sanitizeEvolutionRunId(task.getRunId() == null ? key : task.getRunId());
                Map<String, Object> config = new LinkedHashMap<>();
                config.put("projectId", task.getProjectId());
                config.put("engineId", task.getF3EngineId() == null ? "E-001" : task.getF3EngineId());
                config.put("runId", runId);
                config.put("purpose", "production");
                config.put("outputRoot", outputRoot.getAbsolutePath().replace('\\', '/'));
                config.put("reportRoot", reportRoot.getAbsolutePath().replace('\\', '/'));
                String parentWorkbookPath = compatWorkbookPath(resolveParentWorkbook(task), compatDir);
                Map<String, Object> root = new LinkedHashMap<>();
                root.put("source", task.getParentSource() == null ? "2p4" : task.getParentSource());
                root.put("route", task.getParentRoute() == null ? "steady" : task.getParentRoute());
                root.put("workbook", parentWorkbookPath);
                root.put("modelId", task.getParentModelId() == null ? runId + "_ROOT" : task.getParentModelId());
                root.put("identityBasis", "DataModelGov registered parent");
                // 运行时绑定(sht_f3_current_contract L436-455):父Excel非内嵌运行身份且非MAIN已核
                // 历史文件时,check_inputs要求显式声明关联,缺了报"新父模型缺少已核物理关联";
                // runtimeManifestSha256=F3_RUNTIME_MANIFEST_SHA256与飞参路径同一常量
                Map<String, Object> binding = new LinkedHashMap<>();
                binding.put("workbookSha256", sha256Hex(new File(parentWorkbookPath)));
                binding.put("runtimeManifestSha256", F3_RUNTIME_MANIFEST_SHA256);
                binding.put("basis", "DataModelGov自动关联:父工作簿SHA与F3_R036运行包清单SHA已核验");
                root.put("runtimeBinding", binding);
                config.put("root", root);
                Map<String, Object> sortie = new LinkedHashMap<>();
                sortie.put("sortieId", task.getF3SortieId() == null ? "SORTIE-01" : task.getF3SortieId());
                sortie.put("measurementFile", task.getIdentificationFile() == null || task.getIdentificationFile().isEmpty()
                        ? "" : compatWorkbookPath(task.getIdentificationFile(), compatDir));
                sortie.put("validationFile", task.getValidationFile() == null || task.getValidationFile().isEmpty()
                        ? "" : compatWorkbookPath(task.getValidationFile(), compatDir));
                // 配置字典(Stage4/配置字典.csv):measurementSystemId=测量系统身份,合同必填非空;
                // 随交付Excel的measurement_system_id列留档,标识架次测量数据来自本平台登记上传
                sortie.put("measurementSystemId", "DMG_FLIGHT_SORTIE_DATA");
                sortie.put("parentRef", "root");
                sortie.put("role", "normal");
                sortie.put("identityBasis", "DataModelGov upload");
                sortie.put("selected", true);
                List<Map<String, Object>> sorties = new ArrayList<>();
                sorties.add(sortie);
                config.put("sorties", sorties);
                config.put("modelRoute", task.getParentRoute() == null ? "steady" : task.getParentRoute());
                config.put("maximumSortiesPerSession", 0);
                call.put("config", config);
            } else {
                Map<String, Object> configuration = new LinkedHashMap<>();
                configuration.put("taskId", key + "_" + action);
                boolean transientTask = "sht_f3_transient_task".equals(taskFn);
                // 训练文件两合同均必填(required清单),空时前置给可读错误,不让MATLAB报模糊路径错
                if (task.getIdentificationFile() == null || task.getIdentificationFile().trim().isEmpty()) {
                    throw new IllegalStateException("请先上传训练飞参文件(本架次训练 Excel),再进行检查/确认");
                }
                // runId 仅 transient 合同;parentSource/parentRoute/parentWorkbook 是 steady required 清单
                // (preview/confirm 即校验,缺了报"必须显式提供%s")——parentWorkbook 两合同都必填,全程传;
                // transient 适配器 tf 只取白名单字段,parentSource/parentRoute 多传会被丢弃不进白名单
                if (transientTask) {
                    configuration.put("runId", sanitizeEvolutionRunId(task.getRunId() == null ? key : task.getRunId()));
                }
                configuration.put("parentSource", task.getParentSource() == null ? "2p4" : task.getParentSource());
                configuration.put("parentRoute", task.getParentRoute() == null ? "steady" : task.getParentRoute());
                String parentWorkbookPath = compatWorkbookPath(resolveParentWorkbook(task), compatDir);
                configuration.put("parentWorkbook", parentWorkbookPath);
                // 父模型运行时绑定(sht_f3_current_contract L455-462):父Excel既非内嵌运行身份也非
                // MAIN已核历史文件时,必须显式声明关联——workbookSha256=父Excel实测SHA;
                // runtimeManifestSha256=交付源码固定常量(sht_f3_three_component_assets.m L32,F3_R036运行包);
                // 换交付运行包版本时必须同步此常量,否则MATLAB在绑定校验处报SHA不符
                log.info("F3任务{}开始计算父工作簿SHA256: {}", key, parentWorkbookPath);
                Map<String, Object> binding = new LinkedHashMap<>();
                binding.put("workbookSha256", sha256Hex(new File(parentWorkbookPath)));
                log.info("F3任务{}父工作簿SHA256计算完成", key);
                binding.put("runtimeManifestSha256", F3_RUNTIME_MANIFEST_SHA256);
                binding.put("basis", "DataModelGov自动关联:父工作簿SHA与F3_R036运行包清单SHA已核验");
                configuration.put("parentRuntimeBinding", binding);
                configuration.put("identificationFile", task.getIdentificationFile() == null || task.getIdentificationFile().isEmpty()
                        ? "" : compatWorkbookPath(task.getIdentificationFile(), compatDir));
                configuration.put("validationFile", task.getValidationFile() == null || task.getValidationFile().isEmpty()
                        ? "" : compatWorkbookPath(task.getValidationFile(), compatDir));
                // 飞参Excel合同前置校验(Data sheet+13必填列):让用户在发起前看到可读格式错误,
                // 而不是MATLAB readtable 的「工作表名称 'Data' 不存在」
                if (!evo) {
                    validateMeasurementExcel(new File(configuration.get("identificationFile").toString()), "训练飞参文件");
                    if (task.getValidationFile() != null && !task.getValidationFile().trim().isEmpty()) {
                        validateMeasurementExcel(new File(task.getValidationFile().replace('\\', '/')), "独立测试文件");
                    }
                }
                configuration.put("outputRoot", outputRoot.getAbsolutePath().replace('\\', '/'));
                configuration.put("reportRoot", reportRoot.getAbsolutePath().replace('\\', '/'));
                configuration.put("engineId", task.getF3EngineId() == null ? "E-001" : task.getF3EngineId());
                configuration.put("sortieId", task.getF3SortieId() == null ? "SORTIE-01" : task.getF3SortieId());
                configuration.put("modelId", task.getParentModelId() == null ? key : task.getParentModelId());
                configuration.put("taskPurpose", "model_build");
                configuration.put("dataMethod", task.getDataMethod() == null ? "steady_only" : task.getDataMethod());
                if (task.getRegularizationStrength() != null) {
                    configuration.put("regularizationStrength", task.getRegularizationStrength());
                }
                if ("run".equals(action)) {
                    configuration.put("confirmationFile", task.getConfirmationFile().replace('\\', '/'));
                    if (transientTask) {
                        configuration.put("runId", task.getRunId() == null ? key : task.getRunId());
                    }
                }
                call.put("configuration", configuration);
            }
            File resultFile = new File(adapterDir, "f3-" + action + "-result.json");
            call.put("resultFile", resultFile.getAbsolutePath().replace('\\', '/'));
            File cf = new File(adapterDir, "f3-" + action + "-config.json");
            com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
            om.configure(com.fasterxml.jackson.core.JsonGenerator.Feature.ESCAPE_NON_ASCII, true);
            Files.write(cf.toPath(), om.writeValueAsBytes(call));

            emitLog(key, "调用 " + (evo ? "Start_Stage4_02_EvolutionTask" : taskFn) + " (action=" + action + ")");
            MatlabFunctionRunner runner = new MatlabFunctionRunner(adapterDir, evo ? "dmg_evolution_task" : "dmg_f3_task",
                    new Object[]{cf.getAbsolutePath()},
                    new File(workDir, subDir + "-" + action + ".log"), programService.enginePool(),
                    new MatlabFunctionRunner.ProgressCancellationSink() {
                        @Override public void onProgress(String message) { emitLog(key, message); }
                        @Override public boolean isCancellationRequested() { return false; }
                    });
            running.put(key + ":f3", runner);
            runner.run();

            Map<String, Object> result = resultFile.exists()
                    ? new com.fasterxml.jackson.databind.ObjectMapper().readValue(resultFile, Map.class)
                    : new LinkedHashMap<>();
            EngineModels.ModelingTask tk = store.getTask(task.getProjectId(), task.getId());
            if (tk == null) return;
            if (isConfirm) {
                File conf = findConfirmationFile(outputRoot);
                tk.setStatus(EngineModels.ModelingTask.ST_READY);
                // 凭据路径必须写回任务实体:前端「进入稳态参数更新」按钮以 t.confirmationFile 为解锁条件,
                // 只算不set则后台确认完成后按钮永远置灰
                tk.setConfirmationFile(conf != null ? conf.getAbsolutePath().replace('\\', '/') : null);
                tk.setPrepMessage("数据意图已确认(窗口冻结凭据已生成)");
                tk.setMessage("F3数据意图确认完成;可执行建模");
                emitLog(key, "F3数据意图确认完成");
            } else if (isCheck) {
                tk.setStatus(EngineModels.ModelingTask.ST_READY);
                tk.setPrepMessage("自演化批输入核验通过(check)");
                tk.setMessage("输入核验完成;可执行整批自演化建模");
                emitLog(key, "自演化输入核验完成");
            } else {
                File delivery = findDelivery(outputRoot);
                tk.setStatus(delivery != null ? EngineModels.ModelingTask.ST_COMPLETED : EngineModels.ModelingTask.ST_FAILED);
                tk.setFinishedAt(System.currentTimeMillis());
                tk.setMessage(delivery != null ? ("evolution".equals(task.getKind()) ? "自演化模型已交付,可登记到模型成果" : "飞参模型已交付,可登记到模型成果")
                        : "执行完成但未找到交付Excel");
                Map<String, Object> sum = new LinkedHashMap<>();
                sum.put("outputRoot", outputRoot.getAbsolutePath());
                if (delivery != null) sum.put("deliveryWorkbookFile", delivery.getAbsolutePath());
                File manifest = findManifest(outputRoot);
                if (manifest != null) sum.put("manifestJson", manifest.getAbsolutePath());
                tk.setResult(sum);
                emitLog(key, (evo ? "自演化建模" : "F3建模") + "完成" + (delivery != null ? ": " + delivery.getName() : "(无交付Excel)"));
            }
            store.saveTask(tk);
        } catch (Exception e) {
            log.error("F3 {} 执行失败: {}", action, key, e);
            try {
                EngineModels.ModelingTask tk = store.getTask(task.getProjectId(), task.getId());
                if (tk != null) {
                    tk.setStatus(isConfirm ? EngineModels.ModelingTask.ST_READY : EngineModels.ModelingTask.ST_FAILED);
                    if (!isConfirm) {
                        tk.setFinishedAt(System.currentTimeMillis());
                        tk.setErrorKind(EngineModels.ModelingTask.ERR_NUMERIC);
                    }
                    tk.setMessage("F3" + (isConfirm ? "数据意图确认失败: " : "建模执行失败: ")
                            + friendlyF3Error(e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage()));
                    store.saveTask(tk);
                }
            } catch (IOException io) {
                log.error("F3状态写回失败", io);
            }
            emitLog(key, "F3 " + action + " 失败: " + e.getMessage());
        } finally {
            running.remove(key + ":f3");
        }
    }

    /** F-06自演化不确定性评估:走Start_Stage4_02_EvolutionTask的uq动作链
     *  (uqpreview→自动完整窗口→uqconfirm→uqrun)。合同(uq_action):方法限C/D;
     *  sourceStage=2p4时sourceWorkbook为概率先验=对应路线的2p4参数化交付;
     *  TC24 UQ路径(要求point_id稳态均值表)不适用于自演化,勿混用。 */
    public EngineModels.ModelingTask runEvolutionUq(EngineModels.ModelingTask task, String method) throws IOException {
        final String key = task.getId();
        if (!EngineModels.ModelingTask.ST_COMPLETED.equals(task.getStatus())) {
            throw new IOException("请先完成自演化建模并交付模型,再发起不确定性评估");
        }
        Map<String, Object> res = task.getResult();
        if (res == null || !(res.get("outputRoot") instanceof String)) {
            throw new IOException("缺少已交付的演化结果目录(outputRoot);请重新执行建模");
        }
        if (task.getIdentificationFile() == null || task.getIdentificationFile().trim().isEmpty()) {
            throw new IOException("缺少架次测量数据(identificationFile)");
        }
        final String m = method == null ? "D" : method.trim().toUpperCase();
        if (!m.matches("[CD]")) {
            throw new IOException("自演化UQ方法仅支持C/D(F3合同只接通台架到飞行目标的C/D)");
        }
        if (task.getUqStatus() != null && ("EXECUTING".equals(task.getUqStatus()) || "PREPARING".equals(task.getUqStatus()))) {
            throw new IOException("UQ评估正在执行中,不能重复发起");
        }
        final String runDir = ((String) res.get("outputRoot")).replace('\\', '/');
        // 概率先验=带后验样本的2p4/2p7参数化交付(f34先验合同),不是确定性交付;
        // sourceMethod须与先验Manifest的method_id一致(sht_f34_prior local_validate_upstream)
        File programDirProbe = ensureF3Source(task.getProjectId());
        EngineModels.EngineProject pj = store.getProject(task.getProjectId());
        File jobDir = (pj != null && pj.getWorkdir() != null && !pj.getWorkdir().isEmpty())
                ? new File(pj.getWorkdir(), "job") : null;
        File[] priorCandidates = resolveUqPriorCandidates(programDirProbe, jobDir);
        // 节点一致性合同(sht_f34_prior local_match_entry_nodes):先验健康曲线坐标须与当前模型
        // 完全一致(1e-9),否则物理上不可用。后验Manifest的deterministic_workbook_sha256=
        // 其对应确定性工作簿指纹,与演化起点2p4根模型SHA相等才保证同节点网格
        String rootSha = null;
        String rootWbPath = null;
        try {
            rootWbPath = resolveParentWorkbook(task);
            rootSha = sha256Hex(new File(rootWbPath));
        } catch (Exception ignore) { }
        final String rootShaF = rootSha;
        File priorFile = null;
        String priorMethod = null;
        for (File cand : priorCandidates) {
            String mid = readSheetSingleValue(cand, "Manifest", "method_id");
            String status = readSheetSingleValue(cand, "Manifest", "formal_status");
            if (mid == null || status == null || !status.toUpperCase().contains("ACCEPTED")) continue;
            if (rootShaF != null) {
                String dsha = readSheetSingleValue(cand, "Manifest", "deterministic_workbook_sha256");
                if (dsha == null || !dsha.equalsIgnoreCase(rootShaF)) continue; // 节点网格不一致,选了也必败
            }
            if (priorFile == null || (mid.equalsIgnoreCase(m) && !priorMethod.equalsIgnoreCase(m))) {
                // 首个合法候选;若后来出现与本次评估方法同名的先验则优先
                priorFile = cand;
                priorMethod = mid.toUpperCase();
            }
            if (priorMethod != null && priorMethod.equalsIgnoreCase(m)) break;
        }
        if (priorFile == null) {
            throw new IOException("未找到可作概率先验的后验交付:须同时满足①formal_status为ACCEPTED;"
                    + "②deterministic_workbook_sha256与演化起点工作簿一致(同节点网格);"
                    + "③含ConditionalNuisance条件物理参数表——该表仅TC24「方法C」评估导出"
                    + "(B方法为边际化处理没有条件样本,D为局部近似);"
                    + "请对作为演化起点的2p4模型执行方法C的不确定性评估后重试");
        }
        final String sourceWorkbook = priorFile.getAbsolutePath().replace('\\', '/');
        final String sourceMethod = priorMethod == null ? m : priorMethod;
        String uqId = "UQ_" + new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
        task.setUqStatus("PREPARING");
        task.setUqMessage("准备UQ评估(确认观测并绑定目标模型)");
        task.setUqRunId(uqId);
        task.setUqStartedAt(System.currentTimeMillis());
        store.saveTask(task);
        // 评估记录留档:与TC24路径同口径(saveUqRecord会同步运行记录uq-阶段行),
        // 否则自演化UQ在运行记录/评估记录里无痕
        EngineModels.UqRecord uqRec = new EngineModels.UqRecord();
        uqRec.setProjectId(task.getProjectId());
        uqRec.setTaskId(key);
        for (EngineModels.ModelAsset ma : store.listModels(task.getProjectId())) {
            if (key.equals(ma.getTaskId())) { uqRec.setModelAssetId(ma.getId()); break; }
        }
        uqRec.setMethod(m);
        uqRec.setRunId(uqId);
        uqRec.setStatus(EngineModels.UqRecord.ST_EXECUTING);
        uqRec.setMessage("自演化UQ评估准备中(方法 " + m + ")");
        uqRec.setStartedAt(System.currentTimeMillis());
        store.saveUqRecord(uqRec);
        final String uqRecId = uqRec.getId();
        logBuffers.putIfAbsent(key, new ArrayList<>());
        emitLog(key, "发起自演化UQ评估: method=" + m + ", uqId=" + uqId);
        executor.submit(() -> {
            File adapterDir = null;
            try {
                File programCopy = ensureF3Source(task.getProjectId());
                File workDir = store.taskWorkDir(task.getProjectId(), task.getId());
                adapterDir = new File(workDir, "evolution-uq-work");
                if (adapterDir.exists()) deleteDirectory(adapterDir);
                if (!adapterDir.mkdirs()) throw new IOException("无法创建适配器目录");
                writeEvolutionAdapter(adapterDir, programCopy);
                // ① readresult取已交付模型身份;businessIdentity须与模型严格一致(uq_action断言)
                Map<String, Object> readCall = new LinkedHashMap<>();
                readCall.put("action", "readresult");
                readCall.put("resultDirectory", runDir);
                // read_action合同:readResult必须指定架次
                readCall.put("sortieId", task.getF3SortieId() == null ? "SORTIE-01" : task.getF3SortieId());
                readCall.put("resultFile", new File(adapterDir, "uq-read-result.json").getAbsolutePath().replace('\\', '/'));
                Map<String, Object> read = runEvolutionAdapter(adapterDir, task, key, readCall, "uq-read");
                Map<String, Object> evo = read.get("evolution") instanceof Map
                        ? (Map<String, Object>) read.get("evolution") : null;
                String modelId = evo != null && evo.get("modelId") != null ? evo.get("modelId").toString() : null;
                String engineId = evo != null && evo.get("engineId") != null ? evo.get("engineId").toString()
                        : (task.getF3EngineId() == null ? "E-001" : task.getF3EngineId());
                if (modelId == null) throw new IOException("无法读取已交付模型身份(readresult无modelId)");
                // ② 组UQ配置并执行 preview→自动窗口→confirm→run
                Map<String, Object> uq = new LinkedHashMap<>();
                uq.put("resultDirectory", runDir);
                uq.put("sortieId", task.getF3SortieId() == null ? "SORTIE-01" : task.getF3SortieId());
                uq.put("uqId", task.getUqRunId());
                uq.put("method", m);
                uq.put("sourceStage", task.getParentSource() == null ? "2p4" : task.getParentSource());
                uq.put("sourceWorkbook", sourceWorkbook.replace('\\', '/'));
                File uqDir = new File(workDir, "evolution-uq-" + task.getUqRunId());
                File uqReport = new File(workDir, "evolution-uq-report-" + task.getUqRunId());
                uq.put("outputRoot", uqDir.getAbsolutePath().replace('\\', '/'));
                uq.put("reportRoot", uqReport.getAbsolutePath().replace('\\', '/'));
                uq.put("confirmationFile", "");
                // sht_f3_steady_task local_independent_uq:独立模型评估必须显式声明允许参考重定基
                // (概率中心来自所选先验,同节点平移保留原物理先验);
                // sourceMethod须与先验Manifest的method_id一致,其余统计选项走F3默认
                Map<String, Object> opts = new LinkedHashMap<>();
                opts.put("allowReferenceRebase", true);
                opts.put("sourceMethod", sourceMethod);
                uq.put("options", opts);
                Map<String, Object> bi = new LinkedHashMap<>();
                bi.put("engineId", engineId);
                bi.put("sortieId", uq.get("sortieId"));
                bi.put("parentModelId", modelId);
                // parentPosteriorId=概率先验(2p4交付)Manifest表的posterior_id,sht_f3_steady_task
                // local_model_uq_identity会用先验文件实测值核对声明(缺列回退run_id)
                String prior = readSheetSingleValue(new File(sourceWorkbook), "Manifest", "posterior_id");
                if (prior == null || prior.isEmpty()) prior = readSheetSingleValue(new File(sourceWorkbook), "Manifest", "run_id");
                bi.put("parentPosteriorId", prior == null ? modelId : prior);
                // resolve合同(uqpreview观测身份用空证据集):无文件证据的显式声明必须逐字段给出依据
                Map<String, Object> basis = new LinkedHashMap<>();
                basis.put("engineId", "任务登记的发动机编号");
                basis.put("sortieId", "任务登记的架次编号");
                basis.put("parentModelId", "本次自演化已交付模型编号(readresult实测)");
                basis.put("parentPosteriorId", "概率先验UQ后验交付Manifest实测编号(缺posterior_id列时回退run_id)");
                bi.put("basis", basis);
                uq.put("businessIdentity", bi);
                Map<String, Object> call = new LinkedHashMap<>();
                call.put("action", "uqassessment");
                call.put("uqConfig", uq);
                call.put("resultFile", new File(adapterDir, "uq-run-result.json").getAbsolutePath().replace('\\', '/'));
                setUqMessage(task.getProjectId(), key, "UQ评估执行中(方法 " + m + ")");
                runEvolutionAdapter(adapterDir, task, key, call, "uq-run");
                // ③ uqstatus读取区间状态与交付Excel路径,不覆盖确定性估计值
                Map<String, Object> uqRes = new LinkedHashMap<>();
                try {
                    Map<String, Object> stCall = new LinkedHashMap<>();
                    stCall.put("action", "uqstatus");
                    stCall.put("uqDirectory", uqDir.getAbsolutePath().replace('\\', '/'));
                    stCall.put("resultFile", new File(adapterDir, "uq-status-result.json").getAbsolutePath().replace('\\', '/'));
                    Map<String, Object> st = runEvolutionAdapter(adapterDir, task, key, stCall, "uq-status");
                    uqRes.put("intervalStatus", st.get("intervalStatus"));
                    uqRes.put("workbook", st.get("workbook"));
                    if (st.get("state") instanceof Map) {
                        uqRes.put("stateStatus", ((Map<?, ?>) st.get("state")).get("status"));
                    }
                } catch (Exception ignore) { }
                EngineModels.ModelingTask tk = store.getTask(task.getProjectId(), key);
                tk.setUqStatus("COMPLETED");
                tk.setUqFinishedAt(System.currentTimeMillis());
                tk.setUqMessage("UQ评估完成;结果另存,不覆盖确定性估计值");
                tk.setUqResult(uqRes);
                store.saveTask(tk);
                EngineModels.UqRecord fr = store.getUqRecord(task.getProjectId(), uqRecId);
                if (fr != null) {
                    fr.setStatus(EngineModels.UqRecord.ST_COMPLETED);
                    fr.setFinishedAt(System.currentTimeMillis());
                    fr.setMessage("自演化UQ评估完成;结果另存,不覆盖确定性估计值");
                    Object wb = uqRes.get("workbook");
                    if (wb != null) fr.setDeliveryFile(wb.toString());
                    store.saveUqRecord(fr);
                }
                emitLog(key, "自演化UQ评估完成");
            } catch (Exception e) {
                log.error("自演化UQ评估失败: {}", key, e);
                String msg = com.tsinghua.util.MojibakeUtil.repair(
                        e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
                java.util.Map<String, Object> diag = null;
                try {
                    java.util.List<String> lines = new java.util.ArrayList<>(
                            logBuffers.getOrDefault(key, java.util.Collections.emptyList()));
                    diag = com.tsinghua.util.UqDiagnostics.analyze(task.getKind(), m, lines);
                    java.io.File rep = com.tsinghua.util.UqDiagnostics.writeReport(
                            store.taskWorkDir(task.getProjectId(), key), uqRecId, diag, lines);
                    if (rep != null) {
                        diag.put("reportFile", rep.getAbsolutePath());
                    }
                } catch (Exception de) {
                    log.warn("自演化UQ诊断生成失败(不影响失败状态写回): {}", de.toString());
                    diag = null;
                }
                String text = diag != null
                        ? com.tsinghua.util.UqDiagnostics.summaryText(diag) : ("UQ评估失败: " + msg);
                try {
                    EngineModels.ModelingTask tk = store.getTask(task.getProjectId(), key);
                    tk.setUqStatus("FAILED");
                    tk.setUqFinishedAt(System.currentTimeMillis());
                    tk.setUqMessage(text);
                    if (diag != null) {
                        java.util.Map<String, Object> uqResMap = tk.getUqResult();
                        if (uqResMap == null) {
                            uqResMap = new java.util.LinkedHashMap<>();
                            tk.setUqResult(uqResMap);
                        }
                        uqResMap.put("diagnostics", diag);
                    }
                    store.saveTask(tk);
                    EngineModels.UqRecord fr = store.getUqRecord(task.getProjectId(), uqRecId);
                    if (fr != null) {
                        fr.setStatus(EngineModels.UqRecord.ST_FAILED);
                        fr.setFinishedAt(System.currentTimeMillis());
                        fr.setMessage(text);
                        store.saveUqRecord(fr);
                    }
                } catch (IOException io) {
                    log.error("UQ状态写回失败", io);
                }
                emitLog(key, "自演化UQ评估失败: " + msg);
            } finally {
                running.remove(key + ":uq");
            }
        });
        return task;
    }

    /**
     * F-07-F3 稳态飞参建模不确定性评估。
     *
     * 通道:Start_FlightModelAdapt_15_UncertaintyTask / sht_f3_steady_task 的 uqRun 动作,
     * 走"同次冻结B结果根"(resultDirectory)合同——复用建模阶段已冻结的 confirmation_receipt,
     * 不需要重新生成 uq_assessment 用途凭据,也不经过TC24的 point_id 稳态均值表。
     *
     * 必填:resultDirectory(建模outputRoot,含result.mat/f3_result_manifest.json/f3_execution_plan.json)、
     * confirmationFile、sourceWorkbook(概率先验=带后验样本的2p4/2p7 UQ交付)、method C/D、
     * runTag、outputRoot、reportRoot。后两项必须是不存在的新目录(MATLAB合同SHT:F3UQ:ExistingRun)。
     *
     * 不改交付包任何 .m 文件:复用Java运行时生成的 dmg_f3_task.m 适配器的 otherwise 分支。
     */
    public EngineModels.ModelingTask runFlightSteadyUq(EngineModels.ModelingTask task, String method) throws IOException {
        final String key = task.getId();
        if (!"flight_steady".equals(task.getKind())) {
            throw new IOException("仅稳态飞参建模支持F3独立UQ评估");
        }
        if (!EngineModels.ModelingTask.ST_COMPLETED.equals(task.getStatus())) {
            throw new IOException("请先完成稳态飞参建模并交付模型,再发起不确定性评估");
        }
        Map<String, Object> res = task.getResult();
        if (res == null || !(res.get("outputRoot") instanceof String)) {
            throw new IOException("缺少已交付的建模结果目录(outputRoot);请重新执行稳态飞参建模");
        }
        final String runDir = ((String) res.get("outputRoot")).replace('\\', '/');
        File runDirFile = new File(runDir);
        for (String need : new String[]{"result.mat", "f3_result_manifest.json",
                "f3_execution_plan.json", "delivery/model.xlsx"}) {
            if (!new File(runDirFile, need).isFile()) {
                throw new IOException("建模交付不完整,缺少 " + need + ";请重新执行稳态飞参建模后再评估");
            }
        }
        if (task.getConfirmationFile() == null || task.getConfirmationFile().trim().isEmpty()
                || !new File(task.getConfirmationFile().replace('\\', '/')).isFile()) {
            throw new IOException("缺少建模阶段冻结的确认凭据(confirmation_receipt.mat);请重新执行数据意图确认");
        }
        if (task.getIdentificationFile() == null || task.getIdentificationFile().trim().isEmpty()) {
            throw new IOException("缺少飞参训练数据(identificationFile)");
        }
        final String m = method == null ? "D" : method.trim().toUpperCase();
        if (!m.matches("[CD]")) {
            throw new IOException("稳态飞参UQ方法仅支持C/D(F-07-F3合同)");
        }
        if (task.getUqStatus() != null
                && ("EXECUTING".equals(task.getUqStatus()) || "PREPARING".equals(task.getUqStatus()))) {
            throw new IOException("UQ评估正在执行中,不能重复发起");
        }

        // 概率先验:带后验样本的2p4/2p7 UQ交付(Manifest+ParameterSummary+PosteriorSamples+ConditionalNuisance)。
        // sht_f34_prior local_validate_upstream 要求 formal_status 含 ACCEPTED 且 method_id==sourceMethod;
        // deterministic_workbook_sha256 与建模父工作簿一致只作优选(MATLAB硬校验是
        // local_match_entry_nodes 的节点坐标1e-9唯一映射),不做一刀切拒绝以免滤掉唯一可用先验。
        final File programCopy = ensureF3Source(task.getProjectId());
        EngineModels.EngineProject pj = store.getProject(task.getProjectId());
        File jobDir = (pj != null && pj.getWorkdir() != null && !pj.getWorkdir().isEmpty())
                ? new File(pj.getWorkdir(), "job") : null;
        File[] candidates = resolveUqPriorCandidates(programCopy, jobDir);
        String parentSha = null;
        File manifestJson = findManifest(runDirFile);
        if (manifestJson != null) {
            try {
                Map<String, Object> mf = new com.fasterxml.jackson.databind.ObjectMapper()
                        .readValue(manifestJson, Map.class);
                Object ps = mf.get("parentSha256");
                if (ps != null) parentSha = ps.toString();
            } catch (Exception ignore) { }
        }
        File priorFile = null;
        String priorMethod = null;
        int bestScore = -1;
        for (File cand : candidates) {
            String mid = readSheetSingleValue(cand, "Manifest", "method_id");
            String status = readSheetSingleValue(cand, "Manifest", "formal_status");
            if (mid == null || status == null || !status.toUpperCase().contains("ACCEPTED")) continue;
            String dsha = readSheetSingleValue(cand, "Manifest", "deterministic_workbook_sha256");
            // 同节点网格优先于方法同名:先验的确定性工作簿与建模父工作簿一致,才可能通过
            // local_match_entry_nodes 的1e-9坐标映射;方法不一致无妨(sourceMethod取先验实测值)。
            int score = ((parentSha != null && dsha != null && dsha.equalsIgnoreCase(parentSha)) ? 4 : 0)
                    + (mid.equalsIgnoreCase(m) ? 1 : 0);
            if (score > bestScore) {
                bestScore = score;
                priorFile = cand;
                priorMethod = mid.toUpperCase();
            }
        }
        if (priorFile == null) {
            throw new IOException("未找到可作概率先验的UQ后验交付:F3稳态飞参UQ需要一份带"
                    + "ParameterSummary/PosteriorSamples/ConditionalNuisance表且formal_status为ACCEPTED的"
                    + "2p4(或2p7)参数化交付;请先对作为父模型的2p4试车模型执行方法C的不确定性评估,"
                    + "或使用交付包MiddleData内自带的后验交付后重试");
        }
        final String sourceWorkbook = priorFile.getAbsolutePath().replace('\\', '/');
        final String sourceMethod = priorMethod;
        final String sourceStage = "2p7".equalsIgnoreCase(task.getParentSource()) ? "2p7" : "2p4";

        final String uqId = "UQ_" + new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date())
                + "_" + (System.currentTimeMillis() % 1000);
        task.setUqStatus("PREPARING");
        task.setUqMessage("准备F3稳态飞参UQ评估(核对冻结凭据与概率先验)");
        task.setUqRunId(uqId);
        task.setUqStartedAt(System.currentTimeMillis());
        store.saveTask(task);

        EngineModels.UqRecord uqRec = new EngineModels.UqRecord();
        uqRec.setProjectId(task.getProjectId());
        uqRec.setTaskId(key);
        for (EngineModels.ModelAsset ma : store.listModels(task.getProjectId())) {
            if (key.equals(ma.getTaskId())) { uqRec.setModelAssetId(ma.getId()); break; }
        }
        uqRec.setMethod(m);
        uqRec.setRunId(uqId);
        uqRec.setStatus(EngineModels.UqRecord.ST_EXECUTING);
        uqRec.setMessage("稳态飞参UQ评估准备中(方法 " + m + ")");
        uqRec.setStartedAt(System.currentTimeMillis());
        store.saveUqRecord(uqRec);
        final String uqRecId = uqRec.getId();

        logBuffers.put(key, new ArrayList<>());
        emitLog(key, "发起F3稳态飞参UQ评估: method=" + m + ", uqId=" + uqId);
        emitLog(key, "概率先验: " + sourceWorkbook + " (sourceMethod=" + sourceMethod + ")");
        executor.submit(() -> {
            try {
                File workDir = store.taskWorkDir(task.getProjectId(), task.getId());
                File adapterDir = new File(workDir, "f3-steady-uq-work");
                if (adapterDir.exists()) deleteDirectory(adapterDir);
                if (!adapterDir.mkdirs()) throw new IOException("无法创建F3 UQ适配器目录");
                writeF3Adapter(adapterDir, programCopy, "sht_f3_steady_task");
                File uqDir = new File(workDir, "f3-steady-uq-" + uqId);
                File uqReport = new File(workDir, "f3-steady-uq-report-" + uqId);
                // MATLAB合同(SHT:F3UQ:ExistingRun):新UQ目录必须不存在,这里只算路径不预建
                if (uqDir.exists() || uqReport.exists()) {
                    throw new IOException("UQ输出目录已存在,请稍后重试: " + uqDir.getName());
                }
                Map<String, Object> uq = new LinkedHashMap<>();
                uq.put("resultDirectory", runDir);
                uq.put("confirmationFile", task.getConfirmationFile().replace('\\', '/'));
                uq.put("sourceStage", sourceStage);
                uq.put("sourceWorkbook", sourceWorkbook);
                uq.put("method", m);
                uq.put("runTag", uqId);
                uq.put("outputRoot", uqDir.getAbsolutePath().replace('\\', '/'));
                uq.put("reportRoot", uqReport.getAbsolutePath().replace('\\', '/'));
                Map<String, Object> opts = new LinkedHashMap<>();
                // 概率中心来自所选先验,允许同节点平移重定基;sourceMethod须与先验Manifest.method_id一致
                opts.put("allowReferenceRebase", true);
                opts.put("sourceMethod", sourceMethod);
                uq.put("options", opts);
                // 业务编号一律由MATLAB从冻结凭据/交付/先验文件的实测值解析,此处不猜编号值,
                // 只按合同给出逐字段依据,避免与文件实值冲突(SHT:F3Identity:Conflict)。
                Map<String, Object> bi = new LinkedHashMap<>();
                bi.put("purpose", "production");
                Map<String, Object> basis = new LinkedHashMap<>();
                basis.put("engineId", "engine id resolved from frozen confirmation and delivery manifest");
                basis.put("sortieId", "sortie id resolved from frozen confirmation and delivery manifest");
                basis.put("parentModelId", "run_id of parent workbook bound in frozen confirmation");
                basis.put("parentPosteriorId", "run_id of selected UQ posterior workbook");
                bi.put("basis", basis);
                uq.put("businessIdentity", bi);

                Map<String, Object> call = new LinkedHashMap<>();
                call.put("action", "uqrun");
                call.put("configuration", uq);
                call.put("resultFile", new File(adapterDir, "f3-uq-run-result.json")
                        .getAbsolutePath().replace('\\', '/'));
                setUqMessage(task.getProjectId(), key, "F3稳态飞参UQ评估执行中(方法 " + m + ")");
                try {
                    runAdapter(adapterDir, "dmg_f3_task", task, key, call, "f3-uq-run");
                } catch (Exception runErr) {
                    // 适配器末尾会把uqrun的大结果结构jsonencode回写;若该步失败,物理计算和
                    // f3_uq_result_manifest.json 可能已经落盘。以交付清单为准,不误判为评估失败。
                    if (!new File(uqDir, "f3_uq_result_manifest.json").isFile()) throw runErr;
                    emitLog(key, "UQ交付已写出,结果JSON回读失败(不影响交付): " + runErr.getMessage());
                }

                Map<String, Object> uqRes = new LinkedHashMap<>();
                uqRes.put("method", m);
                uqRes.put("runTag", uqId);
                uqRes.put("sourceWorkbook", sourceWorkbook);
                uqRes.put("outputRoot", uqDir.getAbsolutePath().replace('\\', '/'));
                uqRes.put("reportRoot", uqReport.getAbsolutePath().replace('\\', '/'));
                // 交付Excel路径写在 f3_uq_result_manifest.json 的 workbook 字段
                File uqManifest = new File(uqDir, "f3_uq_result_manifest.json");
                if (uqManifest.isFile()) {
                    try {
                        Map<String, Object> mf = new com.fasterxml.jackson.databind.ObjectMapper()
                                .readValue(uqManifest, Map.class);
                        if (mf.get("workbook") != null) uqRes.put("workbook", mf.get("workbook"));
                        if (mf.get("sourceIdentity") != null) uqRes.put("sourceIdentity", mf.get("sourceIdentity"));
                    } catch (Exception ignore) { }
                }
                if (!uqRes.containsKey("workbook")) {
                    File delivery = findDelivery(uqDir);
                    if (delivery != null) uqRes.put("workbook", delivery.getAbsolutePath().replace('\\', '/'));
                }
                // uqstatus读持久化控制状态,失败不影响已完成交付
                try {
                    Map<String, Object> stCall = new LinkedHashMap<>();
                    stCall.put("action", "uqstatus");
                    Map<String, Object> stCfg = new LinkedHashMap<>();
                    stCfg.put("outputRoot", uqDir.getAbsolutePath().replace('\\', '/'));
                    stCall.put("configuration", stCfg);
                    stCall.put("resultFile", new File(adapterDir, "f3-uq-status-result.json")
                            .getAbsolutePath().replace('\\', '/'));
                    Map<String, Object> st = runAdapter(adapterDir, "dmg_f3_task", task, key, stCall, "f3-uq-status");
                    uqRes.put("intervalStatus", st.get("status"));
                } catch (Exception ignore) { }

                EngineModels.ModelingTask tk = store.getTask(task.getProjectId(), key);
                tk.setUqStatus("COMPLETED");
                tk.setUqFinishedAt(System.currentTimeMillis());
                tk.setUqMessage("F3稳态飞参UQ评估完成;结果另存,不覆盖确定性估计值");
                tk.setUqResult(uqRes);
                store.saveTask(tk);
                EngineModels.UqRecord fr = store.getUqRecord(task.getProjectId(), uqRecId);
                if (fr != null) {
                    fr.setStatus(EngineModels.UqRecord.ST_COMPLETED);
                    fr.setFinishedAt(System.currentTimeMillis());
                    fr.setMessage("稳态飞参UQ评估完成;结果另存,不覆盖确定性估计值");
                    Object wb = uqRes.get("workbook");
                    if (wb != null) fr.setDeliveryFile(wb.toString());
                    store.saveUqRecord(fr);
                }
                emitLog(key, "F3稳态飞参UQ评估完成");
            } catch (Exception e) {
                log.error("F3稳态飞参UQ评估失败: {}", key, e);
                String msg = com.tsinghua.util.MojibakeUtil.repair(
                        e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
                // 与 TC24/TC27 同一口径:把日志还原成结构化诊断写进 status 接口可见的 uqMessage
                java.util.Map<String, Object> diag = null;
                try {
                    java.util.List<String> lines = new java.util.ArrayList<>(
                            logBuffers.getOrDefault(key, java.util.Collections.emptyList()));
                    diag = com.tsinghua.util.UqDiagnostics.analyze(task.getKind(), m, lines);
                    java.io.File rep = com.tsinghua.util.UqDiagnostics.writeReport(
                            store.taskWorkDir(task.getProjectId(), key), uqRecId, diag, lines);
                    if (rep != null) {
                        diag.put("reportFile", rep.getAbsolutePath());
                    }
                } catch (Exception de) {
                    log.warn("F3 UQ诊断生成失败(不影响失败状态写回): {}", de.toString());
                    diag = null;
                }
                String text = diag != null
                        ? com.tsinghua.util.UqDiagnostics.summaryText(diag) : ("UQ评估失败: " + msg);
                try {
                    EngineModels.ModelingTask tk = store.getTask(task.getProjectId(), key);
                    tk.setUqStatus("FAILED");
                    tk.setUqFinishedAt(System.currentTimeMillis());
                    tk.setUqMessage(text);
                    if (diag != null) {
                        java.util.Map<String, Object> uqResMap = tk.getUqResult();
                        if (uqResMap == null) {
                            uqResMap = new java.util.LinkedHashMap<>();
                            tk.setUqResult(uqResMap);
                        }
                        uqResMap.put("diagnostics", diag);
                    }
                    store.saveTask(tk);
                    EngineModels.UqRecord fr = store.getUqRecord(task.getProjectId(), uqRecId);
                    if (fr != null) {
                        fr.setStatus(EngineModels.UqRecord.ST_FAILED);
                        fr.setFinishedAt(System.currentTimeMillis());
                        fr.setMessage(text);
                        store.saveUqRecord(fr);
                    }
                } catch (IOException io) {
                    log.error("F3 UQ状态写回失败", io);
                }
                emitLog(key, "F3稳态飞参UQ评估失败: " + msg);
            } finally {
                running.remove(key + ":uq");
            }
        });
        return task;
    }

    /** 读工作簿指定表的某列第一个非空值(单行身份表);POI读取,失败返回null。 */
    private String readSheetSingleValue(File xlsx, String sheetName, String column) {
        try (java.io.InputStream in = java.nio.file.Files.newInputStream(xlsx.toPath());
             org.apache.poi.ss.usermodel.Workbook wb = org.apache.poi.ss.usermodel.WorkbookFactory.create(in)) {
            org.apache.poi.ss.usermodel.Sheet sheet = wb.getSheet(sheetName);
            if (sheet == null) return null;
            org.apache.poi.ss.usermodel.Row hr = sheet.getRow(0);
            if (hr == null) return null;
            org.apache.poi.ss.usermodel.DataFormatter fmt = new org.apache.poi.ss.usermodel.DataFormatter();
            int col = -1;
            for (int c = 0; c < hr.getLastCellNum(); c++) {
                if (column.equalsIgnoreCase(fmt.formatCellValue(hr.getCell(c)).trim())) { col = c; break; }
            }
            if (col < 0) return null;
            for (int r = 1; r <= sheet.getLastRowNum(); r++) {
                org.apache.poi.ss.usermodel.Row row = sheet.getRow(r);
                if (row == null) continue;
                String v = fmt.formatCellValue(row.getCell(col)).trim();
                if (!v.isEmpty()) return v;
            }
        } catch (Exception ignore) { }
        return null;
    }

    /** UQ后验交付探测:含ParameterSummary+PosteriorSamples+ConditionalNuisance表。
     *  ConditionalNuisance仅方法C导出(sht_export_2p4_uq_delivery按runResult.conditionalNuisance
     *  条件写入),B方法后验(边际化处理)没有条件物理参数表,f34先验构建必失败,须在此拦下。 */
    private boolean isUqPosteriorWorkbook(File xlsx) {
        try (java.util.zip.ZipFile z = new java.util.zip.ZipFile(xlsx)) {
            java.util.zip.ZipEntry e = z.getEntry("xl/workbook.xml");
            if (e == null) return false;
            java.io.InputStream in = z.getInputStream(e);
            byte[] buf = new byte[8192];
            StringBuilder sb = new StringBuilder();
            int n;
            while ((n = in.read(buf)) > 0) sb.append(new String(buf, 0, n, StandardCharsets.UTF_8));
            in.close();
            return sb.toString().contains("name=\"ParameterSummary\"")
                    && sb.toString().contains("name=\"PosteriorSamples\"")
                    && sb.toString().contains("name=\"ConditionalNuisance\"");
        } catch (Exception e) {
            return false;
        }
    }

    /** 解析自演化UQ的概率先验:必须是带后验样本的2p4/2p7参数化交付
     *  (Manifest+ParameterSummary+PosteriorSamples;sht_f34_prior local_build合同),
     *  确定性交付(2p4_deterministic_*.xlsx)没有样本表,不能作先验。
     *  优先级:①用户工作目录程序包MiddleData自带后验(随交付分发,工程验证用)
     *  ②项目任务uq-output产物。候选须formal_status含ACCEPTED;sourceMethod取先验实测method_id。 */
    private File[] resolveUqPriorCandidates(File programCopy, File projectJobDir) {
        java.util.List<File> out = new ArrayList<>();
        // programCopy即程序目录(m_program_adaptive_tune),MiddleData在其内;项目job目录含各任务uq-output产物
        File[] roots = {new File(programCopy, "MiddleData"), projectJobDir};
        for (File root : roots) {
            if (!root.isDirectory()) continue;
            try (java.util.stream.Stream<java.nio.file.Path> walk = java.nio.file.Files.walk(root.toPath(), 7)) {
                walk.map(java.nio.file.Path::toFile)
                        .filter(f -> f.isFile() && f.getName().toLowerCase().endsWith(".xlsx"))
                        .filter(this::isUqPosteriorWorkbook)
                        .forEach(out::add);
            } catch (IOException e) {
                log.warn("扫描UQ后验候选失败: {}", root, e);
            }
        }
        out.sort((a, b) -> Long.compare(b.lastModified(), a.lastModified()));
        log.info("UQ概率先验候选扫描: roots={} 命中={}", roots, out.size());
        return out.toArray(new File[0]);
    }

    /** 同步执行一次dmg_evolution_task动作并回读结果JSON(调用方负责线程池提交)。 */
    private Map<String, Object> runEvolutionAdapter(File adapterDir, EngineModels.ModelingTask task,
                                                    String key, Map<String, Object> call, String tag) throws Exception {
        return runAdapter(adapterDir, "dmg_evolution_task", task, key, call, tag);
    }

    /** 通用F3适配器执行:dmg_evolution_task(自演化)与dmg_f3_task(稳态飞参)共用同一调用骨架。 */
    private Map<String, Object> runAdapter(File adapterDir, String fn, EngineModels.ModelingTask task,
                                           String key, Map<String, Object> call, String tag) throws Exception {
        File cf = new File(adapterDir, tag + "-config.json");
        com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
        om.configure(com.fasterxml.jackson.core.JsonGenerator.Feature.ESCAPE_NON_ASCII, true);
        Files.write(cf.toPath(), om.writeValueAsBytes(call));
        MatlabFunctionRunner runner = new MatlabFunctionRunner(adapterDir, fn,
                new Object[]{cf.getAbsolutePath()},
                new File(adapterDir, tag + ".log"), programService.enginePool(),
                new MatlabFunctionRunner.ProgressCancellationSink() {
                    @Override public void onProgress(String message) { emitLog(key, message); }
                    @Override public boolean isCancellationRequested() { return false; }
                });
        running.put(key + ":uq", runner);
        try {
            runner.run();
        } finally {
            running.remove(key + ":uq");
        }
        File rf = new File((String) call.get("resultFile"));
        return rf.exists() ? new com.fasterxml.jackson.databind.ObjectMapper().readValue(rf, Map.class)
                : new LinkedHashMap<>();
    }

    /** F3通道UQ协作取消(自演化/稳态飞参共用):请求MATLAB侧安全取消,结果作废不落盘。 */
    public boolean stopEvolutionUq(EngineModels.ModelingTask task) {
        final String key = task.getId();
        MatlabFunctionRunner runner = running.get(key + ":uq");
        if (runner == null) {
            // 陈旧状态对账:服务重启/异常退出后 running 登记丢失,uqStatus 仍停在执行态,
            // 前端永远显示执行中且「请求安全暂停」无效——重置为失败态放行重新发起。
            // 对账成功视为取消受理;本来就无执行态则如实返回 false。
            return reconcileStaleUq(task);
        }
        runner.requestCancel();
        setUqMessage(task.getProjectId(), key, "已请求取消(协作取消,结果作废)");
        emitLog(key, "已请求取消F3通道UQ评估");
        return true;
    }

    /**
     * 服务重启后陈旧UQ状态对账:running 无登记但 uqStatus 仍是执行态 → 重置为 FAILED(会话中断)。
     * /status 轮询时调用,前端无需手动重置即可回到重新评估页面。返回 true 表示执行了对账。
     */
    public boolean reconcileStaleUq(EngineModels.ModelingTask task) {
        final String key = task.getId();
        String st = task.getUqStatus();
        if (!"EXECUTING".equals(st) && !"PREPARING".equals(st)) return false;
        if (running.get(key + ":uq") != null) return false; // 真在跑,不动
        try {
            EngineModels.ModelingTask tk = store.getTask(task.getProjectId(), key);
            if (tk != null && ("EXECUTING".equals(tk.getUqStatus()) || "PREPARING".equals(tk.getUqStatus()))) {
                tk.setUqStatus("FAILED");
                tk.setUqFinishedAt(System.currentTimeMillis());
                tk.setUqMessage("评估会话已中断(服务重启或异常退出),状态已重置;可重新发起评估");
                store.saveTask(tk);
                task.setUqStatus("FAILED");
                task.setUqMessage(tk.getUqMessage());
                emitLog(key, "检测到陈旧的UQ执行状态,已重置为失败态(会话中断)");
                return true;
            }
        } catch (IOException ignore) { }
        return false;
    }

    /** 稳态飞参UQ取消:与自演化同一执行器登记表,语义别名便于Controller按kind分流。 */
    public boolean stopFlightUq(EngineModels.ModelingTask task) {
        return stopEvolutionUq(task);
    }

    private void setUqMessage(String pid, String key, String msg) {
        try {
            EngineModels.ModelingTask tk = store.getTask(pid, key);
            tk.setUqMessage(msg);
            store.saveTask(tk);
        } catch (IOException ignore) { }
    }

    /** 瞬态父模型合同检查:交付Excel须含Model工作表(sht_f33_excel_delivery 'inspect'的要求)。
     *  直接读xlsx(zip)的workbook.xml表名,不依赖Excel COM,开销毫秒级。 */
    private boolean isModelDeliveryWorkbook(File xlsx) {
        try (java.util.zip.ZipFile z = new java.util.zip.ZipFile(xlsx)) {
            java.util.zip.ZipEntry e = z.getEntry("xl/workbook.xml");
            if (e == null) return false;
            java.io.InputStream in = z.getInputStream(e);
            byte[] buf = new byte[8192];
            StringBuilder sb = new StringBuilder();
            int n;
            while ((n = in.read(buf)) > 0) sb.append(new String(buf, 0, n, StandardCharsets.UTF_8));
            in.close();
            return sb.toString().contains("name=\"Model\"");
        } catch (Exception e) {
            return false;
        }
    }

    /** 自演化2p4试车起点合同=sht_f3_current_contract要求CorrectionSchedule表;按workbook.xml轻量探测。 */
    private boolean is2p4ParametricDelivery(File xlsx) {
        try (java.util.zip.ZipFile z = new java.util.zip.ZipFile(xlsx)) {
            java.util.zip.ZipEntry e = z.getEntry("xl/workbook.xml");
            if (e == null) return false;
            java.io.InputStream in = z.getInputStream(e);
            byte[] buf = new byte[8192];
            StringBuilder sb = new StringBuilder();
            int n;
            while ((n = in.read(buf)) > 0) sb.append(new String(buf, 0, n, StandardCharsets.UTF_8));
            in.close();
            return sb.toString().contains("name=\"CorrectionSchedule\"");
        } catch (Exception e) {
            return false;
        }
    }

    /** run 必须复用 confirm 那次的 reportRoot:MATLAB 把整份 cfg(含两个根路径)算进 check.identity,
     *  任一路径变了 run 就判 stale。以 confirm 落盘的 configuration.json 为准,缺失时才退回默认值。 */
    private File readConfirmedReportRoot(File outputRoot, File fallback) {
        File cfg = new File(outputRoot, "configuration.json");
        if (!cfg.isFile()) return fallback;
        try {
            Map<?, ?> m = new com.fasterxml.jackson.databind.ObjectMapper().readValue(cfg, Map.class);
            Object v = m.get("reportRoot");
            if (v != null && !String.valueOf(v).trim().isEmpty()) {
                return new File(String.valueOf(v).replace('\\', '/'));
            }
        } catch (Exception e) {
            log.warn("F3读取确认配置里的 reportRoot 失败,退回默认报告根: {}", e.getMessage());
        }
        return fallback;
    }

    /** confirm 的 MATLAB 合同(local_assert_empty + ~isfile(confirmation.mat))要求输出根干净。
     *  这里只做「能不能直接复用旧根」的判断——绝不移动/删除旧内容:
     *  上次 run 若仍在引擎里计算,它会用 diary 占着 session_*.log,移动必然失败;
     *  即使移动成功,把 confirmation.mat 挪走也会让在跑的 run 报「确认凭据不存在」。
     *  不干净就由调用方换新批次目录,旧目录原样留档。 */
    private boolean isBlankConfirmRoot(File root) {
        if (root == null || !root.isDirectory()) return true;
        if (findConfirmationFile(root) != null) return false;
        File[] items = root.listFiles();
        return items == null || items.length == 0;
    }

    /** MATLAB 的「工作表名称 'X' 不存在或不受支持」在无 Excel 服务时来自 xlsfinfo 回退失败
     *  (见 XlsxDocPropsCompat),原样抛给用户完全看不懂;补一句可执行提示。 */
    private String friendlyF3Error(String msg) {
        if (msg != null && msg.contains("工作表名称") && msg.contains("不存在或不受支持")) {
            return msg + "（本机 MATLAB 无法启动 Excel 服务,交付Excel缺少 docProps 元数据时按表名读取会失败;"
                    + "已尝试自动补齐该元数据,若仍报此错请关闭残留的 EXCEL.EXE 进程后重试）";
        }
        return msg;
    }

    /** 传给 MATLAB 的 xlsx 一律走 docProps 补齐副本(见 XlsxDocPropsCompat):
     *  MATLAB writetable 产物没有 docProps,Excel COM 不可用时 xlsfinfo 的非 COM 回退
     *  fileread 失败,返回错误文本而非 sheet 名,调用方的 ismember 守卫退化为逐字符比较,
     *  会去 readtable 一个不存在的表并报「工作表名称 'X' 不存在或不受支持」。
     *  返回正斜杠绝对路径。 */
    private String compatWorkbookPath(String rawPath, File compatDir) {
        if (rawPath == null || rawPath.trim().isEmpty()) return rawPath;
        File f = new File(rawPath.replace('\\', '/'));
        return XlsxDocPropsCompat.ensure(f, compatDir).getAbsolutePath().replace('\\', '/');
    }

    /** 2p4参数化交付Manifest必需列(=sht_load_2p4_deterministic_delivery local_validate_manifest
     *  的required清单,26字段;交付程序合同变更时必须同步此清单)。 */
    private static final String[] P2P4_MANIFEST_REQUIRED = {
            "schema_version", "stage_id", "method_id", "run_id", "route",
            "delivery_status", "result_quality_status", "solver_converged",
            "convergence_is_delivery_gate", "stop_reason", "configured_lambda",
            "model_mode", "inlet_boundary_mode", "parameter_dictionary_id",
            "schedule_schema_version", "interpolation", "endpoint_policy",
            "correction_schedule_row_count", "measurement_bias_row_count",
            "semantic_payload_sha256", "deterministic_contract_sha256",
            "node_contract_sha256", "training_data_sha256",
            "test_data_used_for_inference", "hidden_truth_used_for_inference",
            "internal_mat_relative_path"};

    /** Manifest表缺失的必需列(逗号串);表缺失/解析失败返回null(不按此口径拦截)。
     *  用于自动解析时跳过Manifest残缺的2p4交付(旧版TC24产出/手工构造),避免送进MATLAB
     *  才报「Manifest缺少字段:…」;显式指定的父模型不拦,由MATLAB给出精确清单。 */
    private String manifestMissingColumns(File xlsx) {
        try {
            java.util.Set<String> cols = sheetHeaderColumns(xlsx, "Manifest");
            if (cols == null) return null;
            java.util.List<String> miss = new ArrayList<>();
            for (String k : P2P4_MANIFEST_REQUIRED) {
                if (!cols.contains(k)) miss.add(k);
            }
            return miss.isEmpty() ? null : String.join(", ", miss);
        } catch (Exception e) {
            return null;
        }
    }

    /** 读xlsx指定工作表第一行表头(共享字符串),返回小写列名集合;读不到返回null。 */
    private java.util.Set<String> sheetHeaderColumns(File xlsx, String sheetName) throws IOException {
        try (java.util.zip.ZipFile z = new java.util.zip.ZipFile(xlsx)) {
            String wb = new String(zipEntryBytes(z, "xl/workbook.xml"), StandardCharsets.UTF_8);
            java.util.regex.Matcher ms = java.util.regex.Pattern
                    .compile("<sheet\\b[^>]*name=\"" + sheetName + "\"[^>]*>").matcher(wb);
            if (!ms.find()) return null;
            java.util.regex.Matcher mr = java.util.regex.Pattern.compile("r:id=\"(rId\\d+)\"")
                    .matcher(ms.group());
            if (!mr.find()) return null;
            String rels = new String(zipEntryBytes(z, "xl/_rels/workbook.xml.rels"), StandardCharsets.UTF_8);
            java.util.regex.Matcher mt = java.util.regex.Pattern
                    .compile("<Relationship\\b[^>]*Id=\"" + mr.group(1) + "\"[^>]*>").matcher(rels);
            if (!mt.find()) return null;
            java.util.regex.Matcher mtg = java.util.regex.Pattern.compile("Target=\"([^\"]+)\"")
                    .matcher(mt.group());
            if (!mtg.find()) return null;
            String target = mtg.group(1).replaceFirst("^/", "");
            if (!target.startsWith("xl/")) target = "xl/" + target;
            String sheet = new String(zipEntryBytes(z, target), StandardCharsets.UTF_8);
            java.util.regex.Matcher row = java.util.regex.Pattern.compile("<row\\b[^>]*>(.*?)</row>",
                    java.util.regex.Pattern.DOTALL).matcher(sheet);
            if (!row.find()) return null;
            // 共享字符串池(si内可能多<t>富文本片段,全部拼接)
            java.util.List<String> sst = new ArrayList<>();
            java.util.zip.ZipEntry ssEntry = z.getEntry("xl/sharedStrings.xml");
            if (ssEntry != null) {
                String ss = new String(zipEntryBytes(z, "xl/sharedStrings.xml"), StandardCharsets.UTF_8);
                java.util.regex.Matcher si = java.util.regex.Pattern.compile("<si>(.*?)</si>",
                        java.util.regex.Pattern.DOTALL).matcher(ss);
                while (si.find()) {
                    StringBuilder sb2 = new StringBuilder();
                    java.util.regex.Matcher tv = java.util.regex.Pattern.compile("<t[^>]*>(.*?)</t>",
                            java.util.regex.Pattern.DOTALL).matcher(si.group(1));
                    while (tv.find()) sb2.append(tv.group(1));
                    sst.add(sb2.toString());
                }
            }
            java.util.Set<String> cols = new java.util.HashSet<>();
            java.util.regex.Matcher cm = java.util.regex.Pattern.compile("<c\\b[^>]*>(.*?)</c>",
                    java.util.regex.Pattern.DOTALL).matcher(row.group(1));
            while (cm.find()) {
                String cell = cm.group();
                String val = "";
                if (cell.contains("t=\"s\"")) {
                    java.util.regex.Matcher vm = java.util.regex.Pattern.compile("<v>(\\d+)</v>").matcher(cell);
                    if (vm.find()) {
                        int idx = Integer.parseInt(vm.group(1));
                        val = idx >= 0 && idx < sst.size() ? sst.get(idx) : "";
                    }
                } else {
                    java.util.regex.Matcher tm = java.util.regex.Pattern.compile("<t[^>]*>(.*?)</t>",
                            java.util.regex.Pattern.DOTALL).matcher(cell);
                    if (tm.find()) val = tm.group(1);
                    else {
                        java.util.regex.Matcher vm = java.util.regex.Pattern.compile("<v>([^<]*)</v>").matcher(cell);
                        if (vm.find()) val = vm.group(1);
                    }
                }
                if (val != null && !val.trim().isEmpty()) cols.add(val.trim().toLowerCase());
            }
            return cols;
        }
    }

    private byte[] zipEntryBytes(java.util.zip.ZipFile z, String entry) throws IOException {
        java.util.zip.ZipEntry e = z.getEntry(entry);
        if (e == null) throw new IOException("zip entry missing: " + entry);
        java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
        try (java.io.InputStream in = z.getInputStream(e)) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
        }
        return bo.toByteArray();
    }

    /** 2p4参数化交付须与请求路线一致(sht_load_2p4_deterministic_delivery校验Manifest路线,
     *  不一致报「Excel路线…与请求路线不一致」);按交付命名约定轻量判断,无路线提示时放行给MATLAB兜底。 */
    private boolean is2p4DeliveryForRoute(File xlsx, String route) {
        if (!is2p4ParametricDelivery(xlsx)) return false;
        String n = xlsx.getName().toLowerCase();
        if ("transient_instant".equals(route)) return n.contains("transient");
        return !n.contains("transient");
    }

    /** F3交付内嵌Manifest表时,xlsfinfo能枚举到但无Excel服务器的readtable按名读取会失败
     *  (「工作表名称'Manifest'不存在或不受支持」),Model身份表则正常。轻量探测workbook.xml。 */
    private boolean hasEmbeddedManifestSheet(File xlsx) {
        try (java.util.zip.ZipFile z = new java.util.zip.ZipFile(xlsx)) {
            java.util.zip.ZipEntry e = z.getEntry("xl/workbook.xml");
            if (e == null) return false;
            java.io.InputStream in = z.getInputStream(e);
            byte[] buf = new byte[8192];
            StringBuilder sb = new StringBuilder();
            int n;
            while ((n = in.read(buf)) > 0) sb.append(new String(buf, 0, n, StandardCharsets.UTF_8));
            in.close();
            return sb.toString().contains("name=\"Manifest\"");
        } catch (Exception e) {
            return false;
        }
    }

    /** evolution runId 合同:^[[A-Za-z0-9][A-Za-z0-9_-]{0,31}$;非法字符剔除并截断。 */
    private String sanitizeEvolutionRunId(String raw) {
        String s = raw == null ? "EVO01" : raw.replaceAll("[^A-Za-z0-9_-]", "");
        if (s.isEmpty() || !s.substring(0, 1).matches("[A-Za-z0-9]")) s = "E" + s;
        return s.length() > 32 ? s.substring(0, 32) : s;
    }

    /**
     * 解析父工作簿,优先级:①登记值 ②用户在发起时「选择已有模型」指定的模型成果交付Excel
     * (parentModelId→模型清单deliveryFile,最直接的用户意图) ③项目内已完成F3任务的
     * 交付Excel(取最新)。MATLAB合同要求root.workbook必填单行文本,空串会被
     * "root.workbook为空或含换行"拒绝;找不到交付物时明确报错引导用户。
     */
    private String resolveParentWorkbook(EngineModels.ModelingTask task) throws IOException {
        boolean transientTask = "flight_transient".equals(task.getKind());
        // 自演化根来源=2p4试车模型时,sht_f3_current_contract('parent')按2p4参数化交付合同读取
        // (CorrectionSchedule/MeasurementBias表),F3/TC27模型交付会被readtable报"工作表不存在"
        boolean evo2p4 = "evolution".equals(task.getKind()) && "2p4".equals(task.getParentSource());
        String evoRoute = task.getParentRoute() == null ? "steady" : task.getParentRoute();
        if (task.getParentWorkbook() != null && !task.getParentWorkbook().trim().isEmpty()) {
            File explicit = new File(task.getParentWorkbook().replace('\\', '/'));
            // 瞬态父模型合同=sht_f33_excel_delivery('inspect')要求Model工作表;2p4参数化交付
            // (Manifest/CorrectionSchedule/NpBranchModel)没有Model表,不能作瞬态父模型
            if (transientTask && !isModelDeliveryWorkbook(explicit)) {
                throw new IllegalStateException("父工作簿缺少Model工作表,不是可执行的模型交付Excel"
                        + "(2p4参数化交付如2p4_deterministic_steady.xlsx只能作稳态F3的父模型);"
                        + "请选择含Model工作表的模型交付文件(如examples/F3/TF_R002_continuous/steady_model.xlsx)");
            }
            // 内嵌Manifest的模型交付在无Excel服务器上业务身份读取必失败(见hasEmbeddedManifestSheet)
            if (transientTask && hasEmbeddedManifestSheet(explicit)) {
                throw new IllegalStateException("父工作簿内嵌Manifest表,本机MATLAB无Excel服务时按名读取会失败;"
                        + "请改选不含Manifest的模型交付(如同任务delivery/model.xlsx)或改用2p4参数化交付作根");
            }
            if (evo2p4 && !is2p4DeliveryForRoute(explicit, evoRoute)) {
                throw new IllegalStateException("自演化2p4试车起点须为" + evoRoute + "路线的参数化交付"
                        + "(含CorrectionSchedule表" + ("transient_instant".equals(evoRoute)
                        ? ",如2p4_deterministic_transient_instant.xlsx" : ",如2p4_deterministic_steady.xlsx")
                        + ");当前文件路线不符或缺表,请改选或改根路线");
            }
            return task.getParentWorkbook().replace('\\', '/');
        }
        // ②发起任务时指定的项目模型:模型成果清单按 projectId+modelId 定位,取其交付Excel
        if (task.getParentModelId() != null && !task.getParentModelId().trim().isEmpty()) {
            try {
                EngineModelAssetEntity m = modelRecordService.queryByKey(task.getProjectId(), task.getParentModelId());
                if (m != null && m.getDeliveryFile() != null && !m.getDeliveryFile().trim().isEmpty()) {
                    File f = new File(m.getDeliveryFile());
                    if (f.isFile()) {
                        if (transientTask && !isModelDeliveryWorkbook(f)) {
                            throw new IllegalStateException("指定模型" + m.getModelId()
                                    + "的交付Excel缺少Model工作表(2p4参数化交付等不能作瞬态父模型);请改选含Model工作表的模型交付");
                        }
                        if (transientTask && hasEmbeddedManifestSheet(f)) {
                            throw new IllegalStateException("指定模型" + m.getModelId()
                                    + "的交付Excel内嵌Manifest表,本机MATLAB无Excel服务时读取会失败;请改选其它模型交付");
                        }
                        if (evo2p4 && !is2p4DeliveryForRoute(f, evoRoute)) {
                            throw new IllegalStateException("指定模型" + m.getModelId()
                                    + "的交付Excel不是" + evoRoute + "路线的2p4参数化交付;"
                                    + "根来源为2.4试车模型时请改选对应路线的TC24参数化交付,或改根来源/根路线");
                        }
                        log.info("F3父工作簿取自指定模型: task={} model={} -> {}", task.getId(), m.getModelId(), f.getAbsolutePath());
                        return f.getAbsolutePath().replace('\\', '/');
                    }
                    log.warn("F3指定模型{}的交付文件不存在: {},回退自动解析", m.getModelId(), m.getDeliveryFile());
                }
            } catch (Exception e) {
                log.warn("F3指定模型{}解析失败,回退自动解析: {}", task.getParentModelId(), e.getMessage());
            }
        }
        // ③项目模型成果清单任意已交付模型(登记时间倒序;涵盖TC24稳态辨识/TC27更新/F3/自演化交付,
        //   清单是所有建模工作流的统一成果入口——用户项目首次做飞参建模时父模型通常来自TC24辨识)
        try {
            for (EngineModelAssetEntity m : modelRecordService.queryList(task.getProjectId(), 1, 50)) {
                if (m.getDeliveryFile() == null || m.getDeliveryFile().trim().isEmpty()) continue;
                File f = new File(m.getDeliveryFile());
                if (!f.isFile()) continue;
                // 瞬态任务自动解析时跳过无Model表的交付(如2p4参数化交付),避免把不兼容父模型送进MATLAB
                if (transientTask && (!isModelDeliveryWorkbook(f) || hasEmbeddedManifestSheet(f))) {
                    log.info("F3父工作簿自动解析跳过不兼容交付(无Model表或内嵌Manifest): task={} model={}", task.getId(), m.getModelId());
                    continue;
                }
                // 非瞬态任务:2p4参数化交付路线须与请求父路线一致(parentRoute),否则MATLAB按
                // manifest校验报「Excel路线transient_instant与请求路线steady不一致」;跳过继续找匹配交付
                if (!transientTask && is2p4ParametricDelivery(f) && !is2p4DeliveryForRoute(f, evoRoute)) {
                    log.info("F3父工作簿自动解析跳过非{}路线2p4参数化交付: task={} model={}", evoRoute, task.getId(), m.getModelId());
                    continue;
                }
                // 非瞬态任务:2p4参数化交付Manifest须完整(26必需字段);残缺交付(旧版TC24产出/
                // 手工构造)送进MATLAB才报「Manifest缺少字段:…」,自动解析时前置跳过
                if (!transientTask && is2p4ParametricDelivery(f)) {
                    String miss = manifestMissingColumns(f);
                    if (miss != null) {
                        log.info("F3父工作簿自动解析跳过Manifest残缺的2p4参数化交付: task={} model={} 缺失[{}]",
                                task.getId(), m.getModelId(), miss);
                        continue;
                    }
                }
                // 自演化2p4根只接受对应路线的参数化交付;F3/TC27交付作2p4试车起点会被MATLAB合同拒绝
                if (evo2p4 && !is2p4DeliveryForRoute(f, evoRoute)) {
                    log.info("F3父工作簿自动解析跳过非{}路线2p4参数化交付: task={} model={}", evoRoute, task.getId(), m.getModelId());
                    continue;
                }
                log.info("F3父工作簿取自项目模型清单: task={} model={} -> {}", task.getId(), m.getModelId(), f.getAbsolutePath());
                return f.getAbsolutePath().replace('\\', '/');
            }
        } catch (Exception e) {
            log.warn("F3父工作簿模型清单扫描失败,回退任务结果解析: {}", e.getMessage());
        }
        File fallback = null;
        long newest = -1L;
        for (EngineModels.ModelingTask t : store.listTasks(task.getProjectId())) {
            if (t.getId() != null && t.getId().equals(task.getId())) continue;
            if (t.getKind() == null || !(t.getKind().equals("evolution") || t.getKind().startsWith("flight_"))) continue;
            if (!EngineModels.ModelingTask.ST_COMPLETED.equals(t.getStatus())) continue;
            Map<String, Object> r = t.getResult();
            if (r == null || !(r.get("deliveryWorkbookFile") instanceof String)) continue;
            File f = new File((String) r.get("deliveryWorkbookFile"));
            if (!f.isFile()) continue;
            // 瞬态任务:兜底只接受含Model表且不内嵌Manifest的模型交付。老交付记录指向results.xlsx时自愈:
            // 同delivery目录的model.xlsx才是模型交付(含Model表),results只是结果Excel
            if (transientTask) {
                File pf = f;
                if (pf.getName().equalsIgnoreCase("results.xlsx")) {
                    File mx = new File(pf.getParentFile(), "model.xlsx");
                    pf = (mx.isFile() && isModelDeliveryWorkbook(mx)) ? mx : null;
                } else if (!isModelDeliveryWorkbook(pf)) {
                    pf = null;
                }
                if (pf != null && hasEmbeddedManifestSheet(pf)) pf = null;
                if (pf == null) {
                    log.info("F3父工作簿兜底解析跳过不兼容交付(无Model表或内嵌Manifest): task={} file={}", task.getId(), f.getName());
                    continue;
                }
                f = pf;
            }
            if (evo2p4 && !is2p4DeliveryForRoute(f, evoRoute)) {
                log.info("F3父工作簿兜底解析跳过非{}路线2p4参数化交付: task={} file={}", evoRoute, task.getId(), f.getName());
                continue;
            }
            // 非瞬态任务:2p4参数化交付路线须与请求父路线一致,理由同上(自动解析过滤)
            if (!transientTask && is2p4ParametricDelivery(f) && !is2p4DeliveryForRoute(f, evoRoute)) {
                log.info("F3父工作簿兜底解析跳过非{}路线2p4参数化交付: task={} file={}", evoRoute, task.getId(), f.getName());
                continue;
            }
            // 非瞬态任务:2p4参数化交付Manifest须完整,理由同上(自动解析过滤)
            if (!transientTask && is2p4ParametricDelivery(f)) {
                String miss = manifestMissingColumns(f);
                if (miss != null) {
                    log.info("F3父工作簿兜底解析跳过Manifest残缺的2p4参数化交付: task={} file={} 缺失[{}]",
                            task.getId(), f.getName(), miss);
                    continue;
                }
            }
            long stamp = t.getFinishedAt() == null ? 0L : t.getFinishedAt();
            if (stamp > newest) { newest = stamp; fallback = f; }
        }
        // ⑤ 项目文件库(model类)兜底:新建项目尚无模型成果时,建项初始化的示例模型交付
        //    (示例-瞬态稳态载体模型.xlsx等,含Model工作表)可直接作瞬态父模型;优先"载体/稳态"类
        if (fallback == null && transientTask && fileLibraryMetaService != null) {
            File libDefault = null;
            for (com.tsinghua.entity.FileLibraryEntity e : fileLibraryMetaService.queryPage("model", null, null, 1, 50)) {
                File f = new File(e.getPath());
                if (!f.isFile() || !isModelDeliveryWorkbook(f) || hasEmbeddedManifestSheet(f)) continue;
                if (libDefault == null) libDefault = f;
                if (e.getKind() != null && e.getKind().contains("载体")) { libDefault = f; break; }
            }
            if (libDefault != null) {
                log.info("F3父工作簿取自项目文件库: task={} -> {}", task.getId(), libDefault.getAbsolutePath());
                return libDefault.getAbsolutePath().replace('\\', '/');
            }
        }
        if (fallback == null) {
            if (evo2p4) {
                throw new IllegalStateException("2p4试车起点不可用:项目内没有2p4参数化交付(含CorrectionSchedule表,"
                        + "如TC24稳态辨识输出的2p4_deterministic_steady.xlsx);"
                        + "请先完成TC24稳态系数辨识,或在登记时指定参数化交付文件/改选其它根来源");
            }
            throw new IllegalStateException("父工作簿不可用:未指定项目模型(可在发起任务的「选择已有模型」中指定),"
                    + "也未登记工作簿路径,且项目内没有已交付的模型成果或已完成的稳态辨识/自演化任务;"
                    + "请先完成上游建模任务(如稳态系数辨识)或指定模型后重试。");
        }
        log.info("F3父工作簿自动解析: task={} -> {}", task.getId(), fallback.getAbsolutePath());
        return fallback.getAbsolutePath().replace('\\', '/');
    }

    /** 只读结果清单(无DLL):manifest+delivery Excel路径,直接文件扫描。 */
    public Map<String, Object> readResultFiles(String projectId, String taskId, String kind) throws IOException {
        String[] kd = kindDirs(kind);
        File outputRoot = new File(store.taskWorkDir(projectId, taskId), kd[0]);
        Map<String, Object> out = new LinkedHashMap<>();
        File delivery = findDelivery(outputRoot);
        out.put("deliveryWorkbookFile", delivery != null ? delivery.getAbsolutePath() : null);
        File manifest = findManifest(outputRoot);
        out.put("manifestJson", manifest != null ? manifest.getAbsolutePath() : null);
        out.put("outputRoot", outputRoot.getAbsolutePath());
        return out;
    }

    private File findManifest(File outputRoot) {
        File direct = new File(outputRoot, "f3_result_manifest.json");
        if (direct.isFile()) return direct;
        try (Stream<Path> walk = Files.walk(outputRoot.toPath(), 3)) {
            return walk.map(Path::toFile)
                    .filter(f -> f.isFile() && f.getName().toLowerCase().endsWith("manifest.json"))
                    .findFirst().orElse(null);
        } catch (IOException e) {
            return null;
        }
    }

    private File findConfirmationFile(File outputRoot) {
        try (Stream<Path> walk = Files.walk(outputRoot.toPath(), 3)) {
            return walk.map(Path::toFile)
                    .filter(f -> f.isFile() && f.getName().toLowerCase().contains("confirmation"))
                    .max(Comparator.comparingLong(File::lastModified))
                    .orElse(null);
        } catch (IOException e) {
            return null;
        }
    }

    private File findDelivery(File outputRoot) {
        File delivery = new File(outputRoot, "delivery");
        File[] xs = delivery.listFiles((d, n) -> n.toLowerCase().endsWith(".xlsx"));
        if (xs != null && xs.length > 0) {
            // 模型交付优先:results.xlsx是结果Excel,不能作下游任务的父模型(transient父模型合同要求Model表)
            for (File x : xs) if (x.getName().equalsIgnoreCase("model.xlsx")) return x;
            File best = null;
            for (File x : xs) if (best == null || x.lastModified() > best.lastModified()) best = x;
            return best;
        }
        try (Stream<Path> walk = Files.walk(outputRoot.toPath(), 3)) {
            return walk.map(Path::toFile)
                    .filter(f -> f.isFile() && f.getName().toLowerCase().endsWith(".xlsx"))
                    .max(Comparator.comparingLong(File::lastModified))
                    .orElse(null);
        } catch (IOException e) {
            return null;
        }
    }

    /** F3程序源:项目工作目录 programs/m_program_adaptive_tune 优先,target/classes 兜底。 */
    @Autowired(required = false)
    private FileLibraryMetaService fileLibraryMetaService;

    private File ensureF3Source(String projectId) throws IOException {
        EngineModels.EngineProject p = store.getProject(projectId);
        File user = (p != null && p.getWorkdir() != null && !p.getWorkdir().isEmpty())
                ? new File(new File(p.getWorkdir()), "programs/m_program_adaptive_tune") : null;
        if (user != null && new File(user, "Start_FlightModelAdapt_14_SteadyTask.m").isFile()) {
            applyF3ProgramPatches(user);
            return user;
        }
        // 配置的磁盘交付树(engine.r06.root)优先于内置资源
        File ext = deliveryTree != null ? deliveryTree.programsDir() : null;
        if (ext != null) {
            File extProg = new File(ext, "m_program_adaptive_tune");
            if (new File(extProg, "Start_FlightModelAdapt_14_SteadyTask.m").isFile()) return extProg;
        }
        File c1 = new File("target/classes/" + r06ProgramsBase() + "/m_program_adaptive_tune");
        File c2 = new File("datamodelgov-server/target/classes/" + r06ProgramsBase() + "/m_program_adaptive_tune");
        if (new File(c1, "Start_FlightModelAdapt_14_SteadyTask.m").isFile()) return c1;
        if (new File(c2, "Start_FlightModelAdapt_14_SteadyTask.m").isFile()) return c2;
        throw new IOException("未找到F3飞参程序(项目工作目录与classpath均无);"
                + "请在项目工作目录 program/m_program_adaptive_tune 下放置程序");
    }

    private static final String R06_IN_CLASSPATH = "matlab/delivery/programs";

    /** 交付树根可配置解析(engine.r06.root):磁盘路径优先,classpath/内置资源/jar 兜底。 */
    @Autowired(required = false)
    private DeliveryTreeLocator deliveryTree;

    /** 交付树 programs 层 classpath 基准(配置 classpath 模式时跟随配置)。 */
    private String r06ProgramsBase() {
        return deliveryTree != null ? deliveryTree.classpathProgramsBase() : R06_IN_CLASSPATH;
    }

    /**
     * 交付程序运行期补丁(F3):项目工作副本字节级ASCII替换,交付树不动,幂等。
     * 背景:部署机无Excel COM时xlsfinfo对xlsx可能返回空char形式的sheets,
     * ismember(字符串,空char)按逐字符比较返回非标量逻辑数组,&& / if 直接报
     * "操作数必须能够转换为逻辑标量值"(辨识完成后结果回读即失败)。改用
     * any(strcmp(cellstr(sheets),...)),任何sheets形态都得到标量逻辑;空sheets时
     * 如实跳过验证sheet读取(validationMetrics保持空表,不伪装成已读取)。
     */
    private void applyF3ProgramPatches(File programCopy) {
        File f = new File(programCopy, "sht_f3_steady_task.m");
        if (!f.isFile()) return;
        try {
            // ISO-8859-1往返保持GBK字节不变;补丁目标串均为纯ASCII,不会切进多字节序列
            String content = new String(Files.readAllBytes(f.toPath()), StandardCharsets.ISO_8859_1);
            if (content.contains("any(strcmp(cellstr(sheets)")) return; // 已打补丁,幂等跳过
            String patched = content
                    .replace("readValidation&&ismember('validation_metrics',sheets)",
                            "readValidation&&any(strcmp(cellstr(sheets),'validation_metrics'))")
                    .replace("readValidation&&ismember('validation_predictions',sheets)",
                            "readValidation&&any(strcmp(cellstr(sheets),'validation_predictions'))")
                    .replace("readValidation&&ismember('validation_small_history',sheets)",
                            "readValidation&&any(strcmp(cellstr(sheets),'validation_small_history'))")
                    .replace("if ismember('EvidenceLineage',sheets)",
                            "if any(strcmp(cellstr(sheets),'EvidenceLineage'))");
            if (!patched.equals(content)) {
                Files.write(f.toPath(), patched.getBytes(StandardCharsets.ISO_8859_1));
                log.info("已应用F3程序补丁(xlsfinfo空sheets标量化比较): {}", f);
            }
        } catch (Exception e) {
            log.warn("F3程序补丁应用失败({}): {}", f, e.getMessage());
        }
    }

    /** 递归删除目录 */
    private static void deleteDirectory(File directory) {
        if (directory == null || !directory.exists()) return;
        File[] files = directory.listFiles();
        if (files != null) {
            for (File file : files) {
                if (file.isDirectory()) {
                    deleteDirectory(file);
                } else {
                    file.delete();
                }
            }
        }
        directory.delete();
    }
}
