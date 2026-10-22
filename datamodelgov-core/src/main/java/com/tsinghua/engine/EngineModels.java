package com.tsinghua.engine;

import lombok.Data;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** 发动机项目域模型(工作台),文件存储 JSON 对应的 POJO。 */
public final class EngineModels {

    private EngineModels() {
    }

    /** 工作台项目:一个项目绑定同一台发动机。 */
    @Data
    public static class EngineProject {
        private String id;
        private String name;
        /** 个性化自适应建模 | 系统联合仿真 */
        private String type;
        private String engineId;
        private String location;
        /** 解析后的物理工作目录(保存位置落盘;location 为空时在 project/项目名 下(旧版同根)) */
        private String workdir;
        private String desc;
        private String owner;
        private Long createdAt;

        public Map<String, Object> toMap() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", id);
            m.put("name", name);
            m.put("type", type);
            m.put("engineId", engineId);
            m.put("location", location);
            m.put("workdir", workdir);
            m.put("desc", desc);
            m.put("owner", owner);
            m.put("createdAt", createdAt);
            return m;
        }
    }

    /** 建模任务(首链:稳态试车建模 kind=steady)。 */
    @Data
    public static class ModelingTask {
        /** 空闲可操作:已创建/数据就绪/准备失败后回到此状态 */
        public static final String ST_READY = "READY";
        public static final String ST_PREPARING = "PREPARING";
        public static final String ST_RUNNING = "RUNNING";
        public static final String ST_COMPLETED = "COMPLETED";
        public static final String ST_FAILED = "FAILED";
        public static final String ST_STOP_REQUESTED = "STOP_REQUESTED";
        public static final String ST_STOPPED = "STOPPED";

        /** 错误分类(图01-15/01-16):保存失败与数值失败分开呈现 */
        public static final String ERR_SAVE = "SAVE_FAILED";
        public static final String ERR_NUMERIC = "NUMERIC_FAILED";

        private String id;
        private String projectId;
        /** steady=稳态试车建模(TC24/TC27);后续:transient/flightSteady/flightTransient/evolution */
        private String kind;
        private String name;
        /** 计算路径:steady | transient_instant */
        private String route;
        private String runId;
        private String status;
        private String message;
        /** 失败分类:SAVE_FAILED(交付文件写盘失败) | NUMERIC_FAILED(数值/收敛失败);空=未失败 */
        private String errorKind;
        private String trainingFile;
        private String testFile;
        private Long createdAt;
        private Long startedAt;
        private Long finishedAt;

        /* ---------- TC27稳态更新(kind=steady_update,F-02) ---------- */
        /** 调度更新方法: I | II(独立保存,不自动选优) */
        private String updateMethod;
        /** 新增训练历程(完整试车记录Excel) */
        private String historyFile;
        /** 新增测试历程(可选) */
        private String historyTestFile;
        /** 上游TC24父模型交付Excel(需路径一致) */
        private String upstreamModelFile;
        /** 上游父模型成果id(溯源) */
        private String upstreamModelId;
        /** 使用识别出的小幅变化段辅助稳态辨识(合同默认true) */
        private Boolean includeSmallHistory = Boolean.TRUE;

        /* ---------- TC27瞬态更新(kind=transient_update,F-03) ---------- */
        /** 上游TC27组合稳态模型交付Excel(冻结稳态载体) */
        private String transientUpstreamFile;
        /** 上游模型成果id(溯源) */
        private String transientUpstreamModelId;
        /** 事件选段模式: automatic | manual */
        private String selectionMode = "automatic";
        /** manual模式的瞬态事件时间范围 Nx2(秒) */
        private List<Double[]> eventRangesS = new ArrayList<>();
        /** 估计配置白名单摘要(lambda/maxIterations/integrationStep_s等,透传estimationOptions) */
        private Map<String, Object> estimationOptions = new LinkedHashMap<>();
        /** 程序返回的原始结果(键值),仅保存可序列化摘要 */
        private Map<String, Object> result = new LinkedHashMap<>();
        /** 辨识完整结果浏览 JSON(task='read' 回读 result_view.mat 的白名单子集) */
        private String resultDetailFile;
        /** 运行日志尾部 */
        private List<String> logTail = new ArrayList<>();
        /** 准备(preview)返回的工况与分组明细(编号/Np/Ng/Wf/样本数/分组),真实解析结果 */
        private List<Map<String, Object>> conditions = new ArrayList<>();
        /** 准备记录说明(如 PREP_01 · 数据、配置与运行包一致) */
        private String prepMessage;

        /* ---------- 可选UQ(F-07-TC24):与确定性辨识相互独立 ---------- */
        /** UQ_EXECUTING | UQ_COMPLETED | UQ_FAILED */
        private String uqStatus;
        private String uqMessage;
        /** 合同要求 UQ runId 带 tc24_ 前缀,结果另存不覆盖确定性 */
        private String uqRunId;
        private Long uqStartedAt;
        private Long uqFinishedAt;
        private Map<String, Object> uqResult = new LinkedHashMap<>();
    }

    /** 模型成果:以模型为中心,关联任务、数据、父模型与UQ/预测记录。 */
    @Data
    public static class ModelAsset {
        private String id;
        private String projectId;
        private String taskId;
        private String name;
        /** 来源业务:稳态试车建模 */
        private String sourceBusiness;
        /** 来源阶段:2.4 基础建模 | 2.7 数据更新 */
        private String stage;
        /** 计算路径:稳态方程 | 瞬态时刻方程 */
        private String route;
        private String engineId;
        private Long createdAt;
        /** 正式交付文件(2p4_deterministic_*.xlsx 等)的绝对路径 */
        private String deliveryWorkbookFile;
        /** 导入模型时的身份文件(model_*.identity.json);任务生成的模型为空 */
        private String identityFile;
        /** 训练数据 Excel(溯源:图02-03 输入数据与实际用途) */
        private String trainingFile;
        /** 独立测试数据 Excel(可空;空=未提供,不影响训练与交付) */
        private String testFile;
        /** 父模型 id(TC24 基础建模为空;更新链路指向被更新模型) */
        private String parentModelId;
        /** 结果状态:已交付 | 诊断(未收敛但有效) | 已导入 */
        private String resultStatus;
        /** 关联UQ记录 id 列表(一份模型可有多份UQ;图02-05/02-09) */
        private List<String> uqRecordIds = new ArrayList<>();
        private Map<String, Object> metrics = new LinkedHashMap<>();
    }

    /**
     * UQ评估记录(F-07-TC24):一份模型可多份评估,各有独立身份;
     * 结果另存,不覆盖确定性估计值;预测可显式选择某份记录做区间再传播。
     */
    @Data
    public static class UqRecord {
        public static final String ST_EXECUTING = "EXECUTING";
        public static final String ST_COMPLETED = "COMPLETED";
        public static final String ST_FAILED = "FAILED";

        private String id;
        private String projectId;
        private String taskId;
        private String modelAssetId;
        private String modelName;
        /** 评估方法 B | C | D */
        private String method;
        /** tc24_<method>_<ts>,合同要求前缀 */
        private String runId;
        /** EXECUTING | COMPLETED | FAILED */
        private String status;
        private String message;
        /** 采样设置:particleCount 512 | 1024(sht_tc24_b_config 合同允许值) */
        private Integer particleCount;
        private Long startedAt;
        private Long finishedAt;
        /** UQ 交付 Excel(2p4_uq_method_*.xlsx;后验传播的正式来源) */
        private String deliveryFile;
        /** UQ 完整结果浏览 JSON(task='read' 回读) */
        private String detailFile;
    }

    /** 输出预测记录(F-08 独立稳态预测):支持多工况,逐工况独立状态与结果。 */
    @Data
    public static class PredictionRecord {
        public static final String ST_EXECUTING = "EXECUTING";
        public static final String ST_COMPLETED = "COMPLETED";
        public static final String ST_FAILED = "FAILED";

        private String id;
        private String projectId;
        private String modelAssetId;
        private String modelName;
        /** 下发给程序的模型 Excel 绝对路径 */
        private String modelFile;
        private String runId;
        /** EXECUTING | COMPLETED | FAILED */
        private String status;
        private String message;
        /** 预测输入(Pt1/Tt1/Pamb/Tamb/Mach/Altitude/Wf_model/Mkp/Mkg/inletBoundaryMode);单工况兼容字段 */
        private Map<String, Object> inputs = new LinkedHashMap<>();
        /** 显式选择的UQ记录(区间在新输入下重新传播;空=确定性预测) */
        private String uqRecordId;
        /** 多工况逐条结果(P01..Pxx);单工况时也写入一条,便于统一展示 */
        private List<PredictionCondition> conditions = new ArrayList<>();
        /** 首工况结果摘要(兼容旧前端 kv 展示) */
        private Map<String, Object> result = new LinkedHashMap<>();
        private Long createdAt;
        private Long finishedAt;
    }

    /** 多工况预测的单工况结果(图01-12:部分失败保留有效结果,失败可展开诊断)。 */
    @Data
    public static class PredictionCondition {
        /** P01..Pxx */
        private String id;
        private Map<String, Object> inputs = new LinkedHashMap<>();
        /** COMPLETED | FAILED */
        private String status;
        private String message;
        /** 该工况程序返回摘要(predictionTable 首行标量等) */
        private Map<String, Object> result = new LinkedHashMap<>();
        /** 该工况输出 Excel(steady_model_input_prediction_*.xlsx) */
        private String excelFile;
        private Long finishedAt;
    }
}
