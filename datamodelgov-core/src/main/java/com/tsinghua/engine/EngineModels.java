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
        /** 解析后的物理工作目录(保存位置落盘;location 为空时在 dataRoot 下) */
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
        private String trainingFile;
        private String testFile;
        private Long createdAt;
        private Long startedAt;
        private Long finishedAt;
        /** 程序返回的原始结果(键值),仅保存可序列化摘要 */
        private Map<String, Object> result = new LinkedHashMap<>();
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

    /** 模型成果:以模型为中心,关联任务、数据与交付文件。 */
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
        private Map<String, Object> metrics = new LinkedHashMap<>();
    }

    /** 输出预测记录(F-08 独立稳态预测):一次一个新工况,确定性输出。 */
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
        /** 预测输入(Pt1/Tt1/Pamb/Tamb/Mach/Altitude/Wf_model/Mkp/Mkg/inletBoundaryMode) */
        private Map<String, Object> inputs = new LinkedHashMap<>();
        /** 程序返回的预测结果(Np/Ng/收敛状态等可序列化摘要) */
        private Map<String, Object> result = new LinkedHashMap<>();
        private Long createdAt;
        private Long finishedAt;
    }
}
