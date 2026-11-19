package com.tsinghua.matlab;

import java.io.IOException;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * MATLAB 会话统一字符集约定。
 *
 * <p>引擎会话统一执行 {@code feature('DefaultCharacterSet','GBK')}
 * （MatlabFunctionRunner 每次借出引擎时设置；交付的 MATLAB .m 源码为 GBK 编码，
 * 设为 UTF-8 会把 GBK 中文读成乱码）。因此两侧文件读写必须遵守：</p>
 * <ul>
 *   <li>Java 生成给 MATLAB 消费的脚本/结果文件（dmg_*.m、dmg_export.m、
 *       dmg_setup.m 等）必须按 GBK 写出——脚本文本里内嵌的路径无法转义，
 *       UTF-8 中文在 GBK 会话下会变乱码目录（表现为"未定义函数"）；</li>
 *   <li>MATLAB 写出由 Java 读回的文件（task-result.json、error-report.txt、
 *       dmg_final_cols.txt、采集 CSV 列头等）按 GBK 读取。</li>
 * </ul>
 *
 * <p>纯 ASCII 内容在 GBK 与 UTF-8 下字节相同，英文路径流程行为不变；
 * JSON 配置文件多数写点已配 ESCAPE_NON_ASCII（纯 ASCII 输出），天然免疫，无需改。</p>
 */
public final class MatlabCharset {

    /** MATLAB 会话字符集；勿改为 UTF-8（会把 GBK 交付源码读成乱码导致 preflight 断言失败）。 */
    public static final Charset SESSION = Charset.forName("GBK");

    private MatlabCharset() {
    }

    /** 按 MATLAB 会话字符集编码（等价 getBytes(SESSION)）。 */
    public static byte[] bytes(String s) {
        return s.getBytes(SESSION);
    }

    /** 按 MATLAB 会话字符集读整个文件。 */
    public static String read(Path p) throws IOException {
        return new String(Files.readAllBytes(p), SESSION);
    }

    /** 按 MATLAB 会话字符集写整个文件。 */
    public static void write(Path p, String content) throws IOException {
        Files.write(p, bytes(content));
    }
}
