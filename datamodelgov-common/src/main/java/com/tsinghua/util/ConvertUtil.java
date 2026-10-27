package com.tsinghua.util;

import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 实体与 IGINX 数据点之间的转换工具(全项目唯一副本,位于 common 供 auth/core 共用)。
 * 约定:实体的每个字段对应一个 measurement = prefix + "." + 字段名,key 用业务时间戳,
 * 与 SELECT * FROM prefix 的关系型查询方式配套(一个字段一列)。
 */
public final class ConvertUtil {

    private static final Logger logger = LoggerFactory.getLogger(ConvertUtil.class);

    private ConvertUtil() {
    }

    /* ==================== 写入方向 ==================== */

    /** 将实体字段平铺为 IGINX 数据点:measurement=prefix.字段名,key=timestamp,跳过 null 字段。 */
    public static List<Point> entityToPoints(Object entity, String prefix, Long timestamp) {
        List<Point> points = new ArrayList<>();
        if (entity == null || timestamp == null) {
            return points;
        }
        long key = timestamp;
        for (Field field : collectFields(entity.getClass())) {
            Object value = readField(entity, field);
            if (value == null) {
                continue;
            }
            points.add(createFieldPoint(prefix, field.getName(), value, key));
        }
        return points;
    }

    /** 实体字段对应的 measurement 名清单(prefix.字段名)。 */
    public static List<String> iginxFieldNamesConvert(Class<?> clazz, String prefix) {
        List<String> names = new ArrayList<>();
        for (Field field : collectFields(clazz)) {
            names.add(prefix + "." + field.getName());
        }
        return names;
    }

    public static Point createFieldPoint(String basePath, String fieldName, String value, long key) {
        // IginX 无 STRING 类型:字符串统一按 BINARY 存储与读侧 byte[]→UTF-8 解码约定一致;
        // session_v2 的 value(Object) 不设置 dataType,直接 build 会抛 dataType NPE
        return Point.builder().measurement(measurement(basePath, fieldName)).key(key)
                .binaryValue(value == null ? new byte[0] : value.getBytes(StandardCharsets.UTF_8)).build();
    }

    public static Point createFieldPoint(String basePath, String fieldName, Long value, long key) {
        return Point.builder().measurement(measurement(basePath, fieldName)).key(key).longValue(value == null ? 0L : value).build();
    }

    public static Point createFieldPoint(String basePath, String fieldName, Integer value, long key) {
        return Point.builder().measurement(measurement(basePath, fieldName)).key(key).intValue(value == null ? 0 : value).build();
    }

    public static Point createFieldPoint(String basePath, String fieldName, long value, long key) {
        return Point.builder().measurement(measurement(basePath, fieldName)).key(key).longValue(value).build();
    }

    public static Point createFieldPoint(String basePath, String fieldName, Boolean value, long key) {
        return Point.builder().measurement(measurement(basePath, fieldName)).key(key).booleanValue(value != null && value).build();
    }

    public static Point createFieldPoint(String basePath, String fieldName, Object value, long key) {
        return buildObjectPoint(measurement(basePath, fieldName), key, value);
    }

    private static Point buildObjectPoint(String measurement, long key, Object value) {
        Point.Builder b = Point.builder().measurement(measurement).key(key);
        if (value instanceof byte[]) {
            b.binaryValue((byte[]) value);
        } else if (value instanceof Integer) {
            b.intValue((Integer) value);
        } else if (value instanceof Long) {
            b.longValue((Long) value);
        } else if (value instanceof Boolean) {
            b.booleanValue((Boolean) value);
        } else if (value instanceof Float) {
            b.floatValue((Float) value);
        } else if (value instanceof Double) {
            b.doubleValue((Double) value);
        } else {
            // 默认转 BINARY 字节存储(IginX 无 STRING;value(Object) 不设置 dataType)
            Object safe = value == null ? "" : value;
            b.binaryValue(String.valueOf(safe).getBytes(StandardCharsets.UTF_8));
        }
        return b.build();
    }

    private static String measurement(String basePath, String fieldName) {
        return basePath + "." + fieldName;
    }

    /* ==================== 读取方向 ==================== */

    /**
     * IGINX SQL 查询结果转行记录列表:每行 Map,key 为完整 measurement 路径。
     * 注意:值保持原始类型(byte[] 不转换)——多处调用方按 byte[] 强转后再自行解码。
     */
    public static List<Map<String, Object>> getRecords(SessionExecuteSqlResult res) {
        List<Map<String, Object>> records = new ArrayList<>();
        if (res == null) {
            return records;
        }
        List<String> paths = res.getPaths();
        List<List<Object>> rows = res.getValues();
        if (paths == null || rows == null) {
            return records;
        }
        for (List<Object> row : rows) {
            Map<String, Object> record = new LinkedHashMap<>();
            for (int j = 0; j < paths.size() && j < row.size(); j++) {
                record.put(paths.get(j), row.get(j));
            }
            records.add(record);
        }
        return records;
    }

