package com.tsinghua.matlab;

/**
 * MATLAB 脚本生成相关的小工具。
 */
public final class MatlabUtil {

    private MatlabUtil() {
    }

    /**
     * 转义字符串以便安全嵌入 MATLAB 单引号字面量：
     * 反斜杠 → 双反斜杠，单引号 → 两个单引号。
     */
    public static String escape(String s) {
        return s.replace("\\", "\\\\").replace("'", "''");
    }
}
