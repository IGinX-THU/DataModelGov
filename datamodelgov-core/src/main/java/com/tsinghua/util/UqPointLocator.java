package com.tsinghua.util;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 用工况坐标反查稳态点号。
 *
 * <p>TC27 的 UQ 点级失败消息来自 {@code q.messages}（只拼 {@code stopReason}/{@code failure.message}），
 * 不含 {@code point_id}，所以日志里只知道「某个稳态点气热平衡不收敛」，不知道是哪个点。
 * 而热参考间隙表的越界告警带有查询坐标（PT 给 Np+负载，HPC/GT 给 Ng），
 * 本次运行的稳态均值表（{@code *_steady_means.xlsx}，含 point_id/Np_mean/Ng_mean）就在输出目录里。
 *
 * <p>因此这里只在 Java 侧做一次「坐标 → 点号」的最近邻匹配，属于纯读操作，不改变 MATLAB 行为。
 * 匹配是启发式的：只在相对误差足够小时才给出结果，并标注"疑似"，绝不把猜测当结论。
 */
public final class UqPointLocator {

    private UqPointLocator() {
    }

    /** 相对误差阈值：修正后的查询坐标与均值表原始值之间允许的偏差。 */
    private static final double REL_TOL = 5e-3;

    /**
     * @param root     任务工作目录（内部会找最新的 *_steady_means.xlsx）
     * @param warnings 诊断里的 outOfRange 列表（可为 null）
     * @return 最多 3 个疑似点，每项含 pointId / np / ng / matchScore / relativeError
     */
    public static List<Map<String, Object>> locate(File root, List<?> warnings) {
        if (root == null || warnings == null || warnings.isEmpty()) {
            return Collections.emptyList();
        }
        List<double[]> queries = new ArrayList<>();
        List<String> kinds = new ArrayList<>();
        for (Object o : warnings) {
            if (!(o instanceof Map)) {
                continue;
            }
            Map<?, ?> m = (Map<?, ?>) o;
            Object comp = m.get("component");
            Object spd = m.get("querySpeedRpm");
            if (spd == null) {
                continue;
            }
            double v = toDouble(spd);
            if (Double.isNaN(v)) {
                continue;
            }
            // PT 的查询坐标是 Np；HPC/GT 是 Ng
            kinds.add("PT".equals(String.valueOf(comp)) ? "Np" : "Ng");
            queries.add(new double[]{v});
        }
        if (queries.isEmpty()) {
            return Collections.emptyList();
        }

        File book = newestSteadyMeans(root, 5);
        if (book == null) {
            return Collections.emptyList();
        }
        List<Map<String, Object>> rows = readPoints(book);
        if (rows.isEmpty()) {
            return Collections.emptyList();
        }

        List<Map<String, Object>> scored = new ArrayList<>();
        for (Map<String, Object> row : rows) {
            int hits = 0;
            double totalRel = 0;
            boolean usable = true;
            for (int i = 0; i < queries.size(); i++) {
                Object val = row.get("Np".equals(kinds.get(i)) ? "np" : "ng");
                double actual = toDouble(val);
                if (Double.isNaN(actual)) {
                    usable = false;
                    break;
                }
                double q = queries.get(i)[0];
                double rel = Math.abs(actual - q) / Math.max(1.0, Math.abs(q));
                if (rel <= REL_TOL) {
                    hits++;
                    totalRel += rel;
                }
            }
            if (!usable || hits == 0) {
                continue;
            }
            Map<String, Object> item = new LinkedHashMap<>(row);
            item.put("matchScore", hits);
            item.put("relativeError", totalRel);
            scored.add(item);
        }
        if (scored.isEmpty()) {
            return Collections.emptyList();
        }
        scored.sort((a, b) -> {
            int c = Integer.compare((Integer) b.get("matchScore"), (Integer) a.get("matchScore"));
            if (c != 0) {
                return c;
            }
            return Double.compare((Double) a.get("relativeError"), (Double) b.get("relativeError"));
        });
        // 只保留「能解释最多条越界告警」的那一档，避免把弱匹配混进来
        int best = (Integer) scored.get(0).get("matchScore");
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> item : scored) {
            if ((Integer) item.get("matchScore") < best || out.size() >= 3) {
                break;
            }
            out.add(item);
        }
        return out;
    }

    /** 在任务目录内找最新的稳态均值表（准备阶段写出的 tc27_*_steady_means.xlsx 等）。 */
    private static File newestSteadyMeans(File dir, int depth) {
        File best = null;
        File[] kids = dir.listFiles();
        if (kids == null) {
            return null;
        }
        for (File f : kids) {
            if (f.isDirectory()) {
                if (depth > 1) {
                    File sub = newestSteadyMeans(f, depth - 1);
                    if (sub != null && (best == null || sub.lastModified() > best.lastModified())) {
                        best = sub;
                    }
                }
                continue;
            }
            String n = f.getName().toLowerCase();
            if (n.endsWith(".xlsx") && n.contains("steady_means")
                    && (best == null || f.lastModified() > best.lastModified())) {
                best = f;
            }
        }
        return best;
    }

    /** 读取 point_id / Np_mean / Ng_mean 三列；表头位置与列顺序都不固定，按名字找。 */
    private static List<Map<String, Object>> readPoints(File file) {
        List<Map<String, Object>> out = new ArrayList<>();
        try (InputStream in = new FileInputStream(file);
             org.apache.poi.ss.usermodel.Workbook wb = org.apache.poi.ss.usermodel.WorkbookFactory.create(in)) {
            org.apache.poi.ss.usermodel.DataFormatter fmt = new org.apache.poi.ss.usermodel.DataFormatter();
            for (int s = 0; s < wb.getNumberOfSheets(); s++) {
                org.apache.poi.ss.usermodel.Sheet sheet = wb.getSheetAt(s);
                if (sheet == null) {
                    continue;
                }
                int headerRow = -1;
                int cId = -1, cNp = -1, cNg = -1;
                for (int r = 0; r <= Math.min(5, sheet.getLastRowNum()) && headerRow < 0; r++) {
                    org.apache.poi.ss.usermodel.Row hr = sheet.getRow(r);
                    if (hr == null) {
                        continue;
                    }
                    int id = -1, np = -1, ng = -1;
                    for (int c = 0; c < hr.getLastCellNum(); c++) {
                        String t = cellText(hr.getCell(c), fmt).trim();
                        if (t.isEmpty()) {
                            continue;
                        }
                        String low = t.toLowerCase();
                        if (id < 0 && low.contains("point_id")) {
                            id = c;
                        } else if (np < 0 && low.contains("np")) {
                            np = c;
                        } else if (ng < 0 && low.contains("ng")) {
                            ng = c;
                        }
                    }
                    if (id >= 0 && np >= 0 && ng >= 0) {
                        headerRow = r;
                        cId = id;
                        cNp = np;
                        cNg = ng;
                    }
                }
                if (headerRow < 0) {
                    continue;
                }
                for (int r = headerRow + 1; r <= sheet.getLastRowNum(); r++) {
                    org.apache.poi.ss.usermodel.Row row = sheet.getRow(r);
                    if (row == null) {
                        continue;
                    }
                    String pid = cellText(row.getCell(cId), fmt).trim();
                    double np = toDouble(cellText(row.getCell(cNp), fmt));
                    double ng = toDouble(cellText(row.getCell(cNg), fmt));
                    if (pid.isEmpty() || Double.isNaN(np) || Double.isNaN(ng)) {
                        continue;
                    }
                    Map<String, Object> item = new LinkedHashMap<>();
                    item.put("pointId", pid);
                    item.put("np", np);
                    item.put("ng", ng);
                    out.add(item);
                }
                break; // 命中一张表即可
            }
        } catch (Exception e) {
            return Collections.emptyList();
        }
        return out;
    }

    private static String cellText(org.apache.poi.ss.usermodel.Cell cell,
                                   org.apache.poi.ss.usermodel.DataFormatter fmt) {
        if (cell == null) {
            return "";
        }
        try {
            return fmt.formatCellValue(cell);
        } catch (Exception e) {
            return "";
        }
    }

    private static double toDouble(Object o) {
        if (o == null) {
            return Double.NaN;
        }
        if (o instanceof Number) {
            return ((Number) o).doubleValue();
        }
        try {
            return Double.parseDouble(String.valueOf(o).trim());
        } catch (Exception e) {
            return Double.NaN;
        }
    }
}
