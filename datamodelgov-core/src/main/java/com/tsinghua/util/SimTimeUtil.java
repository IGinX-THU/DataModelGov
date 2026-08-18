package com.tsinghua.util;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * 仿真时间工具：保证停止时间是固定步长的整数倍。
 * Simulink 以固定步长推进，若 StopTime 不是步长的整数倍，实际停止时刻会落在最近的步长边界上，
 * 前端显示的“停止时间”与真实停止时刻就会对不上，因此在下发仿真前先做对齐。
 */
public final class SimTimeUtil {

    private SimTimeUtil() {
    }

    /** 把停止时间对齐到固定步长的整数倍（至少一个步长） */
    public static double alignToStep(double stopTime, double step) {
        if (step <= 0 || Double.isNaN(step) || Double.isNaN(stopTime)) return stopTime;
        long steps = Math.round(stopTime / step);
        if (steps < 1) steps = 1;
        return BigDecimal.valueOf(step).multiply(BigDecimal.valueOf(steps))
                .setScale(9, RoundingMode.HALF_UP).stripTrailingZeros().doubleValue();
    }

    /** 去掉多余小数位的数字文本，如 30.0 → 30、20.325000 → 20.325 */
    public static String format(double value) {
        return BigDecimal.valueOf(value).setScale(9, RoundingMode.HALF_UP)
                .stripTrailingZeros().toPlainString();
    }

    public static double parse(String text, double fallback) {
        try {
            return Double.parseDouble(text.trim());
        } catch (Exception e) {
            return fallback;
        }
    }
}
