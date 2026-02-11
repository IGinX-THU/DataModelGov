/**
 * 应用全局配置文件
 * 前后端分离配置
 */
window.AppConfig = {
    // API基础配置
    api: {
        baseURL: 'http://localhost:8080', // 可配置的API域名
        timeout: 10000,
        headers: {
            'Content-Type': 'application/json'
        }
    },
    
    // 认证配置
    auth: {
        tokenKey: 'app_token',
        token: null, // 可从localStorage或配置中获取
        tokenHeader: 'Authorization'
    },
    
    // API端点
    endpoints: {
        // 数据源相关
        datasource: {
            register: '/api/datasource/register',
            list: '/api/datasource/list',
            remove: '/api/datasource/remove',
            test: '/api/datasource/test',
            tree: '/api/datasource/tree'
        },
        // 其他模块可以继续添加
        user: {
            login: '/api/auth/login',
            logout: '/api/auth/logout'
        }
    },
    
    // 字段映射配置
    fieldMapping: {
        // 数据源注册字段映射
        datasource: {
            // 前端字段名 -> 后端字段名
            alias: 'alias',           // 数据源名称
            type: 'type',             // 数据源类型  
            host: 'ip',               // 主机地址 -> IP
            port: 'port',             // 端口
            username: 'username',      // 用户名
            password: 'password',      // 密码
            description: 'extraParams', // 描述 -> 额外参数
            database: 'extraParams',   // 数据库名称 -> 额外参数
            // 其他字段都放入extraParams
        }
    },
    
    // 获取完整的API URL
    getApiUrl(module, endpoint) {
        if (!this.endpoints[module] || !this.endpoints[module][endpoint]) {
            console.error(`API端点不存在: ${module}.${endpoint}`);
            return this.api.baseURL + endpoint;
        }
        return this.api.baseURL + this.endpoints[module][endpoint];
    },
    
    // 获取认证头
    getAuthHeaders() {
        const headers = { ...this.api.headers };
        const token = this.getToken();
        if (token) {
            headers[this.auth.tokenHeader] = `Bearer ${token}`;
        }
        return headers;
    },
    
    // 获取token
    getToken() {
        if (this.auth.token) {
            return this.auth.token;
        }
        return localStorage.getItem(this.auth.tokenKey);
    },
    
    // 设置token
    setToken(token) {
        this.auth.token = token;
        localStorage.setItem(this.auth.tokenKey, token);
    },
    
    // 清除token
    clearToken() {
        this.auth.token = null;
        localStorage.removeItem(this.auth.tokenKey);
    },
    
    // 转换表单数据为后端格式
    transformFormData(formData, module = 'datasource') {
        const mapping = this.fieldMapping[module];
        if (!mapping) {
            console.error(`字段映射配置不存在: ${module}`);
            return formData;
        }
        
        const backendData = {};
        const extraParams = {};
        
        // 遍历字段映射
        Object.entries(mapping).forEach(([frontendField, backendField]) => {
            const value = formData[frontendField];
            if (value !== undefined && value !== null && value !== '') {
                if (backendField === 'extraParams') {
                    // 放入额外参数
                    extraParams[frontendField] = value;
                } else {
                    // 直接映射
                    backendData[backendField] = value;
                }
            }
        });
        
        // 如果有额外参数，转换为JSON字符串
        if (Object.keys(extraParams).length > 0) {
            backendData.extraParams = JSON.stringify(extraParams);
        }
        
        return backendData;
    },
    
    // 初始化配置
    init(config = {}) {
        // 合并用户配置
        if (config.api) {
            this.api = { ...this.api, ...config.api };
        }
        if (config.auth) {
            this.auth = { ...this.auth, ...config.auth };
        }
        if (config.endpoints) {
            this.endpoints = { ...this.endpoints, ...config.endpoints };
        }
        
        // 初始化日志已静默
    }
};

// 默认初始化
window.AppConfig.init();
