package com.tsinghua.util;

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

}



