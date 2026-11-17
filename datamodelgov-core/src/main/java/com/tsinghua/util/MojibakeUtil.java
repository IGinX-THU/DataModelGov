package com.tsinghua.util;

import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CharsetEncoder;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;

/**
 * 修复 MATLAB 侧中文乱码。
 *
 * <p>会话字符集被固定为 GBK（见 MatlabFunctionRunner），而交付包里少量 .m 文件是
 * UTF-8 编码，字面量在 MATLAB 内部就被按 GBK 读成了乱码，并原样抛到 Java。
 * 一条消息里经常是「正常中文 + 乱码片段」混合，例如
 * 「确定性结果不能用于当前UQ回放：稳态点失败：姘旂儹骞宠　鐗╃悊...」。</p>
 *
 * <p>旧实现把整串按 GBK 回编码再按 UTF-8 解码，会修好乱码片段却把前面的正常
 * 中文二次破坏（正是 uqMessage 里出现「ȷ???...气热平衡物理求??失败」的原因）。
 * 这里改为按片段尝试还原：只接受「更像正常中文」的候选，正常片段原样保留；
 * 已在 MATLAB 侧丢失的字节会变成 U+FFFD，不做臆测替换。方法幂等，可重复调用。</p>
 *
 * <p>本类只处理文本，不改变 MATLAB 会话字符集，也不修改任何 .m 源码。</p>
 */
public final class MojibakeUtil {

    private static final Charset GBK = Charset.forName("GBK");
    private static final Charset GB18030 = Charset.forName("GB18030");

    /** U+FFFD、假名、欧元符号、制表符等 UTF-8→GBK 误读时常见的杂字符。 */
    private static final String TELLTALE =
            "锛姘鐗娈涓銆鏄鐨浣纭宄鈥戠妯鍔犳燂纭€鍙鑳澶辫旂儹骞宠";

    /** 单次尝试覆盖的最大字符数，控制高频日志下的开销。 */
    private static final int MAX_SPAN = 64;

    /** 只有明显更像中文才替换，避免把正常中文误判为乱码。 */
    private static final int MIN_GAIN = 4;

    private MojibakeUtil() {
    }

    /**
     * 尽力还原字符串中的乱码片段。正常文本原样返回；已修复的文本再次调用不会变化。
     */
    public static String repair(String msg) {
        if (msg == null || msg.isEmpty() || !needsRepair(msg)) {
            return msg;
        }
        StringBuilder out = new StringBuilder(msg.length());
        int n = msg.length();
        int i = 0;
        while (i < n) {
            // U+FFFD 与代理项无法用 GBK/GB18030 回编码，作为片段边界原样保留。
            if (isUnencodable(msg.charAt(i))) {
                out.append(msg.charAt(i));
                i++;
                continue;
            }
            int end = i;
            while (end < n && !isUnencodable(msg.charAt(end))) {
                end++;
            }
            String block = msg.substring(i, end);
            out.append(needsRepair(block) ? repairBlock(block) : block);
            i = end;
        }
        return out.toString();
    }

