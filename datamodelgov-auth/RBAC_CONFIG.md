# RBAC权限系统配置说明

## 整体架构设计

### 1. 权限控制层次
- **Spring Security**: 负责基础认证和角色级别的访问控制
- **PermissionInterceptor**: 负责细粒度的权限控制（基于@RequirePermission注解）
- **RolePermissionService**: 负责角色权限数据管理

### 2. 角色权限定义

#### 管理员 (ADMIN)
- 拥有所有权限
- Spring Security级别: `hasRole("ADMIN")`
- 业务权限: 所有Permission枚举值

#### 数据工程师 (DATA_ENGINEER)  
- Spring Security级别: 基础认证用户
- 业务权限:
  - 数据源管理: DATASOURCE_REGISTER, DATASOURCE_REMOVE, DATASOURCE_LIST, DATASOURCE_TREE
  - 数据表管理: DATA_QUERY, DATA_IMPORT, DATA_EXPORT, DATA_DELETE, DATA_RELATIONAL_QUERY, DATA_RELATIONAL_COUNT, DATA_RELATIONAL_EXPORT

#### 模型工程师 (MODEL_ENGINEER)
- Spring Security级别: 基础认证用户  
- 业务权限: MODEL_UPLOAD, MODEL_DOWNLOAD, MODEL_QUERY_META, MODEL_SAVE_META, MODEL_HISTORY, MODEL_DELETE

#### 仿真工程师 (SIMULATION_ENGINEER)
- Spring Security级别: 基础认证用户
- 业务权限:
  - 关联规则: ASSOCIATION_RULES_SAVE, ASSOCIATION_RULES_QUERY, ASSOCIATION_RULES_COUNT, ASSOCIATION_RULES_DETAIL, ASSOCIATION_RULES_DELETE
  - 查询权限: DATA_QUERY, DATA_RELATIONAL_QUERY, DATA_RELATIONAL_COUNT, MODEL_QUERY_META, MODEL_HISTORY, DATASOURCE_LIST, DATASOURCE_TREE

## SecurityConfig配置逻辑

### 1. 放行规则 (permitAll)
```java
// 静态资源
.antMatchers("/", "/index.html").permitAll()
.antMatchers("/static/**", "/css/**", "/js/**", "/images/**", "/lib/**", "/components/**", "/config/**").permitAll()

// 页面路由
.antMatchers("/login.html", "/login", "/error", "/favicon.ico").permitAll()

// 认证相关API
.antMatchers("/api/auth/**").permitAll()

// RBAC测试API（用于测试权限系统）
.antMatchers("/api/rbac/**").permitAll()

// 公开测试API
.antMatchers("/api/test/public").permitAll()

// API文档
.antMatchers("/doc.html", "/swagger-ui/**", "/v3/api-docs/**", "/v2/api-docs", "/swagger-resources/**", "/webjars/**").permitAll()

// 健康检查
.antMatchers("/actuator/health", "/actuator/info").permitAll()
```

### 2. 认证要求 (authenticated)
```java
// 受保护的测试API
.antMatchers("/api/test/protected").authenticated()

// 业务API接口（具体权限由拦截器控制）
.antMatchers("/api/datasource/**", "/api/data/**", "/api/model/**", "/api/association/**").authenticated()

// 其他所有接口
.anyRequest().authenticated()
```

### 3. 角色要求 (hasRole)
```java
// 管理员专用测试API
.antMatchers("/api/test/admin").hasRole("ADMIN")

// 管理员专用接口
.antMatchers("/api/admin/**", "/admin/**").hasRole("ADMIN")
```

## 拦截器配置

### PermissionInterceptor拦截范围
```java
.addPathPatterns("/api/datasource/**", "/api/data/**", "/api/model/**", "/api/association/**") // 只拦截需要权限控制的业务API
.excludePathPatterns("/api/auth/**", "/api/rbac/**", "/api/test/**", "/api/admin/**"); // 排除不需要权限拦截的接口
```

