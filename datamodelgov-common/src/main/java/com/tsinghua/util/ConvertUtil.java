package com.tsinghua.util;

import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.thrift.DataType;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.BeanUtils;

import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.*;


/**
 * 类型转换: Entity - Vo转换
 * @author songpeijiang
 * @since 2024/4/10
 */
public class ConvertUtil {
    public static final Logger logger = LoggerFactory.getLogger(ConvertUtil.class);

    public static <T> T entityConvert(Object source, Class<T> target) {
        if (source == null) {
            return null;
        }
        T targetObject = null;
        try {
            targetObject = target.newInstance();
            BeanUtils.copyProperties(source, targetObject);
        } catch (Exception e) {
            logger.error("convert error ", e);
        }
        return targetObject;
    }

    public static <T> List<T> entityListConvert(Collection<?> sourceList, Class<T> target) {
        if (sourceList == null) {
            return null;
        }
        List<T> targetList = new ArrayList<>(sourceList.size());

        try {
            for (Object source : sourceList) {
                T targetObject = target.newInstance();
                BeanUtils.copyProperties(source, targetObject);
                targetList.add(targetObject);
            }
        } catch (Exception e) {
            logger.error("convert error ", e);
        }
        return targetList;
    }


    /**
     * 将字符串转换为 UTF-8 编码的字节数组
     * 这是最通用、兼容性最好的编码
     */
    public static byte[] stringToBytes(String str) {
        if (str == null) {
            return new byte[0]; // 或 return null，根据您的业务逻辑
        }
        return str.getBytes(StandardCharsets.UTF_8);
    }

