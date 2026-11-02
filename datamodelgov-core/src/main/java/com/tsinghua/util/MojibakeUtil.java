package com.tsinghua.util;

import java.nio.charset.StandardCharsets;

/** 修复"UTF-8字节被按GBK解码"造成的双重编码乱码。
 *  场景:Owner程序子流程以UTF-8写状态文件,父流程用MATLAB原生GBK编码读回,
 *  错误信息在MATLAB内部即已成乱码并原样抛至Java(如"热平衡物理求解失败"→"姘旂儹骞宠...")。
 *  修复=按GBK回编码还原原始UTF-8字节,再按UTF-8解码。
 *  判据:错乱特征字(锛/姘/鐗/娈/涓/銆)在修复后消失或大幅减少即接受;
 *  不可恢复字节会变成U+FFFD,不能按问号数量比较。 */
public final class MojibakeUtil {

    private MojibakeUtil() {
    }

    public static String repair(String msg) {
        if (msg == null || msg.isEmpty()) return msg;
        boolean suspicious = msg.indexOf('锛') >= 0 || msg.indexOf('姘') >= 0
                || msg.indexOf('鐗') >= 0 || msg.indexOf('娈') >= 0 || msg.indexOf('涓') >= 0;
        if (!suspicious) return msg;
        try {
            byte[] bytes = msg.getBytes("GBK");
            String repaired = new String(bytes, StandardCharsets.UTF_8);
            if (countTelltale(repaired) * 3 <= countTelltale(msg) && hasCjk(repaired)) return repaired;
        } catch (Exception ignore) {
        }
        return msg;
    }

    private static int countTelltale(String s) {
        int n = 0;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '锛' || c == '姘' || c == '鐗' || c == '娈' || c == '涓' || c == '銆') n++;
        }
        return n;
    }

    private static boolean hasCjk(String s) {
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c >= 0x4E00 && c <= 0x9FFF) return true;
        }
        return false;
    }
}