### 拦截器工作流程
1. 检查方法或类上的@RequirePermission注解
2. 从Spring Security上下文获取用户信息
3. 通过RolePermissionService验证用户权限
4. 权限验证通过则放行，否则返回403错误

## 测试用户账号

| 用户名 | 密码 | 角色 | 说明 |
|--------|------|------|------|
| admin | admin123 | ADMIN | 系统管理员，拥有所有权限 |
| data_engineer | data123 | DATA_ENGINEER | 数据工程师，管理数据源和数据表 |
| model_engineer | model123 | MODEL_ENGINEER | 模型工程师，管理模型文件 |
| simulation_engineer | sim123 | SIMULATION_ENGINEER | 仿真工程师，管理关联规则 |
| user | user123 | DATA_ENGINEER | 普通用户，默认数据工程师角色 |

## 认证问题排查

### 如果提示用户名密码错误，请检查：

1. **密码编码器配置**: 确认 `SecurityConfig` 中使用的是 `BCryptPasswordEncoder`
2. **用户数据**: 确认 `RolePermissionService.initializeUsers()` 中的密码已加密
3. **密码格式**: 确认 `UserEntity.toUserDetails()` 中使用的是加密后的密码

### 调试步骤：

1. 访问 `/api/auth/test/login-status` 检查认证状态
2. 访问 `/api/auth/test/current-user` 获取当前用户信息
3. 访问 `/api/rbac/users` 查看所有用户配置
4. 检查日志中的错误信息

### 密码安全说明：

- **加密方式**: 使用 BCrypt 加密算法
- **密码存储**: 数据库中存储的是加密后的哈希值
- **密码验证**: Spring Security 自动处理密码验证
- **安全性**: BCrypt 包含盐值，防止彩虹表攻击

### 常见问题：

- **用户名密码错误**: 检查密码编码器配置和用户初始化
- **401未认证**: 检查JWT配置或登录状态
- **403权限不足**: 检查用户角色和权限配置

## API权限映射

### DataSourceController (/api/datasource/**)
- POST /register - @RequirePermission(DATASOURCE_REGISTER)
- POST /remove - @RequirePermission(DATASOURCE_REMOVE)  
- GET /list - @RequirePermission(DATASOURCE_LIST)
- GET /tree - @RequirePermission(DATASOURCE_TREE)

### DataTableController (/api/data/**)
- POST /query - @RequirePermission(DATA_QUERY)
- POST /import - @RequirePermission(DATA_IMPORT)
- POST /export - @RequirePermission(DATA_EXPORT)
- POST /delete - @RequirePermission(DATA_DELETE)
- POST /relational/query - @RequirePermission(DATA_RELATIONAL_QUERY)
- POST /relational/count - @RequirePermission(DATA_RELATIONAL_COUNT)
- POST /relational/export - @RequirePermission(DATA_RELATIONAL_EXPORT)

### ModelFileController (/api/model/**)
- POST /upload - @RequirePermission(MODEL_UPLOAD)
- POST /download - @RequirePermission(MODEL_DOWNLOAD)
- GET /metas - @RequirePermission(MODEL_QUERY_META)
- POST /metas - @RequirePermission(MODEL_SAVE_META)
- GET /history - @RequirePermission(MODEL_HISTORY)
- DELETE /delete - @RequirePermission(MODEL_DELETE)

### AssociationRulesController (/api/association/**)
- POST /rules/save - @RequirePermission(ASSOCIATION_RULES_SAVE)
- POST /rules/query - @RequirePermission(ASSOCIATION_RULES_QUERY)
- POST /rules/count - @RequirePermission(ASSOCIATION_RULES_COUNT)
- GET /rules/detail - @RequirePermission(ASSOCIATION_RULES_DETAIL)
- DELETE /rules/delete - @RequirePermission(ASSOCIATION_RULES_DELETE)

## 测试建议

1. 使用不同角色用户登录测试对应权限
2. 访问RBAC测试API验证权限配置: `/api/rbac/**`
3. 测试无权限访问时的403响应
4. 验证管理员角色的全权限访问