    /**
     * 将字节数组解码为 UTF-8 字符串
     */
    public static String bytesToString(byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            return ""; // 或 return null
        }
        return new String(bytes, StandardCharsets.UTF_8);
    }

    /**
     * 获取到所有字段
     */
    public static List<String> iginxFieldNamesConvert(Class<?> clazz, String prefix) {
        List<String> fieldNames = new ArrayList<>();
        Field[] fields = clazz.getDeclaredFields();

        for (Field field : fields) {
            fieldNames.add(String.format("%s.%s", prefix, field.getName()));
        }

        return fieldNames;
    }

    /**
     * 将实体对象转换为 IGINX Point 列表（反射遍历所有字段）
     * @param entity 实体对象
     * @param prefix IGINX 存储前缀（如 relational_system.workflow_workspace）
     * @param timestamp 时间戳（主键）
     * @return Point 列表
     */
    public static <T> List<Point> entityToPoints(T entity, String prefix, long timestamp) {
        if (entity == null) return new ArrayList<>();
        List<Point> points = new ArrayList<>();
        Field[] fields = entity.getClass().getDeclaredFields();
        for (Field field : fields) {
            field.setAccessible(true);
            try {
                Object value = field.get(entity);
                if (value == null) continue;
                points.add(createFieldPoint(prefix, field.getName(), value, timestamp));
            } catch (IllegalAccessException e) {
                logger.warn("无法访问字段: {}", field.getName(), e);
            }
        }
        return points;
    }

    /**
     * 创建字段数据点 - 通用方法
     * 参考ModelFileService的createFieldPoint方法，提取为公共工具方法
     */
    public static Point createFieldPoint(String basePath, String fieldName, Object value, long timestamp) {
        String measurement = String.format("%s.%s", basePath, fieldName);

        Point.Builder builder = Point.builder()
                .measurement(measurement)
                .key(timestamp);

        // 根据值的类型设置对应的值类型
        if (value == null) {
            return null;
        } else if (value instanceof Boolean) {
            builder.booleanValue((Boolean) value)
                    .dataType(DataType.BOOLEAN);
        } else if (value instanceof Integer) {
            builder.intValue(((Integer) value))
                    .dataType(DataType.INTEGER);
        } else if (value instanceof Long) {
            builder.longValue((Long) value)
                    .dataType(DataType.LONG);
        } else if (value instanceof Float) {
            builder.floatValue(((Float) value))
                    .dataType(DataType.FLOAT);
        } else if (value instanceof Double) {
            builder.doubleValue(((Double) value))
                    .dataType(DataType.DOUBLE);
        } else {
            // 默认转换为字节数组存储
            builder.binaryValue(value.toString().getBytes(StandardCharsets.UTF_8))
                    .dataType(DataType.BINARY);
        }

        return builder.build();
    }

    /**
     * 将记录映射为实体 - 通用方法
     */
    public static <T> T mapToEntity(T entity, Map<String, Object> record, String tablePrefix) {

        // 使用ConvertUtil的通用方法设置字段值 - 参考ModelFileService.queryMeta
        record.forEach((k, v) -> {
            String fieldName = k.replace(tablePrefix + ".", "");
            ConvertUtil.setEntityField(entity, tablePrefix, fieldName, v);
        });

        return entity;
    }
    /**
     * 根据字段名设置实体属性 - 通用方法
     * 参考ModelFileService的setDtoField方法，提取为公共工具方法
     * 需要传入实体类、字段映射前缀、字段名和值
     */
    public static <T> void setEntityField(T entity, String prefix, String fieldName, Object value) {
        try {
            String fullFieldName = prefix + "." + fieldName;
            
            // 使用反射设置字段值
            Field field = null;
            try {
                field = entity.getClass().getDeclaredField(fieldName);
                field.setAccessible(true);
            } catch (NoSuchFieldException e) {
                // 如果实体类中没有该字段，则忽略
                logger.debug("实体类中不存在字段: {}", fieldName);
                return;
            }

            // 根据字段类型设置值
            if (value instanceof byte[]) {
                String stringValue = new String((byte[]) value, StandardCharsets.UTF_8);
                setFieldValue(entity, field, stringValue);
            } else if (value instanceof String) {
                setFieldValue(entity, field, value);
            } else if (value instanceof Boolean) {
                setFieldValue(entity, field, value);
            } else if (value instanceof Long) {
                setFieldValue(entity, field, value);
            } else if (value instanceof Integer) {
                // 根据字段类型转换Integer
                Class<?> fieldType = field.getType();
                if (fieldType == Long.class || fieldType == long.class) {
                    setFieldValue(entity, field, ((Integer) value).longValue());
                } else if (fieldType == Integer.class || fieldType == int.class) {
                    setFieldValue(entity, field, value);
                } else if (fieldType == Boolean.class || fieldType == boolean.class) {
                    setFieldValue(entity, field, ((Integer) value) == 1);
                } else {
                    setFieldValue(entity, field, value.toString());
                }
            } else {
                setFieldValue(entity, field, value.toString());
            }
        } catch (Exception e) {
            logger.warn("设置字段 {} 失败: {}", fieldName, e.getMessage());
        }
    }

    /**
     * 设置字段值的辅助方法
     */
    private static <T> void setFieldValue(T entity, Field field, Object value) throws IllegalAccessException {
        Class<?> fieldType = field.getType();
        
        if (value == null) {
            field.set(entity, null);
            return;
        }
        
        if (fieldType == String.class) {
            field.set(entity, value.toString());
        } else if (fieldType == Boolean.class || fieldType == boolean.class) {
            if (value instanceof Boolean) {
                field.set(entity, value);
            } else if (value instanceof String) {
                field.set(entity, Boolean.valueOf((String) value));
            } else if (value instanceof Integer) {
                field.set(entity, ((Integer) value) == 1);
            }
        } else if (fieldType == Long.class || fieldType == long.class) {
            if (value instanceof Long) {
                field.set(entity, value);
            } else if (value instanceof Integer) {
                field.set(entity, ((Integer) value).longValue());
            } else if (value instanceof String) {
                try {
                    field.set(entity, Long.parseLong((String) value));
                } catch (NumberFormatException e) {
                    logger.warn("无法将字符串 {} 转换为 Long", value);
                }
            }
        } else if (fieldType == Integer.class || fieldType == int.class) {
            if (value instanceof Integer) {
                field.set(entity, value);
            } else if (value instanceof Long) {
                field.set(entity, ((Long) value).intValue());
            } else if (value instanceof String) {
                try {
                    field.set(entity, Integer.parseInt((String) value));
                } catch (NumberFormatException e) {
                    logger.warn("无法将字符串 {} 转换为 Integer", value);
                }
            }
        } else {
            // 其他类型直接toString
            field.set(entity, value.toString());
        }
    }

    /**
     * 单位换算处理
     * 根据运算符和换算值对原始数据进行单位转换
     * 
     * @param value 原始值
     * @param operator 运算符 (multiply, divide, add, subtract)
     * @param conversionValue 换算值
     * @return 转换后的值
     */
    public static Object convertValue(Object value, String operator, String conversionValue) {
        if (value == null || operator == null || conversionValue == null || 
            "none".equals(operator) || conversionValue.trim().isEmpty()) {
            return value;
        }
        
        try {
            double numericValue = ((Number) value).doubleValue();
            double factor = parseConversionValue(conversionValue);
            
            switch (operator.toLowerCase()) {
                case "multiply":
                    return numericValue * factor;
                case "divide":
                    if (factor == 0) {
                        logger.warn("除数不能为0，跳过单位转换");
                        return value;
                    }
                    return numericValue / factor;
                case "add":
                    return numericValue + factor;
                case "subtract":
                    return numericValue - factor;
                default:
                    logger.warn("未知的运算符: {}，跳过单位转换", operator);
                    return value;
            }
        } catch (Exception e) {
            logger.error("单位转换失败: value={}, operator={}, conversionValue={}, error={}", 
                        value, operator, conversionValue, e.getMessage());
            return value;
        }
    }
    
    /**
     * 解析换算值
     * 支持小数、整数和分数格式（如 9/5）
     * 
     * @param value 换算值字符串
     * @return 解析后的数值
     */
    private static double parseConversionValue(String value) {
        if (value == null || value.trim().isEmpty()) {
            return 1.0;
        }
        
        value = value.trim();
        
        // 处理分数格式 (如 9/5)
        if (value.contains("/")) {
            String[] parts = value.split("/");
            if (parts.length == 2) {
                try {
                    double numerator = Double.parseDouble(parts[0].trim());
                    double denominator = Double.parseDouble(parts[1].trim());
                    if (denominator != 0) {
                        return numerator / denominator;
                    }
                } catch (NumberFormatException e) {
                    logger.warn("分数格式解析失败: {}", value);
                }
            }
        }
        
        // 处理普通数值
        try {
            return Double.parseDouble(value);
        } catch (NumberFormatException e) {
            logger.warn("数值格式解析失败: {}", value);
            return 1.0;
        }
    }
    
    /**
     * 批量单位换算
     * 对映射关系中的所有字段进行单位转换
     * 
     * @param mappings 映射关系列表
     * @param data 原始数据
     * @return 转换后的数据
     */
    public static java.util.Map<String, Object> batchConvertValue(
            java.util.List<java.util.Map<String, Object>> mappings, 
            java.util.Map<String, Object> data) {
        
        java.util.Map<String, Object> result = new java.util.HashMap<>(data);
        
        for (java.util.Map<String, Object> mapping : mappings) {
            String sourceField = (String) mapping.get("sourceField");
            String targetField = (String) mapping.get("targetField");
            String operator = (String) mapping.get("operator");
            String conversionValue = (String) mapping.get("conversionValue");
            
            if (sourceField != null && targetField != null && data.containsKey(sourceField)) {
                Object originalValue = data.get(sourceField);
                Object convertedValue = convertValue(originalValue, operator, conversionValue);
                result.put(targetField, convertedValue);
                
                logger.debug("单位转换: {} {} {} = {} -> {}", 
                           sourceField, originalValue, getConversionDescription(operator, conversionValue), 
                           convertedValue, targetField);
            }
        }
        
        return result;
    }
    
    /**
     * 获取转换描述
     * 用于日志显示转换过程
     */
    private static String getConversionDescription(String operator, String conversionValue) {
        if ("none".equals(operator) || conversionValue == null || conversionValue.trim().isEmpty()) {
            return "无转换";
        }
        
        String opSymbol;
        switch (operator.toLowerCase()) {
            case "multiply": opSymbol = "×"; break;
            case "divide": opSymbol = "÷"; break;
            case "add": opSymbol = "+"; break;
            case "subtract": opSymbol = "-"; break;
            default: opSymbol = operator; break;
        }
        
        return String.format("%s %s %s", operator, opSymbol, conversionValue);
    }
    
    /**
     * 验证转换参数
     * 检查运算符和换算值是否有效
     */
    public static boolean validateConversionParams(String operator, String conversionValue) {
        if (operator == null || conversionValue == null) {
            return false;
        }
        
        // 检查运算符
        if (!java.util.Arrays.asList("none", "multiply", "divide", "add", "subtract").contains(operator.toLowerCase())) {
            return false;
        }
        
        // 如果不是无转换，检查换算值
        if (!"none".equals(operator) && conversionValue.trim().isEmpty()) {
            return false;
        }
        
        // 尝试解析换算值
        try {
            parseConversionValue(conversionValue);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * 获取session结果转换
     *
     */
    public static List<Map<String, Object>> getRecords(SessionExecuteSqlResult res) {
        List<String> header = res.getPaths();
        List<Map<String, Object>> records = new ArrayList<>();
        List<List<Object>>  rows = res.getValues();
        rows.forEach(row -> {
            Map<String, Object> rs = new LinkedHashMap<>();
            for (int i=0; i<=header.size() -1; i++){
                Object value = row.get(i);
                if (value instanceof byte[]) {
                    rs.put(header.get(i), new String((byte[]) value, StandardCharsets.UTF_8));
                } else {
                    rs.put(header.get(i), row.get(i));
                }
            }
            records.add(rs);
        });
        return records;
    }

}



