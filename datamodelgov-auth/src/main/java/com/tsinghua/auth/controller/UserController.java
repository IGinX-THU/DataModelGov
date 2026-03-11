package com.tsinghua.auth.controller;

import com.tsinghua.auth.entity.UserEntity;
import com.tsinghua.auth.entity.RoleEntity;
import com.tsinghua.auth.service.RolePermissionService;
import com.tsinghua.model.Result;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.dto.UserQueryRequest;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.HashMap;
import java.util.Map;

@Api(tags = "用户管理")
@RestController
@RequestMapping("/api/user")
public class UserController {

    @Autowired
    private RolePermissionService rolePermissionService;

    @ApiOperation("创建用户")
    @PostMapping("/save")
    @RequirePermission(Permission.USER_CREATE)
    public Result<Void> saveUser(@RequestBody UserEntity user) throws Exception {
        // 检查用户名是否已存在
        UserEntity existingUser = rolePermissionService.getUser(user.getUsername());
        if (existingUser != null) {
            return Result.error("用户已存在");
        }
        
        rolePermissionService.addUser(user);
        return Result.success("用户创建成功");
    }

    @ApiOperation("分页查询用户")
    @PostMapping("/query")
    @RequirePermission(Permission.USER_READ)
    public Result<List<UserEntity>> queryUsers(@RequestBody UserQueryRequest request) {
        // 调用服务层方法进行筛选查询
        List<UserEntity> users = rolePermissionService.queryUsers(
            request.getUsername(), 
            request.getRole(), 
            request.getEnabled(), 
            request.getPage(), 
            request.getPageSize()
        );
        return Result.success(users);
    }

    @ApiOperation("查询用户总数")
    @PostMapping("/count")
    @RequirePermission(Permission.USER_READ)
    public Result<Object> countUsers(@RequestBody UserQueryRequest request) {
        // 调用服务层方法进行筛选查询总数
        List<UserEntity> users = rolePermissionService.queryUsers(
            request.getUsername(), 
            request.getRole(), 
            request.getEnabled(), 
            null, 
            null
        );
        Map<String, Object> result = new HashMap<>();
        result.put("count", users.size());
        return Result.success(result);
    }

    @ApiOperation("用户详情")
    @GetMapping("/detail")
    @RequirePermission(Permission.USER_READ)
    public Result<?> queryUser(@RequestParam("username") String username) {
        UserEntity user = rolePermissionService.getUser(username);
        if (user == null) {
            return Result.error("未找到指定用户");
        }
        return Result.success(user);
    }

    @ApiOperation("删除用户")
    @DeleteMapping("/delete")
    @RequirePermission(Permission.USER_DELETE)
    public Result<Void> deleteUser(@RequestParam("username") String username) throws Exception {
        rolePermissionService.removeUser(username);
        return Result.success("操作成功");
    }

    @ApiOperation("更新用户")
    @PostMapping("/update")
    @RequirePermission(Permission.USER_UPDATE)
    public Result<Void> updateUser(@RequestBody UserEntity user) throws Exception {
        rolePermissionService.updateUser(user);
        return Result.success("用户更新成功");
    }

    @ApiOperation("获取所有角色")
    @GetMapping("/roles")
    @RequirePermission(Permission.USER_READ)
    public Result<List<RoleEntity>> getRoles() {
        List<RoleEntity> roles = rolePermissionService.getAllRoles();
        return Result.success(roles);
    }

    @ApiOperation("修改密码")
    @PostMapping("/change-password")
    public Result<Void> changePassword(@RequestBody Map<String, String> request) {
        String username = request.get("username");
        String oldPassword = request.get("oldPassword");
        String newPassword = request.get("newPassword");
        
        boolean success = rolePermissionService.changePassword(username, oldPassword, newPassword);
        if (success) {
            return Result.success("密码修改成功");
        } else {
            return Result.error("密码修改失败，请检查原密码是否正确");
        }
    }

    @ApiOperation("获取当前用户信息")
    @GetMapping("/current")
    public Result<UserEntity> getCurrentUser() {
        // 从Spring Security Context获取当前用户名
        String username = getCurrentUsername();
        UserEntity user = rolePermissionService.getUser(username);
        return Result.success(user);
    }

    private String getCurrentUsername() {
        // 从Spring Security Context获取当前认证用户
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null && authentication.isAuthenticated()) {
            return authentication.getName();
        }
        return "LUDNS"; // 降级处理，默认返回LUDNS
    }
}
