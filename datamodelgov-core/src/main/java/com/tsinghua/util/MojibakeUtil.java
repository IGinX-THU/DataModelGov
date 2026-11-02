package com.tsinghua.util;

import java.nio.charset.StandardCharsets;

/** 修复"UTF-8字节被按GBK解码"造成的双重编码乱码。
 *  场景:Owner程序子流程以UTF-8写状态文件,父流程用MATLAB原生GBK编码读回,
 *  错误信息在MATLAB内部即已成乱码并原样抛至Java(如"热平衡物理求解失败"→"姘旂儹骞宠...")。
 *  修复=按GBK回编码还原原始UTF-8字节,再按UTF-8解码;仅当替换符减少且恢复出中文才替换。 */
public final class MojibakeUtil {

    private MojibakeUtil() {
    }

    public static String repair(String msg) {
        if (msg == null || msg.isEmpty()) return msg;
        // 典型错乱字符抽样("锛"=全角标点错乱、"姘"="热"首字节、"涓"/"鐗"/"娈"高频错乱字)
        boolean suspicious = msg.indexOf('锛') >= 0 || msg.indexOf('姘') >= 0
                || msg.indexOf('鐗') >= 0 || msg.indexOf('娈') >= 0 || msg.indexOf('涓') >= 0;
        if (!suspicious) return msg;
        try {
            byte[] bytes = msg.getBytes("GBK");
            String repaired = new String(bytes, StandardCharsets.UTF_8);
            if (countBad(repaired) < countBad(msg) && hasCjk(repaired)) return repaired;
        } catch (Exception ignore) {
        }
        return msg;
    }

    private static int countBad(String s) {
        int n = 0;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '?' || c == '\ufffd') n++;
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
