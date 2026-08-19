/**
 * 应用全局配置文件
 * 前后端分离配置
 */
window.AppConfig = {
    // API基础配置
    api: {
        baseURL: 'http://localhost:8080', // 可配置的API域名
        //baseURL: 'http://124.65.131.2:18080',
        // 前端请求超时时间（毫秒），建议略小于后端超时时间
        timeout: 55000,
        headers: {
            'Content-Type': 'application/json'
        }
    },
    
    // 认证配置
    auth: {
        tokenKey: 'jwtToken', // 使用JWT token
        token: null,
        tokenHeader: 'Authorization',
        refreshTokenKey: 'refreshToken',
        usernameKey: 'username'
    },
    
    // API端点
    endpoints: {
        // 认证相关
        auth: {
            login: '/api/auth/login',
            logout: '/api/auth/logout',
            refresh: '/api/auth/refresh',
            verify: '/api/auth/verify',
            user: '/api/auth/user'
        },
        // 数据源相关
        datasource: {
            register: '/api/datasource/register',
            list: '/api/datasource/list',
            remove: '/api/datasource/remove',
            test: '/api/datasource/test',
            tree: '/api/datasource/tree'
        },
        // 数据查询相关
        data: {
            query: '/api/data/query',
            'relational/query': '/api/data/relational/query',
            'relational/count': '/api/data/relational/count',
            'relational/export': '/api/data/relational/export',
            import: '/api/data/import',
            export: '/api/data/export',
            delete: '/api/data/delete'
        },
        // 模型生成相关
        generation: {
            generate: '/api/generation/generate',
            preview: '/api/generation/preview',
            download: '/api/generation/download',
            list: '/api/generation/list'
        },
        // 模型文件相关
        modelFiles: {
            list: '/api/model-files/list',
            save: '/api/model-files/save',
            delete: '/api/model-files/delete',
            content: '/api/model-files/content'
        },
        // 关联规则相关
        associationRules: {
            query: '/api/association/rules/query',
            count: '/api/association/rules/count',
            detail: '/api/association/rules/detail',
            delete: '/api/association/rules/delete',
            save: '/api/association/rules/save',
            'validate-name': '/api/association/rules/validate-name'
        },
        // 解析规则相关
        parsingRules: {
            query: '/api/parsing/rules/query',
            count: '/api/parsing/rules/count',
            detail: '/api/parsing/rules/detail',
            delete: '/api/parsing/rules/delete',
            save: '/api/parsing/rules/save',
            'validate-name': '/api/parsing/rules/validate-name',
            autoParse: '/api/parsing/autoParse'
        },
        // 仿真档案相关
        simulationArchives: {
            query: '/api/simulation/archives/query',
            count: '/api/simulation/archives/count',
            detail: '/api/simulation/archives/detail',
            delete: '/api/simulation/archives/delete',
            save: '/api/simulation/archives/save',
            'upload-report': '/api/simulation/archives/upload-report',
            'package-download': '/api/simulation/archives/package-download',
            'validate-name': '/api/simulation/archives/validate-name',
            copy: '/api/simulation/archives/copy',
            run: '/api/simulation/archives/run',
            'run-selective': '/api/simulation/archives/run-selective',
            stop: '/api/simulation/archives/stop',
            'execution-status': '/api/simulation/archives/execution-status',
            'execution-log': '/api/simulation/archives/execution-log',
            'execution-records': '/api/simulation/archives/execution-records',
            'execution-records-count': '/api/simulation/archives/execution-records-count',
            'execution-record': '/api/simulation/archives/execution-record'
        },
        // 数据档案相关
        dataArchive: {
            query: '/api/dataArchive/query',
            count: '/api/dataArchive/count',
            detail: '/api/dataArchive/detail',
            update: '/api/dataArchive/update',
            delete: '/api/dataArchive/delete'
        },
        // 算法管理相关
        algorithm: {
            upload: '/api/algorithm/upload',
            download: '/api/algorithm/download',
            metas: '/api/algorithm/metas',
            history: '/api/algorithm/history',
            delete: '/api/algorithm/delete',
            extractAlgorithmFile: '/api/algorithm/extractAlgorithmFile',
            tree: '/api/algorithm/tree',
            'archive/query': '/api/algorithm/archive/query',
            'archive/count': '/api/algorithm/archive/count'
        },
        // 用户管理相关
        userManagement: {
            query: '/api/user/query',
            count: '/api/user/count',
            detail: '/api/user/detail',
            update: '/api/user/update',
            save: '/api/user/save',
            delete: '/api/user/delete',
            'change-password': '/api/user/change-password',
            all: '/api/user/all'
        },
        dataPermission: {
            ownerTables: '/api/data-permission/owner-tables',
            query: '/api/data-permission/query',
            count: '/api/data-permission/count',
            update: '/api/data-permission/update',
            delete: '/api/data-permission/delete'
        },
        // 模型相关
        model: {
            upload: '/api/model/upload',
            download: '/api/model/download',
            metas: '/api/model/metas',
            history: '/api/model/history',
            delete: '/api/model/delete',
            extractModelFile: '/api/model/extractModelFile',
            autoParse: '/api/parsing/autoParse',
            tree: '/api/model/tree',
            'archive/query': '/api/model/archive/query',
            'archive/count': '/api/model/archive/count'
        },
        // 任务相关
        task: {
            run: '/api/task/run',
            'validate-uniqueness': '/api/task/validate-uniqueness',
            stop: '/api/task/stop',
            log: '/api/task/log',
            query: '/api/task/query',
            count: '/api/task/count',
            detail: '/api/task/detail',
            'delete': '/api/task/delete',
            'upload-report': '/api/task/upload-report',
            'package-download': '/api/task/package-download',
            'time-range': '/api/task/time-range'
        },
        // 项目相关
        project: {
            create: '/api/project/create',
            query: '/api/project/query',
            count: '/api/project/count',
            detail: '/api/project/detail',
            tree: '/api/project/tree'
        },
        // 程序管理相关
        program: {
            upload: '/api/program/upload',
            download: '/api/program/download',
            metas: '/api/program/metas',
            history: '/api/program/history',
            delete: '/api/program/delete',
            tree: '/api/program/tree',
            list: '/api/program/list',
            count: '/api/program/count',
            run: '/api/program/run',
            stop: '/api/program/stop',
            results: '/api/program/results',
            'live-data': '/api/program/live-data',
            'live-stream': '/api/program/live-stream',
            pause: '/api/program/pause',
            resume: '/api/program/resume',
            'update-config': '/api/program/update-config',
            config: '/api/program/config',
            plugin: '/api/program/plugin',
            files: '/api/program/files',
            'download-result': '/api/program/download-result',
            'upload-overview': '/api/program/upload-overview',
            'download-signal': '/api/program/download-signal',
            'engine-status': '/api/program/engine-status',
            'engine-restart': '/api/program/engine-restart',
            'preset-programs': '/api/program/preset-programs',
            'config-templates': '/api/program/config-templates',
            templates: '/api/program/templates',
            'setup-script': '/api/program/setup-script'
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
    
    // 水印配置
    // 可以通过修改以下配置来自定义水印效果
    watermark: {
        text: '清华大学大数据系统软件国家工程研究中心', // 水印文本内容
        opacity: 0.1,                                        // 透明度 (0-1)
        fontSize: 48,                                        // 字体大小（像素）
        color: '#999',                                       // 水印颜色
        rotation: -45,                                       // 旋转角度（度）
        enable: true                                         // 是否启用水印
    },
    
    // 获取认证头
    getAuthHeaders() {
        const headers = { ...this.api.headers };
        const token = this.getToken();
        if (token) {
            headers[this.auth.tokenHeader] = `Bearer ${token}`;
        }
        // 添加当前项目信息到请求头（按用户隔离）
        const username = this.getUsername();
        if (username) {
            const currentProject = localStorage.getItem('currentProject_' + username);
            if (currentProject) {
                try {
                    const project = JSON.parse(currentProject);
                    if (project && project.name) {
                        // HTTP header 仅支持 ISO-8859-1，中文等项目名需 URL 编码
                        headers['X-Current-Project'] = encodeURIComponent(project.name);
                    }
                } catch (e) {
                    console.error('解析当前项目失败:', e);
                }
            }
        }
        return headers;
    },
    
    // 获取完整的API URL
    getApiUrl(module, endpoint) {
        if (!this.endpoints[module] || !this.endpoints[module][endpoint]) {
            console.error(`API端点不存在: ${module}.${endpoint}`);
            return this.api.baseURL + endpoint;
        }
        return this.api.baseURL + this.endpoints[module][endpoint];
    },
    
    // 统一API调用方法
    async request(url, options = {}) {
        const config = {
            method: 'GET',
            headers: { ...this.getAuthHeaders(), ...(options.headers || {}) },
            ...options
        };

        // 如果是登录或刷新接口，不需要token
        if (url.includes('/api/auth/login') || url.includes('/api/auth/refresh')) {
            delete config.headers[this.auth.tokenHeader];
        }

        // 创建AbortController用于超时控制
        const controller = new AbortController();
        const timeoutId = setTimeout(() => {
            controller.abort();
            console.error(`请求超时: ${url} (超时时间: ${this.api.timeout}ms)`);
        }, this.api.timeout);

        // 将signal添加到config中
        config.signal = controller.signal;

        try {
            const response = await fetch(url, config);
            
            // 检查认证状态
            if (response.status === 401) {
                console.log('⚠️ 收到401响应，尝试刷新token');
                // 尝试刷新token
                try {
                    const newToken = await this.refreshToken();
                    if (newToken) {
                        // 重新设置请求头
                        config.headers[this.auth.tokenHeader] = `Bearer ${newToken}`;
                        console.log('🔄 使用新token重新发送请求');
                        // 重新发送请求
                        const retryResponse = await fetch(url, config);
                        if (retryResponse.ok) {
                            const contentType = retryResponse.headers.get('content-type');
                            if (contentType && contentType.includes('application/json')) {
                                return await retryResponse.json();
                            } else {
                                return await retryResponse.text();
                            }
                        }
                    }
                } catch (refreshError) {
                    console.error('刷新token失败:', refreshError);
                }
                
                // 刷新失败，处理认证失败
                this.handleAuthFailure();
                throw new Error('认证失败，请重新登录');
            }
            
            // 检查权限不足状态 (403)
            if (response.status === 403) {
                console.log('🚫 收到403响应，权限不足');
                try {
                    const errorData = await response.json();
                    if (errorData && errorData.message) {
                        // 显示后端返回的详细权限错误信息
                        if (window.CommonUtils && window.CommonUtils.showError) {
                            window.CommonUtils.showError(errorData.message, 8000); // 显示8秒
                        } else if (window.CommonUtils && window.CommonUtils.showToast) {
                            window.CommonUtils.showToast(errorData.message, 'error');
                        }
                        throw new Error(errorData.message);
                    }
                } catch (parseError) {
                    // 如果无法解析JSON，使用默认错误信息
                    const errorMsg = '权限不足，无法访问该资源。请联系管理员分配相应权限。';
                    if (window.CommonUtils && window.CommonUtils.showError) {
                        window.CommonUtils.showError(errorMsg, 8000);
                    } else if (window.CommonUtils && window.CommonUtils.showToast) {
                        window.CommonUtils.showToast(errorMsg, 'error');
                    }
                    throw new Error(errorMsg);
                }
            }
            
            // 检查其他HTTP错误
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            
            // 尝试解析JSON响应
            const contentType = response.headers.get('content-type');
            if (contentType && contentType.includes('application/json')) {
                return await response.json();
            } else {
                return await response.text();
            }
            
        } catch (error) {
            // 清除timeout
            clearTimeout(timeoutId);
            
            if (error.name === 'AbortError') {
                throw new Error(`请求超时，请检查网络连接或稍后重试 (超时时间: ${this.api.timeout}ms)`);
            }
            
            console.error('API请求失败:', error);
            throw error;
        } finally {
            // 确保清除timeout
            clearTimeout(timeoutId);
        }
    },

    // GET请求
    async get(module, endpoint, params = {}) {
        let url = this.getApiUrl(module, endpoint);
        
        // 添加查询参数
        if (Object.keys(params).length > 0) {
            const queryString = new URLSearchParams(params).toString();
            url += (url.includes('?') ? '&' : '?') + queryString;
        }
        
        return this.request(url, { method: 'GET' });
    },

    // POST请求
    async post(module, endpoint, data = {}) {
        const url = this.getApiUrl(module, endpoint);
        return this.request(url, {
            method: 'POST',
            body: JSON.stringify(data)
        });
    },

    // PUT请求
    async put(module, endpoint, data = {}) {
        const url = this.getApiUrl(module, endpoint);
        return this.request(url, {
            method: 'PUT',
            body: JSON.stringify(data)
        });
    },

    // DELETE请求
    async delete(module, endpoint, params = {}) {
        let url = this.getApiUrl(module, endpoint);
        
        // 添加查询参数
        if (Object.keys(params).length > 0) {
            const queryString = new URLSearchParams(params).toString();
            url += (url.includes('?') ? '&' : '?') + queryString;
        }
        
        return this.request(url, { method: 'DELETE' });
    },

    // 处理认证失败
    handleAuthFailure() {
        console.warn('认证失败，清除token并跳转到登录页');
        this.clearToken();
        this.clearRefreshToken();
        this.clearUsername();
        
        // 如果不在登录页面，则跳转
        if (!window.location.pathname.includes('/login.html')) {
            window.location.href = '/login.html';
        }
    },

    // 获取refresh token
    getRefreshToken() {
        return localStorage.getItem(this.auth.refreshTokenKey);
    },

    // 设置refresh token
    setRefreshToken(refreshToken) {
        localStorage.setItem(this.auth.refreshTokenKey, refreshToken);
    },

    // 清除refresh token
    clearRefreshToken() {
        localStorage.removeItem(this.auth.refreshTokenKey);
    },

    // 获取用户名
    getUsername() {
        return localStorage.getItem(this.auth.usernameKey);
    },

    // 设置用户名
    setUsername(username) {
        localStorage.setItem(this.auth.usernameKey, username);
    },

    // 清除用户名
    clearUsername() {
        localStorage.removeItem(this.auth.usernameKey);
    },

    // 检查是否已登录
    isLoggedIn() {
        return !!this.getToken();
    },

    // 验证当前token是否有效
    async validateToken() {
        if (!this.getToken()) {
            return false;
        }

        try {
            const response = await this.request(
                this.api.baseURL + this.endpoints.auth.verify,
                { method: 'GET' }
            );
            return response && response.success;
        } catch (error) {
            console.error('Token验证失败:', error);
            return false;
        }
    },

    // 刷新token
    async refreshToken() {
        const refreshToken = this.getRefreshToken();
        
        if (!refreshToken) {
            throw new Error('没有刷新token');
        }

        try {
            // 直接使用fetch，避免循环调用request方法
            const refreshUrl = this.api.baseURL + this.endpoints.auth.refresh;
            
            const response = await fetch(refreshUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ refreshToken })
            });

            if (response.ok) {
                const result = await response.json();
                
                if (result.success && result.data) {
                    this.setToken(result.data.token);
                    this.setRefreshToken(result.data.refreshToken);
                    console.log('🔄 Token刷新成功');
                    return result.data.token;
                } else {
                    throw new Error(result.message || '刷新token失败');
                }
            } else {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
        } catch (error) {
            console.error('刷新token失败:', error);
            this.handleAuthFailure();
            throw error;
        }
    },

    // 登录
    async login(username, password) {
        try {
            const response = await this.request(
                this.api.baseURL + this.endpoints.auth.login,
                {
                    method: 'POST',
                    body: JSON.stringify({ username, password })
                }
            );

            if (response.success && response.data) {
                this.setToken(response.data.token);
                this.setRefreshToken(response.data.refreshToken);
                this.setUsername(username);
                // 不清除项目信息，让用户能恢复上次的项目
                return response;
            } else {
                throw new Error(response.message || '登录失败');
            }
        } catch (error) {
            console.error('登录失败:', error);
            throw error;
        }
    },

    // 登出
    async logout() {
        try {
            if (this.getToken()) {
                await this.request(
                    this.api.baseURL + this.endpoints.auth.logout,
                    { method: 'POST' }
                );
            }
        } catch (error) {
            console.error('登出请求失败:', error);
        } finally {
            const username = this.getUsername();
            this.clearToken();
            this.clearRefreshToken();
            this.clearUsername();
            // 清除当前用户的项目信息（按用户隔离）
            if (username) {
                localStorage.removeItem('currentProject_' + username);
            }
            
            // 跳转到登录页
            if (!window.location.pathname.includes('/login.html')) {
                window.location.href = '/login.html';
            }
        }
    },

    // 文件上传请求
    async upload(module, endpoint, formData) {
        const url = this.getApiUrl(module, endpoint);
        const headers = this.getAuthHeaders();
        
        // 文件上传不能设置Content-Type，让浏览器自动设置
        delete headers['Content-Type'];

        try {
            const response = await fetch(url, {
                method: 'POST',
                headers: headers,
                body: formData
            });
            
            // 检查认证状态
            if (response.status === 401) {
                // 尝试刷新token
                try {
                    const newToken = await this.refreshToken();
                    if (newToken) {
                        // 重新设置请求头
                        headers[this.auth.tokenHeader] = `Bearer ${newToken}`;
                        // 重新发送请求
                        const retryResponse = await fetch(url, {
                            method: 'POST',
                            headers: headers,
                            body: formData
                        });
                        if (retryResponse.ok) {
                            const contentType = retryResponse.headers.get('content-type');
                            if (contentType && contentType.includes('application/json')) {
                                return await retryResponse.json();
                            } else {
                                return await retryResponse.text();
                            }
                        }
                    }
                } catch (refreshError) {
                    console.error('刷新token失败:', refreshError);
                }
                
                // 刷新失败，处理认证失败
                this.handleAuthFailure();
                throw new Error('认证失败，请重新登录');
            }
            
            // 检查权限不足状态 (403)
            if (response.status === 403) {
                console.log('🚫 收到403响应，权限不足');
                try {
                    const errorData = await response.json();
                    if (errorData && errorData.message) {
                        // 显示后端返回的详细权限错误信息
                        if (window.CommonUtils && window.CommonUtils.showError) {
                            window.CommonUtils.showError(errorData.message, 8000); // 显示8秒
                        } else if (window.CommonUtils && window.CommonUtils.showToast) {
                            window.CommonUtils.showToast(errorData.message, 'error');
                        }
                        throw new Error(errorData.message);
                    }
                } catch (parseError) {
                    // 如果无法解析JSON，使用默认错误信息
                    const errorMsg = '权限不足，无法访问该资源。请联系管理员分配相应权限。';
                    if (window.CommonUtils && window.CommonUtils.showError) {
                        window.CommonUtils.showError(errorMsg, 8000);
                    } else if (window.CommonUtils && window.CommonUtils.showToast) {
                        window.CommonUtils.showToast(errorMsg, 'error');
                    }
                    throw new Error(errorMsg);
                }
            }
            
            // 检查其他HTTP错误
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            
            // 尝试解析JSON响应
            const contentType = response.headers.get('content-type');
            if (contentType && contentType.includes('application/json')) {
                return await response.json();
            } else {
                return await response.text();
            }
            
        } catch (error) {
            console.error('文件上传失败:', error);
            throw error;
        }
    },

    // 文件下载请求
    async download(module, endpoint, data, filename, useUrlParams = false) {
        let url = this.getApiUrl(module, endpoint);
        const headers = this.getAuthHeaders();

        try {
            let requestOptions = {
                method: 'POST',
                headers: headers
            };

            if (useUrlParams) {
                // 使用URL参数而不是JSON body
                if (Object.keys(data).length > 0) {
                    const queryString = new URLSearchParams(data).toString();
                    url += (url.includes('?') ? '&' : '?') + queryString;
                }
            } else {
                // 使用JSON body
                requestOptions.body = JSON.stringify(data);
            }

            const response = await fetch(url, requestOptions);
            
            // 检查认证状态
            if (response.status === 401) {
                this.handleAuthFailure();
                throw new Error('认证失败，请重新登录');
            }
            
            // 检查权限不足状态 (403)
            if (response.status === 403) {
                console.log('🚫 收到403响应，权限不足');
                try {
                    const errorData = await response.json();
                    if (errorData && errorData.message) {
                        // 显示后端返回的详细权限错误信息
                        if (window.CommonUtils && window.CommonUtils.showError) {
                            window.CommonUtils.showError(errorData.message, 8000); // 显示8秒
                        } else if (window.CommonUtils && window.CommonUtils.showToast) {
                            window.CommonUtils.showToast(errorData.message, 'error');
                        }
                        throw new Error(errorData.message);
                    }
                } catch (parseError) {
                    // 如果无法解析JSON，使用默认错误信息
                    const errorMsg = '权限不足，无法访问该资源。请联系管理员分配相应权限。';
                    if (window.CommonUtils && window.CommonUtils.showError) {
                        window.CommonUtils.showError(errorMsg, 8000);
                    } else if (window.CommonUtils && window.CommonUtils.showToast) {
                        window.CommonUtils.showToast(errorMsg, 'error');
                    }
                    throw new Error(errorMsg);
                }
            }
            
            // 检查其他HTTP错误
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            
            // 获取文件名
            const contentDisposition = response.headers.get('Content-Disposition');
            let downloadFilename = filename || 'download.xlsx';
            if (contentDisposition) {
                const filenameMatch = contentDisposition.match(/filename="?([^"]+)"?/);
                if (filenameMatch) {
                    downloadFilename = filenameMatch[1];
                }
            }
            
            // 下载文件
            const blob = await response.blob();
            const downloadUrl = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = downloadUrl;
            a.download = downloadFilename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            window.URL.revokeObjectURL(downloadUrl);
            
            return { success: true, filename: downloadFilename };
            
        } catch (error) {
            console.error('文件下载失败:', error);
            throw error;
        }
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
