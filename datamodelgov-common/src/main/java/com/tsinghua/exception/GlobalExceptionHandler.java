package com.tsinghua.exception;

import com.tsinghua.model.Result;
import lombok.extern.slf4j.Slf4j;
import org.springframework.validation.BindException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import javax.validation.ConstraintViolation;
import javax.validation.ConstraintViolationException;
import java.util.Set;

/**
 * 全局异常处理器
 */
@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    /**
     * 处理参数校验异常
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public Result<Void> handleMethodArgumentNotValidException(MethodArgumentNotValidException e) {
        log.error("参数校验异常", e);
        StringBuilder message = new StringBuilder();
        for (FieldError error : e.getBindingResult().getFieldErrors()) {
            message.append(error.getField()).append(": ").append(error.getDefaultMessage()).append("; ");
        }
        return Result.paramError(message.toString());
    }

    /**
     * 处理参数绑定异常
     */
    @ExceptionHandler(BindException.class)
    public Result<Void> handleBindException(BindException e) {
        log.error("参数绑定异常", e);
        StringBuilder message = new StringBuilder();
        for (FieldError error : e.getBindingResult().getFieldErrors()) {
            message.append(error.getField()).append(": ").append(error.getDefaultMessage()).append("; ");
        }
        return Result.paramError(message.toString());
    }

    /**
     * 处理约束违反异常
     */
    @ExceptionHandler(ConstraintViolationException.class)
    public Result<Void> handleConstraintViolationException(ConstraintViolationException e) {
        log.error("约束违反异常", e);
        Set<ConstraintViolation<?>> violations = e.getConstraintViolations();
        StringBuilder message = new StringBuilder();
        for (ConstraintViolation<?> violation : violations) {
            message.append(violation.getMessage()).append("; ");
        }
        return Result.paramError(message.toString());
    }

    /**
     * 处理非法参数异常
     */
    @ExceptionHandler(IllegalArgumentException.class)
    public Result<Void> handleIllegalArgumentException(IllegalArgumentException e) {
        log.error("非法参数异常", e);
        return Result.paramError(e.getMessage());
    }

    /**
     * 处理运行时异常
     */
    @ExceptionHandler(RuntimeException.class)
    public Result<String> handleRuntimeException(RuntimeException e) {
        log.error("运行时异常", e);
        return Result.error("系统运行异常" , e.getMessage());
    }

    /**
     * 处理NoClassDefFoundError异常（特别是POI相关）
     */
    @ExceptionHandler(NoClassDefFoundError.class)
    public Result<String> handleNoClassDefFoundError(NoClassDefFoundError e) {
        log.error("类加载异常", e);
        return Result.error("系统依赖缺失，请联系管理员" , e.getMessage());
    }

    /**
     * 处理AbstractMethodError异常（XML解析器版本冲突）
     */
    @ExceptionHandler(AbstractMethodError.class)
    public Result<String> handleAbstractMethodError(AbstractMethodError e) {
        log.error("XML解析器版本冲突", e);
        return Result.error("XML解析器版本冲突，请检查系统依赖", e.getMessage());
    }

    /**
     * 处理客户端提前断开连接(浏览器刷新/关闭页面/前端请求超时主动abort)。
     * 此时连接已死或响应已提交:禁止再写任何响应体——否则错误JSON会被拼进
     * 已发出的响应之后(浏览器报"Unexpected non-whitespace character after JSON"),
     * 或污染同一条keep-alive连接上的下一个响应。
     * 只记DEBUG日志并返回null(响应已提交,Spring视为已处理)。
     */
    @ExceptionHandler(org.apache.catalina.connector.ClientAbortException.class)
    public Result<Void> handleClientAbort(org.apache.catalina.connector.ClientAbortException e) {
        log.debug("客户端已断开连接,放弃响应: {}", e.getMessage());
        return null;
    }

    /**
     * 处理所有异常
     */
    @ExceptionHandler(Exception.class)
    public Result<String> handleException(Exception e) {
        log.error("系统异常", e);
        return Result.error("系统异常，请联系管理员", e.getMessage());
    }
}
