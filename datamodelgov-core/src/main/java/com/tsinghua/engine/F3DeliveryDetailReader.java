package com.tsinghua.engine;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.DataFormatter;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.usermodel.WorkbookFactory;

import java.io.File;
import java.io.InputStream;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * F3 交付 UQ 明细的 Java POI 只读解析器。
 *
 * 背景:F3 R1 稳态交付(3p4_r1_uq_delivery.xlsx,schema=SHT_F34_R1_DELIVERY_V1)与
 * F3 局部D 交付(3p4_method_D_local_delivery.xlsx)的 Manifest 不是 TC24 合同,
 * 送进 dmg_tc24_read(Start_TC24_00_Offline)会被 sht_tc24_result_view 以
 * "Manifest缺少schema_version或route"拒绝。这里直接用 POI 读交付 Excel,
 * 产出与 TC24 UQ 明细(delivery.parameterTable)同构的 JSON,绕开 MATLAB reader。
 *
 * 约束:只读 Excel + 写 detail JSON,不改任何 MATLAB 源码。
 */
public final class F3DeliveryDetailReader {
    private static final double Z95 = 1.959963984540054;
    private static final DataFormatter FMT = new DataFormatter();

    private F3DeliveryDetailReader() {}

    /** 是否 F3 R1 稳态交付(含 ParameterSummary 且列头有 method_c_mean / method_d_map)。 */
    public static boolean isR1Delivery(File excel) {
        return hasHeader(excel, "ParameterSummary", "method_c_mean")
                || hasHeader(excel, "ParameterSummary", "method_d_map");
    }

    /** 是否 F3 局部D 交付(含 LocalDistribution + ParameterDictionary 且前者有 json_text 列)。 */
    public static boolean isLocalDDelivery(File excel) {
        return hasHeader(excel, "LocalDistribution", "json_text")
                && hasSheet(excel, "ParameterDictionary");
    }

    /** 统一入口:按交付类型解析并写出 detail JSON。成功返回 true。 */
    public static boolean read(File excel, File out, StringBuilder errorOut) {
        return read(excel, out, errorOut, null);
    }

