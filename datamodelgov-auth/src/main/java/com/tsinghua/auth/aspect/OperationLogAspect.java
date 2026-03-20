package com.tsinghua.auth.aspect;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsinghua.auth.annotation.OperationLog;
import com.tsinghua.auth.entity.OperationLogEntity;
import lombok.extern.slf4j.Slf4j;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.annotation.Pointcut;
import org.aspectj.lang.reflect.MethodSignature;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import javax.servlet.http.HttpServletRequest;
import java.lang.reflect.Method;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

/**
 * 操作日志记录切面
 * 记录所有Controller接口的操作日志，包含：操作人、IP、时间、接口传参
 */
@Slf4j
@Aspect
@Component
public class OperationLogAspect {

    @Autowired
    private ObjectMapper objectMapper;

    /**
     * 定义切点：所有Controller方法
     */
    @Pointcut("execution(* com.tsinghua..controller..*(..))")
    public void controllerPointcut() {
    }

    /**
     * 定义切点：带有OperationLog注解的方法
     */
    @Pointcut("@annotation(com.tsinghua.auth.annotation.OperationLog)")
    public void operationLogPointcut() {
    }

    /**
     * 环绕通知：记录操作日志
     */
    @Around("controllerPointcut()")
    public Object logOperation(ProceedingJoinPoint joinPoint) throws Throwable {
        long startTime = System.currentTimeMillis();
        
        // 获取请求信息
        ServletRequestAttributes attributes = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
        HttpServletRequest request = attributes != null ? attributes.getRequest() : null;
        
        // 获取方法信息和注解
        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        Method method = signature.getMethod();
        OperationLog operationLogAnnotation = method.getAnnotation(OperationLog.class);
        
        String className = method.getDeclaringClass().getSimpleName();
        String methodName = method.getName();
        
        // 获取操作人
        String operator = getCurrentUser();
        
        // 获取IP地址
        String clientIp = getClientIp(request);
        
        // 获取请求参数
        Map<String, Object> params = getMethodParameters(joinPoint, signature);
        boolean shouldRecordParams = operationLogAnnotation == null || operationLogAnnotation.recordParams();
        boolean shouldRecordResult = operationLogAnnotation == null || operationLogAnnotation.recordResult();
        
        // 构建操作描述
        String description = operationLogAnnotation != null ? operationLogAnnotation.value() : 
                           String.format("执行 %s.%s", className, methodName);
        
        // 构建操作类型
        String operationType = operationLogAnnotation != null ? 
                           operationLogAnnotation.type().name() : "OTHER";
        
        // 构建操作日志实体
        OperationLogEntity logEntity = OperationLogEntity.builder()
                .operator(operator)
                .clientIp(clientIp)
                .description(description)
                .operationType(operationType)
                .method(className + "." + methodName)
                .params(shouldRecordParams ? formatParams(params) : "未记录")
                .operationTime(LocalDateTime.now())
                .userAgent(request != null ? request.getHeader("User-Agent") : "未知")
                .requestUri(request != null ? request.getRequestURI() : "未知")
                .build();
        
        Object result = null;
        Exception exception = null;
        
        try {
            // 执行目标方法
            result = joinPoint.proceed();
            
            // 记录成功日志
            long endTime = System.currentTimeMillis();
            long executionTime = endTime - startTime;
            
            logEntity.setStatus("成功");
            logEntity.setExecutionTime(executionTime);
            logEntity.setResult(shouldRecordResult ? formatResult(result) : "未记录");
            
            log.info("操作日志: {}", logEntity.toString());
            
            return result;
            
        } catch (Exception e) {
            exception = e;
            
            // 记录异常日志
            long endTime = System.currentTimeMillis();
            long executionTime = endTime - startTime;
            
            logEntity.setStatus("失败");
            logEntity.setExecutionTime(executionTime);
            logEntity.setErrorMessage(e.getMessage());
            
            log.info("操作日志: {}", logEntity.toString());
            log.error("操作异常详情", e);
            
            throw e;
        }
    }