    /** 用查询结果的一行填充实体:列名去掉 prefix. 前缀后按字段名反射赋值。 */
    public static <T> T mapToEntity(T entity, Map<String, Object> row, String prefix) {
        if (entity == null || row == null) {
            return entity;
        }
        String dotPrefix = prefix == null ? "" : prefix + ".";
        Map<String, Object> fields = new LinkedHashMap<>();
        for (Map.Entry<String, Object> e : row.entrySet()) {
            String key = e.getKey();
            String fieldName = key != null && key.startsWith(dotPrefix) ? key.substring(dotPrefix.length()) : key;
            fields.put(fieldName, e.getValue());
        }
        for (Field field : collectFields(entity.getClass())) {
            if (!fields.containsKey(field.getName())) {
                continue;
            }
            setEntityField(entity, prefix, field.getName(), fields.get(field.getName()));
        }
        return entity;
    }

    /** 反射设置实体字段:byte[] 转 UTF-8 字符串,数值/布尔做基本类型适配。 */
    public static void setEntityField(Object entity, String prefix, String fieldName, Object value) {
        try {
            Field field = findField(entity.getClass(), fieldName);
            if (field == null) {
                return;
            }
            field.setAccessible(true);
            Object converted = coerce(value, field.getType());
            if (converted != null || !field.getType().isPrimitive()) {
                field.set(entity, converted);
            }
        } catch (Exception e) {
            logger.debug("设置实体字段失败: {}.{} = {}", entity.getClass().getSimpleName(), fieldName, value, e);
        }
    }

    /** DTO 同名字段拷贝到目标实体(含基本类型适配)。 */
    public static <T> T entityConvert(Object source, Class<T> targetType) {
        if (source == null) {
            return null;
        }
        try {
            T target = targetType.newInstance();
            Map<String, Field> targetFields = new LinkedHashMap<>();
            for (Field f : collectFields(targetType)) {
                targetFields.put(f.getName(), f);
            }
            for (Field sf : collectFields(source.getClass())) {
                Field tf = targetFields.get(sf.getName());
                if (tf == null) {
                    continue;
                }
                Object value = readField(source, sf);
                if (value == null) {
                    continue;
                }
                Object converted = coerce(value, tf.getType());
                if (converted != null || !tf.getType().isPrimitive()) {
                    tf.setAccessible(true);
                    tf.set(target, converted);
                }
            }
            return target;
        } catch (Exception e) {
            logger.error("实体转换失败: {} -> {}", source.getClass().getSimpleName(), targetType.getSimpleName(), e);
            return null;
        }
    }

    /** 实体列表批量转换。 */
    public static <T> List<T> entityListConvert(Collection<?> sourceList, Class<T> targetType) {
        List<T> targetList = new ArrayList<>();
        if (sourceList == null) {
            return targetList;
        }
        for (Object source : sourceList) {
            T target = entityConvert(source, targetType);
            if (target != null) {
                targetList.add(target);
            }
        }
        return targetList;
    }

    /* ==================== 通用转换 ==================== */

    /**
     * 数据绑定运算:none/加/减/乘/除,conversionValue 为数值或分数(如 9/5);其余原样返回。
     * 兼容两套运算符写法:multiply/divide/add/subtract、mul/div/sub、+ - * /、加减乘除。
     * 整数值收敛为 Long 返回。
     */
    public static Object convertValue(Object value, String operator, String conversionValue) {
        if (value == null || operator == null || "none".equalsIgnoreCase(operator) || operator.trim().isEmpty()) {
            return value;
        }
        double cv;
        try {
            cv = parseConversionValue(conversionValue);
        } catch (Exception e) {
            return value;
        }
        String op = operator.trim().toLowerCase();
        boolean isAdd = op.equals("+") || op.equals("add") || op.equals("加");
        boolean isSub = op.equals("-") || op.equals("sub") || op.equals("subtract") || op.equals("减");
        boolean isMul = op.equals("*") || op.equals("mul") || op.equals("multiply") || op.equals("乘");
        boolean isDiv = op.equals("/") || op.equals("div") || op.equals("divide") || op.equals("除");
        if (!isAdd && !isSub && !isMul && !isDiv) {
            return value;
        }
        try {
            double base = Double.parseDouble(String.valueOf(value).trim());
            double out;
            if (isAdd) {
                out = base + cv;
            } else if (isSub) {
                out = base - cv;
            } else if (isMul) {
                out = base * cv;
            } else {
                out = cv == 0 ? base : base / cv;
            }
            if (out == Math.floor(out) && !Double.isInfinite(out)) {
                return (long) out;
            }
            return out;
        } catch (Exception e) {
            return value;
        }
    }