    /**
     * @param method 上游 UQ 记录的方法(C/D);为空时从 Manifest/列存在性推断。
     */
    public static boolean read(File excel, File out, StringBuilder errorOut, String method) {
        try {
            if (isLocalDDelivery(excel)) return readLocalD(excel, out, errorOut);
            if (isR1Delivery(excel)) return readR1(excel, out, errorOut, method);
            fail(errorOut, "不是F3 R1/局部D交付Excel(无ParameterSummary.method_c_*且无LocalDistribution)");
            return false;
        } catch (Exception e) {
            fail(errorOut, e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
            return false;
        }
    }

    /** F3 R1:ParameterSummary 的 method_c/method_d 后验列 + x_node 坐标。 */
    private static boolean readR1(File excel, File out, StringBuilder errorOut, String method) throws Exception {
        try (InputStream in = Files.newInputStream(excel.toPath());
             Workbook wb = WorkbookFactory.create(in)) {
            Sheet ps = wb.getSheet("ParameterSummary");
            if (ps == null) { fail(errorOut, "缺少ParameterSummary工作表"); return false; }
            Row hr = ps.getRow(0);
            if (hr == null) { fail(errorOut, "ParameterSummary无表头"); return false; }
            Map<String, Integer> col = headerMap(hr);

            boolean useD = "D".equalsIgnoreCase(method) || "method_d".equalsIgnoreCase(method);
            if (method == null || method.trim().isEmpty()) {
                // 无显式方法时:Manifest 的 parent_posterior_id 含 _D_ 用 D,否则用 C
                String parent = manifestValue(wb, "parent_posterior_id");
                useD = parent != null && (parent.contains("_D_") || parent.toUpperCase().endsWith("_D"));
            }
            String meanKey = useD ? "method_d_map" : "method_c_mean";
            String stdKey = useD ? "method_d_std" : "method_c_std";
            String loKey = useD ? "method_d_q025" : "method_c_q025";
            String hiKey = useD ? "method_d_q975" : "method_c_q975";
            if (!col.containsKey(meanKey)) {
                fail(errorOut, "ParameterSummary缺少" + meanKey + "列");
                return false;
            }

            Map<String, Object> manifest = readManifest(wb);
            List<Map<String, Object>> rows = new ArrayList<>();
            for (int r = 1; r <= ps.getLastRowNum(); r++) {
                Row row = ps.getRow(r);
                if (row == null) continue;
                String name = str(row, col, "name");
                if (name.isEmpty()) continue;
                Map<String, Object> p = new LinkedHashMap<>();
                p.put("name", name);
                p.put("parameter_id", str(row, col, "parameter_id"));
                p.put("groupKind", mapKind(str(row, col, "kind")));
                p.put("coordinate", num(row, col, "x_node"));
                p.put("unit", str(row, col, "unit"));
                p.put("lowerBound", num(row, col, "lower_bound"));
                p.put("upperBound", num(row, col, "upper_bound"));
                // 确定性值=参考中心(theta=0),与 F34 局部D 的 prior_center 语义一致
                p.put("deterministicEstimate", num(row, col, "prior_center"));
                Double m = num(row, col, meanKey);
                p.put("posteriorMean", m);
                p.put("posteriorMedian", m);
                p.put("posteriorStd", num(row, col, stdKey));
                p.put("posteriorQ025", num(row, col, loKey));
                p.put("posteriorQ975", num(row, col, hiKey));
                rows.add(p);
            }
            if (rows.isEmpty()) { fail(errorOut, "ParameterSummary无有效参数行"); return false; }
            writeDetail(out, useD ? "D" : "C", manifest, rows,
                    "F3 R1后验传播交付:均值与q05–q95来自ParameterSummary的method_"
                            + (useD ? "D" : "C") + "后验列;确定性值=参考中心(prior_center)。");
            return true;
        }
    }

    /** F3 局部D:LocalDistribution.json_text 拼接为高斯矩 + ParameterDictionary 参数合同。 */
    private static boolean readLocalD(File excel, File out, StringBuilder errorOut) throws Exception {
        try (InputStream in = Files.newInputStream(excel.toPath());
             Workbook wb = WorkbookFactory.create(in)) {
            Sheet ld = wb.getSheet("LocalDistribution");
            StringBuilder sb = new StringBuilder();
            for (int r = 1; r <= ld.getLastRowNum(); r++) {
                Row row = ld.getRow(r);
                if (row == null) continue;
                Cell c = row.getCell(1);
                if (c != null) sb.append(FMT.formatCellValue(c));
            }
            if (sb.length() == 0) { fail(errorOut, "LocalDistribution.json_text为空"); return false; }
            Map<?, ?> jm = new ObjectMapper().readValue(sb.toString(), Map.class);
            List<?> meanArr = (List<?>) jm.get("jointMean");
            List<?> covArr = (List<?>) jm.get("jointCovariance");
            Object dimObj = jm.get("explicitDimension");
            int n = dimObj == null ? (meanArr == null ? 0 : meanArr.size()) : ((Number) dimObj).intValue();
            if (meanArr == null || covArr == null || n <= 0) {
                fail(errorOut, "LocalDistribution缺jointMean/jointCovariance/explicitDimension");
                return false;
            }

            Sheet pd = wb.getSheet("ParameterDictionary");
            Row hr = pd.getRow(0);
            if (hr == null) { fail(errorOut, "ParameterDictionary无表头"); return false; }
            Map<String, Integer> col = headerMap(hr);
            Map<String, Object> manifest = readManifest(wb);
            List<Map<String, Object>> rows = new ArrayList<>();
            for (int i = 0; i < n; i++) {
                Row row = pd.getRow(i + 1);
                if (row == null) break;
                Double m = ((Number) meanArr.get(i)).doubleValue();
                double sd = 0;
                if (i < covArr.size() && covArr.get(i) instanceof List) {
                    List<?> cr = (List<?>) covArr.get(i);
                    if (i < cr.size() && cr.get(i) instanceof Number) {
                        sd = Math.sqrt(Math.max(((Number) cr.get(i)).doubleValue(), 0));
                    }
                }
                Map<String, Object> p = new LinkedHashMap<>();
                String name = str(row, col, "name");
                p.put("name", name.isEmpty() ? str(row, col, "parameter_id") : name);
                p.put("parameter_id", str(row, col, "parameter_id"));
                p.put("groupKind", mapKind(str(row, col, "kind")));
                p.put("coordinate", num(row, col, "x_node"));
                p.put("unit", str(row, col, "unit"));
                p.put("lowerBound", num(row, col, "lower_bound"));
                p.put("upperBound", num(row, col, "upper_bound"));
                // 确定性值=参考中心(prior_center,theta=0),黑色叉对齐合同中心
                p.put("deterministicEstimate", num(row, col, "prior_center"));
                p.put("posteriorMean", m);
                p.put("posteriorMedian", m);
                p.put("posteriorStd", sd);
                p.put("posteriorQ025", m - Z95 * sd);
                p.put("posteriorQ975", m + Z95 * sd);
                rows.add(p);
            }
            if (rows.isEmpty()) { fail(errorOut, "ParameterDictionary无有效参数行"); return false; }
            String interp = jm.get("intervalInterpretation") == null ? "" : String.valueOf(jm.get("intervalInterpretation"));
            writeDetail(out, "D", manifest, rows,
                    "局部D高斯近似交付:中位数与q05–q95为局部后验(相对参考中心的修正量空间,"
                            + "q05–q95为边缘95%区间±1.96σ);确定性值=合同参考中心(prior_center);"
                            + "完整局部联合矩见交付Excel的LocalDistribution表。" + interp);
            return true;
        }
    }

    /** 写出与 TC24 detail 同构的 JSON(delivery.parameterTable 供 04-15 渲染)。 */
    private static void writeDetail(File out, String method, Map<String, Object> manifest,
                                    List<Map<String, Object>> rows, String note) throws Exception {
        Map<String, Object> root = new LinkedHashMap<>();
        root.put("kind", "uncertainty_delivery");
        Map<String, Object> delivery = new LinkedHashMap<>();
        delivery.put("method", method);
        delivery.put("route", firstStr(manifest, "route_id", "schema_version", "model_route"));
        delivery.put("runId", firstStr(manifest, "run_id", "parent_posterior_id", "sortie_id"));
        delivery.put("manifest", manifest);
        delivery.put("parameterTable", rows);
        root.put("delivery", delivery);
        root.put("message", note);
        new ObjectMapper().writerWithDefaultPrettyPrinter().writeValue(out, root);
    }

    /** F3 kind → 前端 04-15 的 groupKind(页签过滤 + 本次处理列语义)。 */
    private static String mapKind(String kind) {
        if (kind == null) return "constant";
        String k = kind.toLowerCase();
        if (k.contains("fuel_bias")) return "fuel_bias";
        if (k.contains("health_node")) return "health_schedule";
        if (k.contains("sortie_nuisance") || k.contains("nuisance")) return "constant";
        if (k.contains("constant")) return "health_constant";
        return k;
    }

    /**
     * 读 Manifest。交付习惯两种排布:
     *  ① 横向(首行字段名、第二行值,如 F3/F34 交付):schema_version|stage_id|route_id...
     *  ② 纵向(首列字段名、第二列值,如部分 TC24 交付)。
     * 用 "schema_version" 出现的位置判定,避免把表头当数据。
     */
    private static Map<String, Object> readManifest(Workbook wb) {
        Map<String, Object> m = new LinkedHashMap<>();
        Sheet s = wb.getSheet("Manifest");
        if (s == null || s.getRow(0) == null) return m;
        Row hr = s.getRow(0);
        boolean horizontal = false;
        for (int c = 0; c < hr.getLastCellNum(); c++) {
            if ("schema_version".equalsIgnoreCase(strAt(hr, c))) { horizontal = true; break; }
        }
        if (horizontal) {
            Row vr = s.getRow(1);
            for (int c = 0; c < hr.getLastCellNum(); c++) {
                String k = strAt(hr, c);
                if (k.isEmpty()) continue;
                m.put(k, vr == null ? "" : strAt(vr, c));
            }
        } else {
            for (int r = 0; r <= s.getLastRowNum(); r++) {
                Row row = s.getRow(r);
                if (row == null) continue;
                String k = strAt(row, 0);
                if (k.isEmpty()) continue;
                m.put(k, strAt(row, 1));
            }
        }
        return m;
    }

    private static String strAt(Row row, int c) {
        if (row == null) return "";
        Cell cell = row.getCell(c);
        return cell == null ? "" : FMT.formatCellValue(cell).trim();
    }

    private static String manifestValue(Workbook wb, String key) {
        Object v = readManifest(wb).get(key);
        return v == null ? null : String.valueOf(v);
    }

    private static Map<String, Integer> headerMap(Row hr) {
        Map<String, Integer> m = new LinkedHashMap<>();
        for (int c = 0; c < hr.getLastCellNum(); c++) {
            Cell cell = hr.getCell(c);
            if (cell == null) continue;
            String h = FMT.formatCellValue(cell).trim();
            if (!h.isEmpty()) m.put(h, c);
        }
        return m;
    }

    private static boolean hasSheet(File excel, String sheetName) {
        try (InputStream in = Files.newInputStream(excel.toPath());
             Workbook wb = WorkbookFactory.create(in)) {
            return wb.getSheet(sheetName) != null;
        } catch (Exception e) {
            return false;
        }
    }

    private static boolean hasHeader(File excel, String sheetName, String header) {
        try (InputStream in = Files.newInputStream(excel.toPath());
             Workbook wb = WorkbookFactory.create(in)) {
            Sheet s = wb.getSheet(sheetName);
            if (s == null || s.getRow(0) == null) return false;
            return headerMap(s.getRow(0)).containsKey(header);
        } catch (Exception e) {
            return false;
        }
    }

    private static String str(Row row, Map<String, Integer> col, String key) {
        Integer i = col.get(key);
        if (i == null) return "";
        Cell c = row.getCell(i);
        return c == null ? "" : FMT.formatCellValue(c).trim();
    }

    private static Double num(Row row, Map<String, Integer> col, String key) {
        Integer i = col.get(key);
        if (i == null) return null;
        Cell c = row.getCell(i);
        if (c == null) return null;
        String s = FMT.formatCellValue(c).trim();
        if (s.isEmpty() || "-".equals(s)) return null;
        try { return Double.valueOf(s); } catch (NumberFormatException e) { return null; }
    }

    private static String firstStr(Map<String, Object> m, String... keys) {
        for (String k : keys) {
            Object v = m.get(k);
            if (v != null && !String.valueOf(v).isEmpty()) return String.valueOf(v);
        }
        return "";
    }

    private static void fail(StringBuilder errorOut, String msg) {
        if (errorOut != null) errorOut.append(msg);
    }

    /** 便于离线验证:java -cp ... F3DeliveryDetailReader <excel> <out.json> */
    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.out.println("usage: F3DeliveryDetailReader <excel.xlsx> <out.json> [method]");
            return;
        }
        StringBuilder err = new StringBuilder();
        boolean ok = read(new File(args[0]), new File(args[1]), err,
                args.length > 2 ? args[2] : null);
        System.out.println(ok ? "OK -> " + args[1] : "FAIL: " + err);
    }
}
