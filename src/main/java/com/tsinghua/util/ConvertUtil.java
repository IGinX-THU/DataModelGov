package com.tsinghua.util;

import cn.edu.tsinghua.iginx.thrift.DataType;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.BeanUtils;

import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;


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
            byte[] bytes = "".getBytes(StandardCharsets.UTF_8);
            builder.binaryValue(bytes)
                    .dataType(DataType.BINARY);
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

}



