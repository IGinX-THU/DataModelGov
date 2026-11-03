package com.tsinghua.engine;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.File;
import java.util.ArrayDeque;
import java.util.Deque;

/**
 * R06 交付树根统一解析(可配置 + 自动扫描)。
 * 内置资源使用固定目录名 resources/matlab/delivery(版本无关,升级时整树覆盖内容即可,不改代码);
 * 外部交付树保留原始版本化目录名(Delivery_V1_...)由自动扫描定位。
 * application.yml: engine.r06.root 支持三种取值:
 * <pre>
 * 1) 留空(默认):使用内置交付树 classpath:matlab/delivery
 *    (工作区 resources → target/classes → jar 解压 逐级探测,行为与历史版本一致);
 * 2) classpath:matlab/delivery :显式指向 classpath 中的内置交付树
 *    (即 resources/matlab/delivery;jar 内条目前缀同步生效);
 * 3) 磁盘路径(相对或绝对):指向交付树根或其任意上层目录。
 *    若配置的不是交付树根本身,会自动向下扫描(最多2层)定位含
 *    programs / examples / advanced_C 布局特征的子目录——因此配置到
 *    program/Delivery_V1_20261102_R065(程序 文件夹的父层)也能自动找到 程序/ 下的交付树。
 *    磁盘路径优先级最高,各服务的"工作目录/内置资源/jar"兜底链保持不变。
 * </pre>
 * 容错:配置直接指向 programs 层(其下就是 m_program_adaptive_tune/AFO_V_2)时自动按该层解析;
 * 扫描结果按配置值缓存,不重复遍历磁盘。
 */
@Slf4j
@Component
public class DeliveryTreeLocator {

    /** 内置(classpath 默认)交付树根 —— 固定目录名 resources/matlab/delivery,版本无关。 */
    public static final String DEFAULT_CLASSPATH_ROOT = "matlab/delivery";

    /** 交付树布局特征目录(识别用,缺 programs 一定不算)。 */
    private static final String[] LAYOUT_MARKERS = {
            "programs", "examples", "advanced_C", "docs", "manifests", "tools"
    };

    @Value("${engine.r06.root:}")
    private String configuredRoot;

    /** 扫描结果缓存(key=配置值,避免每次请求遍历磁盘)。 */
    private volatile File cachedRoot;
    private volatile String cachedKey;

    /** classpath 模式交付树根(不带 classpath: 前缀,正斜杠,无尾斜杠)。 */
    public String classpathRoot() {
        String v = configuredRoot == null ? "" : configuredRoot.trim();
        if (v.startsWith("classpath:")) {
            String p = v.substring("classpath:".length()).trim().replace('\\', '/');
            while (p.endsWith("/")) p = p.substring(0, p.length() - 1);
            // 容错:直接指到 programs 层则回退一层作为树根
            if (p.endsWith("/programs")) p = p.substring(0, p.length() - "/programs".length());
            if (!p.isEmpty()) return p;
        }
        return DEFAULT_CLASSPATH_ROOT;
    }

    /** classpath 模式 programs 层(供 jar 条目前缀 / classpath* 模式拼接)。 */
    public String classpathProgramsBase() {
        return classpathRoot() + "/programs";
    }

    /** 文件系统模式的交付树根;未配置 / classpath 前缀 / 定位失败时返回 null。 */
    public File fileRoot() {
        String key = configuredRoot == null ? "" : configuredRoot.trim();
        if (key.isEmpty() || key.startsWith("classpath:")) return null;
        File c = cachedRoot;
        if (c != null && key.equals(cachedKey)) return c;
        File root = locate(key);
        if (root != null) {
            cachedRoot = root;
            cachedKey = key;
            log.info("engine.r06.root 交付树根已定位: {} (配置值: {})", root.getAbsolutePath(), key);
        }
        return root;
    }

    /** 自动扫描定位交付树根:配置目录本身 → 向下最多2层找含布局特征的子目录。 */
    private File locate(String v) {
        File f = new File(v);
        if (!f.isDirectory()) {
            log.warn("engine.r06.root 配置的路径不存在或不是目录: {}", v);
            return null;
        }
        if (layoutScore(f) > 0) return f; // 本身即交付树根
        // BFS 向下最多2层,按布局特征数取最佳
        File best = null;
        int bestScore = 0;
        Deque<File> queue = new ArrayDeque<>();
        Deque<Integer> depth = new ArrayDeque<>();
        queue.add(f);
        depth.add(0);
        while (!queue.isEmpty()) {
            File dir = queue.poll();
            int d = depth.poll();
            if (d >= 2) continue;
            File[] subs = dir.listFiles(File::isDirectory);
            if (subs == null) continue;
            for (File sub : subs) {
                int s = layoutScore(sub);
                if (s > bestScore) {
                    best = sub;
                    bestScore = s;
                }
                queue.add(sub);
                depth.add(d + 1);
            }
        }
        if (best == null) {
            log.warn("engine.r06.root 配置目录及其下2层内未找到含 programs/examples/advanced_C 布局的交付树: {}", v);
        }
        return best;
    }

    /** 布局特征打分:含 programs(+1,必要)且含任一其他特征目录;仅 programs 也算(打分1)。 */
    private int layoutScore(File dir) {
        if (dir == null || !new File(dir, "programs").isDirectory()) return 0;
        int score = 1;
        for (int i = 1; i < LAYOUT_MARKERS.length; i++) {
            if (new File(dir, LAYOUT_MARKERS[i]).isDirectory()) score++;
        }
        return score;
    }

    /** 文件系统模式的交付树 programs 层;null=未配置磁盘路径或布局不符。 */
    public File programsDir() {
        File root = fileRoot();
        if (root == null) return null;
        // 容错:配置/定位结果直接是 programs 层(其下直接是 m_program_adaptive_tune / AFO_V_2)
        if (new File(root, "m_program_adaptive_tune").isDirectory()
                || new File(root, "AFO_V_2").isDirectory()) return root;
        File p = new File(root, "programs");
        if (p.isDirectory()) return p;
        log.warn("engine.r06.root 定位的交付树下未找到 programs 层: {}", root.getAbsolutePath());
        return null;
    }

    /** 文件系统模式的交付树 examples 层;null=未配置或不存在。 */
    public File examplesDir() {
        File root = fileRoot();
        if (root == null) return null;
        File e = new File(root, "examples");
        if (e.isDirectory()) return e;
        File sibling = new File(root.getParentFile(), "examples"); // root 直接指 programs 层时 examples 同级
        return sibling.isDirectory() ? sibling : null;
    }
}