    private static boolean needsRepair(String s) {
        int weird = 0;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '\uFFFD' || TELLTALE.indexOf(c) >= 0) {
                return true;
            }
            if (isWeird(c) && ++weird >= 2) {
                return true;
            }
        }
        return false;
    }

    private static boolean isUnencodable(char c) {
        return c == '\uFFFD' || c == '\uFFFE' || c == '\uFFFF' || Character.isSurrogate(c);
    }

    /** 非 ASCII、非汉字基本区、非中文/全角标点的字符，乱码片段里的典型杂符号。 */
    private static boolean isWeird(char c) {
        if (c < 0x80) {
            return false;
        }
        if (c >= 0x4E00 && c <= 0x9FFF) {
            return false;
        }
        if (c >= 0x3000 && c <= 0x303F) {
            return false;
        }
        if (c >= 0xFF00 && c <= 0xFFEF) {
            return false;
        }
        if (c >= 0x2000 && c <= 0x206F) {
            return false;
        }
        return true;
    }

    private static int cjkCount(String s) {
        int n = 0;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c >= 0x4E00 && c <= 0x9FFF) {
                n++;
            }
        }
        return n;
    }

    private static int weirdCount(String s) {
        int n = 0;
        for (int i = 0; i < s.length(); i++) {
            if (isWeird(s.charAt(i))) {
                n++;
            }
        }
        return n;
    }

    private static int telltaleCount(String s) {
        int n = 0;
        for (int i = 0; i < s.length(); i++) {
            if (TELLTALE.indexOf(s.charAt(i)) >= 0) {
                n++;
            }
        }
        return n;
    }

    private static int replacementCount(String s) {
        int n = 0;
        for (int i = 0; i < s.length(); i++) {
            if (s.charAt(i) == '\uFFFD') {
                n++;
            }
        }
        return n;
    }

    private static boolean suspiciousStart(char c) {
        return c == '\uFFFD' || TELLTALE.indexOf(c) >= 0 || isWeird(c);
    }

    /** 还原收益：杂字符与特征字减少得越多、汉字越完整，收益越高。 */
    private static int gain(String original, String decoded) {
        int cjk = cjkCount(decoded);
        if (cjk == 0) {
            return Integer.MIN_VALUE;
        }
        return (weirdCount(original) - weirdCount(decoded)) * 5
                + (telltaleCount(original) - telltaleCount(decoded)) * 3
                + (cjk - cjkCount(original))
                - replacementCount(decoded) * 3;
    }

    /** 对一个可编码块做贪心片段替换。 */
    private static String repairBlock(String s) {
        Encoded[] encodings = {encode(s, GBK), encode(s, GB18030)};
        StringBuilder out = new StringBuilder(s.length());
        int n = s.length();
        int i = 0;
        while (i < n) {
            // 只从「疑似乱码字」起头尝试，避免把前面的正常中文一起吞进回编码片段
            // （旧实现整串变换正是这样把「确定性结果不能用于...」毁掉的）。
            if (!suspiciousStart(s.charAt(i))) {
                out.append(s.charAt(i));
                i++;
                continue;
            }
            int limit = Math.min(n, i + MAX_SPAN);
            String best = null;
            int bestEnd = i;
            int bestGain = MIN_GAIN;
            for (Encoded enc : encodings) {
                if (enc == null) {
                    continue;
                }
                for (int j = i + 2; j <= limit; j++) {
                    int from = enc.bounds[i];
                    int len = enc.bounds[j] - from;
                    if (len < 3) {
                        continue;
                    }
                    // 宽松解码：MATLAB 读错时已丢失的字节会变成 U+FFFD，由 gain 惩罚。
                    String decoded = new String(enc.bytes, from, len, StandardCharsets.UTF_8);
                    int g = gain(s.substring(i, j), decoded);
                    if (g > bestGain) {
                        bestGain = g;
                        best = decoded;
                        bestEnd = j;
                    }
                }
            }
            if (best != null) {
                out.append(best);
                i = bestEnd;
            } else {
                out.append(s.charAt(i));
                i++;
            }
        }
        return out.toString();
    }

    /** 把字符串按字符集编码，并记录每个 char 在字节数组中的起始边界。 */
    private static Encoded encode(String s, Charset cs) {
        try {
            CharsetEncoder whole = cs.newEncoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT);
            ByteBuffer bb = whole.encode(CharBuffer.wrap(s));
            byte[] bytes = new byte[bb.remaining()];
            bb.get(bytes);

            int[] bounds = new int[s.length() + 1];
            CharsetEncoder one = cs.newEncoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT);
            int pos = 0;
            for (int i = 0; i < s.length(); i++) {
                bounds[i] = pos;
                one.reset();
                ByteBuffer part = one.encode(CharBuffer.wrap(s.substring(i, i + 1)));
                pos += part.remaining();
            }
            bounds[s.length()] = pos;
            return pos == bytes.length ? new Encoded(bytes, bounds) : null;
        } catch (CharacterCodingException e) {
            return null;
        }
    }

    private static final class Encoded {
        private final byte[] bytes;
        private final int[] bounds;

        private Encoded(byte[] bytes, int[] bounds) {
            this.bytes = bytes;
            this.bounds = bounds;
        }
    }
}
