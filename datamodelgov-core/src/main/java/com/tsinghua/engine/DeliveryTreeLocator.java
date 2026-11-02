package com.tsinghua.engine;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.File;

/**
 * R06 交付树根统一解析(可配置)。
 * application.yml: engine.r06.root 支持三种取值:
 * <pre>
 * 1) 留空(默认):使用内置交付树 classpath:programs/Delivery_V1_20261019_R06
 *    (工作区 resources → target/classes → jar 解压 逐级探测,行为与历史版本一致);
 * 2) classpath:programs/Delivery_V1_20261019_R06 :显式指向 classpath 中的交付树根
 *    (即 resources/programs/ 下的当前位置;jar 内条目前缀同步生效);
 * 3) 磁盘路径(相对或绝对):指向外部交付树根目录(其下含 programs/ 与 examples/),
 *    如 program/Delivery_V1_20261019_R06/程序(原始交付包布局,多一层"程序"目录也没问题)。
 *    磁盘路径优先级最高,各服务的"工作目录/内置资源/jar"兜底链保持不变。
 * </pre>
 * 容错:配置直接指向 programs 层(其下就是 m_program_adaptive_tune/AFO_V_2)时自动按该层解析。
 */
@Slf4j
@Component
public class DeliveryTreeLocator {

    /** 内置(classpath 默认)交付树根。 */
    public static final String DEFAULT_CLASSPATH_ROOT = "programs/Delivery_V1_20261019_R06";

    @Value("${engine.r06.root:}")
    private String configuredRoot;

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

    /** 文件系统模式的交付树根;未配置 / classpath 前缀 / 路径不存在时返回 null。 */
    public File fileRoot() {
        String v = configuredRoot == null ? "" : configuredRoot.trim();
        if (v.isEmpty() || v.startsWith("classpath:")) return null;
        File f = new File(v);
        if (!f.isDirectory()) {
            log.warn("engine.r06.root 配置的交付树根不存在或不是目录: {}", v);
            return null;
        }
        return f;
    }

    /** 文件系统模式的交付树 programs 层;null=未配置磁盘路径或布局不符。 */
    public File programsDir() {
        File root = fileRoot();
        if (root == null) return null;
        // 容错:配置直接指向 programs 层(其下直接是 m_program_adaptive_tune / AFO_V_2)
        if (new File(root, "m_program_adaptive_tune").isDirectory()
                || new File(root, "AFO_V_2").isDirectory()) return root;
        File p = new File(root, "programs");
        if (p.isDirectory()) return p;
        log.warn("engine.r06.root 配置的目录下未找到 programs 层: {}", root.getAbsolutePath());
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