    /**
     * 解析换算值:支持小数、整数和分数格式(如 9/5)。
     */
    public static double parseConversionValue(String value) {
        if (value == null || value.trim().isEmpty()) {
            return 1.0;
        }
        value = value.trim();
        if (value.contains("/")) {
            String[] parts = value.split("/");
            if (parts.length == 2) {
                double numerator = Double.parseDouble(parts[0].trim());
                double denominator = Double.parseDouble(parts[1].trim());
                if (denominator != 0) {
                    return numerator / denominator;
                }
            }
        }
        return Double.parseDouble(value);
    }

    /** 批量单位换算:对映射关系中的所有字段进行单位转换。 */
    public static Map<String, Object> batchConvertValue(List<Map<String, Object>> mappings, Map<String, Object> data) {
        Map<String, Object> result = new LinkedHashMap<>(data);
        for (Map<String, Object> mapping : mappings) {
            String sourceField = (String) mapping.get("sourceField");
            String targetField = (String) mapping.get("targetField");
            String operator = (String) mapping.get("operator");
            String conversionValue = (String) mapping.get("conversionValue");
            if (sourceField != null && targetField != null && data.containsKey(sourceField)) {
                result.put(targetField, convertValue(data.get(sourceField), operator, conversionValue));
            }
        }
        return result;
    }

    /** 验证转换参数:运算符与换算值是否有效。 */
    public static boolean validateConversionParams(String operator, String conversionValue) {
        if (operator == null || conversionValue == null) {
            return false;
        }
        String op = operator.trim().toLowerCase();
        boolean known = op.equals("none") || op.equals("+") || op.equals("add") || op.equals("加")
                || op.equals("-") || op.equals("sub") || op.equals("subtract") || op.equals("减")
                || op.equals("*") || op.equals("mul") || op.equals("multiply") || op.equals("乘")
                || op.equals("/") || op.equals("div") || op.equals("divide") || op.equals("除");
        if (!known) {
            return false;
        }
        if ("none".equals(op)) {
            return true;
        }
        try {
            parseConversionValue(conversionValue);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /** 字符串转 UTF-8 字节数组。 */
    public static byte[] stringToBytes(String str) {
        if (str == null) {
            return new byte[0];
        }
        return str.getBytes(StandardCharsets.UTF_8);
    }

    /** 文件分片字节合并为 UTF-8 字符串。 */
    public static String bytesToString(byte[] bytes) {
        if (bytes == null) {
            return "";
        }
        return new String(bytes, StandardCharsets.UTF_8);
    }

    /* ==================== 反射辅助 ==================== */

    private static List<Field> collectFields(Class<?> clazz) {
        List<Field> fields = new ArrayList<>();
        for (Class<?> c = clazz; c != null && c != Object.class; c = c.getSuperclass()) {
            for (Field f : c.getDeclaredFields()) {
                if (Modifier.isStatic(f.getModifiers())) continue;
                fields.add(f);
            }
        }
        return fields;
    }

    private static Field findField(Class<?> clazz, String name) {
        for (Class<?> c = clazz; c != null && c != Object.class; c = c.getSuperclass()) {
            try {
                return c.getDeclaredField(name);
            } catch (NoSuchFieldException ignored) {
            }
        }
        return null;
    }

    private static Object readField(Object entity, Field field) {
        try {
            field.setAccessible(true);
            return field.get(entity);
        } catch (Exception e) {
            logger.debug("读取字段失败: {}.{}", entity.getClass().getSimpleName(), field.getName(), e);
            return null;
        }
    }

    private static Object coerce(Object value, Class<?> type) {
        if (value == null) {
            return null;
        }
        if (value instanceof byte[]) {
            value = bytesToString((byte[]) value);
        }
        String type3 = type.getSimpleName();
        try {
            if (type == String.class) {
                if (value instanceof Double || value instanceof Float) {
                    double d = ((Number) value).doubleValue();
                    return d == Math.floor(d) && !Double.isInfinite(d) ? String.valueOf((long) d) : String.valueOf(d);
                }
                return String.valueOf(value);
            }
            if (type == Integer.class || type3.equals("int")) {
                return value instanceof Number ? ((Number) value).intValue() : Integer.parseInt(String.valueOf(value).trim());
            }
            if (type == Long.class || type3.equals("long")) {
                return value instanceof Number ? ((Number) value).longValue() : Long.parseLong(String.valueOf(value).trim());
            }
            if (type == Double.class || type3.equals("double")) {
                return value instanceof Number ? ((Number) value).doubleValue() : Double.parseDouble(String.valueOf(value).trim());
            }
            if (type == Float.class || type3.equals("float")) {
                return value instanceof Number ? ((Number) value).floatValue() : Float.parseFloat(String.valueOf(value).trim());
            }
            if (type == Boolean.class || type3.equals("boolean")) {
                if (value instanceof Boolean) return value;
                String s = String.valueOf(value).trim();
                return "true".equalsIgnoreCase(s) || "1".equals(s);
            }
        } catch (Exception e) {
            logger.debug("字段值类型转换失败: {} -> {}", value, type3);
            return null;
        }
        return value;
    }
}
