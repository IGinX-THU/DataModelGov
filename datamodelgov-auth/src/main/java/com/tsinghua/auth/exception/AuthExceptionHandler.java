package com.tsinghua.auth.exception;

import com.tsinghua.model.Result;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.security.access.AccessDeniedException;

/**
 * Auth模块异常处理器
 */
@Slf4j
@RestControllerAdvice
public class AuthExceptionHandler {

    /**
     * 处理自定义权限不足异常
     */
    @ExceptionHandler(InsufficientPermissionException.class)
    public Result<Void> handleInsufficientPermissionException(InsufficientPermissionException e) {
        log.error("权限不足异常 - 用户角色: {}, 缺少权限: {}", 
                e.getUserRole(), e.getRequiredPermissions(), e);
        return Result.authError(e.getMessage());
    }

    /**
     * 处理Spring Security权限不足异常
     */
    @ExceptionHandler(AccessDeniedException.class)
    public Result<Void> handleAccessDeniedException(AccessDeniedException e) {
        log.error("Spring Security权限不足异常", e);
        return Result.authError("权限不足，无法访问该资源。请联系管理员分配相应权限。");
    }

}
