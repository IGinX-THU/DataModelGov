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
            m.put("desc", desc);
            m.put("owner", owner);
            m.put("createdAt", createdAt);
            return m;
        }
    }

    /** 建模任务(首链:稳态试车建模 kind=steady)。 */
    @Data
    public static class ModelingTask {
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
}