    /**
     * 获取当前用户
     */
    private String getCurrentUser() {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication != null && authentication.isAuthenticated()) {
                return authentication.getName();
            }
        } catch (Exception e) {
            log.debug("获取当前用户失败", e);
        }
        return "匿名用户";
    }

    /**
     * 获取客户端IP地址
     */
    private String getClientIp(HttpServletRequest request) {
        if (request == null) {
            return "未知";
        }
        
        try {
            String ip = request.getHeader("X-Forwarded-For");
            if (ip == null || ip.length() == 0 || "unknown".equalsIgnoreCase(ip)) {
                ip = request.getHeader("Proxy-Client-IP");
            }
            if (ip == null || ip.length() == 0 || "unknown".equalsIgnoreCase(ip)) {
                ip = request.getHeader("WL-Proxy-Client-IP");
            }
            if (ip == null || ip.length() == 0 || "unknown".equalsIgnoreCase(ip)) {
                ip = request.getHeader("HTTP_CLIENT_IP");
            }
            if (ip == null || ip.length() == 0 || "unknown".equalsIgnoreCase(ip)) {
                ip = request.getHeader("HTTP_X_FORWARDED_FOR");
            }
            if (ip == null || ip.length() == 0 || "unknown".equalsIgnoreCase(ip)) {
                ip = request.getRemoteAddr();
            }
            
            // 如果是多个IP，取第一个
            if (ip != null && ip.contains(",")) {
                ip = ip.split(",")[0].trim();
            }
            
            return ip != null ? ip : "未知";
        } catch (Exception e) {
            log.debug("获取客户端IP失败", e);
            return "未知";
        }
    }

    /**
     * 获取方法参数
     */
    private Map<String, Object> getMethodParameters(ProceedingJoinPoint joinPoint, MethodSignature signature) {
        Map<String, Object> params = new HashMap<>();
        
        try {
            String[] paramNames = signature.getParameterNames();
            Object[] paramValues = joinPoint.getArgs();
            
            if (paramNames != null && paramValues != null) {
                for (int i = 0; i < paramNames.length; i++) {
                    String paramName = paramNames[i];
                    Object paramValue = paramValues[i];
                    
                    // 过滤敏感参数
                    if (isSensitiveParameter(paramName, paramValue)) {
                        params.put(paramName, "***");
                    } else {
                        params.put(paramName, paramValue);
                    }
                }
            } else {
                // 如果无法获取参数名，使用索引
                Object[] args = joinPoint.getArgs();
                if (args != null) {
                    for (int i = 0; i < args.length; i++) {
                        Object arg = args[i];
                        if (isSensitiveParameter("arg" + i, arg)) {
                            params.put("arg" + i, "***");
                        } else {
                            params.put("arg" + i, arg);
                        }
                    }
                }
            }
        } catch (Exception e) {
            log.debug("获取方法参数失败", e);
            params.put("error", "参数解析失败");
        }
        
        return params;
    }

    /**
     * 判断是否为敏感参数
     */
    private boolean isSensitiveParameter(String paramName, Object paramValue) {
        if (paramName == null) {
            return false;
        }
        
        String lowerParamName = paramName.toLowerCase();
        return lowerParamName.contains("password") ||
               lowerParamName.contains("pwd") ||
               lowerParamName.contains("token") ||
               lowerParamName.contains("secret") ||
               lowerParamName.contains("key") ||
               lowerParamName.contains("credential");
    }

    /**
     * 格式化参数
     */
    private String formatParams(Map<String, Object> params) {
        try {
            return objectMapper.writeValueAsString(params);
        } catch (Exception e) {
            return "参数格式化失败: " + params.toString();
        }
    }

    /**
     * 格式化返回结果
     */
    private String formatResult(Object result) {
        if (result == null) {
            return "null";
        }
        
        try {
            // 限制返回结果的长度，避免日志过长
            String jsonResult = objectMapper.writeValueAsString(result);
            if (jsonResult.length() > 1000) {
                return jsonResult.substring(0, 1000) + "...[截断]";
            }
            return jsonResult;
        } catch (Exception e) {
            return "结果格式化失败: " + result.toString();
        }
    }
}
