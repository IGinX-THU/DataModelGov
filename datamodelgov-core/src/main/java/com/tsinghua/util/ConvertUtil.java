package com.tsinghua.util;

import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import lombok.extern.slf4j.Slf4j;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 实体与 IGINX 数据点之间的转换工具。
 * 约定:实体的每个字段对应一个 measurement = prefix + "." + 字段名,key 用业务时间戳,
 * 与 SELECT * FROM prefix 的关系型查询方式配套(一个字段一列)。
 */
@Slf4j
public final class ConvertUtil {

    private ConvertUtil() {
    }

    /* ==================== 写入方向 ==================== */

    /** 将实体字段平铺为 IGINX 数据点:measurement=prefix.字段名,key=timestamp,值为字符串化字段值。 */
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
        return Point.builder().measurement(measurement(basePath, fieldName)).key(key).value(value).build();
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
        cn.edu.tsinghua.iginx.session_v2.write.Point.Builder b =
                cn.edu.tsinghua.iginx.session_v2.write.Point.builder().measurement(measurement).key(key);
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
            b.value(value == null ? "" : String.valueOf(value));
        }
        return b.build();
    }

    private static String measurement(String basePath, String fieldName) {
        return basePath + "." + fieldName;
    }

    /* ==================== 读取方向 ==================== */

    /** IGINX SQL 查询结果转行记录列表:每行 Map,key 为完整 measurement 路径。 */
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
                record.put(paths.get(j), normalizeValue(row.get(j)));
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
            log.debug("设置实体字段失败: {}.{} = {}", entity.getClass().getSimpleName(), fieldName, value, e);
        }
    }

    /** DTO 同名字段拷贝到目标实体。 */
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
            log.error("实体转换失败: {} -> {}", source.getClass().getSimpleName(), targetType.getSimpleName(), e);
            return null;
        }
    }

    /* ==================== 通用转换 ==================== */

    /** 数据绑定运算:none/加/减/乘/除,conversionValue 为数值;其余原样返回。 */
    public static Object convertValue(Object value, String operator, String conversionValue) {
        if (value == null || operator == null || "none".equalsIgnoreCase(operator) || operator.trim().isEmpty()) {
            return value;
        }
        double cv;
        try {
            cv = Double.parseDouble(String.valueOf(conversionValue).trim());
        } catch (Exception e) {
            return value;
        }
        try {
            double base = Double.parseDouble(String.valueOf(value).trim());
            double out;
            switch (operator.trim()) {
                case "+":
                case "add":
                case "加":
                    out = base + cv;
                    break;
                case "-":
                case "sub":
                case "减":
                    out = base - cv;
                    break;
                case "*":
                case "mul":
                case "乘":
                    out = base * cv;
                    break;
                case "/":
                case "div":
                case "除":
                    out = cv == 0 ? base : base / cv;
                    break;
                default:
                    return value;
            }
            if (out == Math.floor(out) && !Double.isInfinite(out)) {
                return (long) out;
            }
            return out;
        } catch (Exception e) {
            return value;
        }
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
            log.debug("读取字段失败: {}.{}", entity.getClass().getSimpleName(), field.getName(), e);
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
            log.debug("字段值类型转换失败: {} -> {}", value, type3);
            return null;
        }
        return value;
    }

    private static Object normalizeValue(Object v) {
        return v;
    }
}
