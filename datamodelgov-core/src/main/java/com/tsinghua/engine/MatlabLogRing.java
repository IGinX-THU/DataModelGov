package com.tsinghua.engine;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

/**
 * 全局MATLAB日志环(进程级):接入层各服务(TC24/AFO/预测)的日志行统一入环,
 * 供工作台底部状态栏滚动显示最近MATLAB活动(与旧版程序运行页footer-log一致)。
 */
public final class MatlabLogRing {

    private static final int CAPACITY = 300;
    private static final Deque<String> RING = new ArrayDeque<>();

    private MatlabLogRing() { }

    public static synchronized void append(String line) {
        if (line == null || line.isEmpty()) return;
        String ts = new java.text.SimpleDateFormat("HH:mm:ss").format(new java.util.Date());
        RING.addLast("[" + ts + "] " + line);
        while (RING.size() > CAPACITY) RING.pollFirst();
    }

    /** 最近n行(旧→新);n<=0返回空。 */
    public static synchronized List<String> tail(int n) {
        List<String> out = new ArrayList<>();
        if (n <= 0) return out;
        for (String s : RING) {
            out.add(s);
        }
        return out.size() > n ? new ArrayList<>(out.subList(out.size() - n, out.size())) : out;
    }
}
