class DataSourceList extends HTMLElement {
    constructor() {
        super();
        this.dataSources = [];
        this.currentPage = 1;
        this.pageSize = 10;
    }

    connectedCallback() {
        this.style.display = 'none'; // 默认隐藏
        
        this.innerHTML = `
            <link rel="stylesheet" href="./components/data-resource/data-source-list.css">
            <link rel="stylesheet" href="./components/common-pagination/common-pagination.css">
        `;
        
        // 加载HTML内容
        fetch('./components/data-resource/data-source-list.html')
            .then(response => response.text())
            .then(html => {
                this.innerHTML += html;
                this.initEventListeners();
                // 不在初始化时加载数据，只在显示时加载
            });
    }

    initEventListeners() {
        // 工具栏按钮
        const addDataSourceBtn = this.querySelector('#addDataSourceBtn');
        const refreshBtn = this.querySelector('#refreshBtn');

        if (addDataSourceBtn) {
            addDataSourceBtn.addEventListener('click', () => {
                // 显示注册异构数据源弹窗
                this.showRegisterDialog();
            });
        }

        if (refreshBtn) {
            refreshBtn.addEventListener('click', () => {
                this.loadDataSources();
            });
        }
    }

    async loadDataSources() {
        try {
            // 使用与左侧数据源树相同的接口
            const response = await fetch(window.AppConfig.getApiUrl('datasource', 'list'));
            const result = await response.json();
            
            if (result.code === 200 && result.data) {
                this.dataSources = result.data;
            } else {
                console.error('获取数据源列表失败:', result.message);
                this.dataSources = [];
            }
        } catch (error) {
            console.error('获取数据源列表异常:', error);
            this.dataSources = [];
        }

        this.renderTable();
    }

    getMockDataSources() {
        // 模拟数据，与左侧数据源树结构一致
        return [
            {
                id: 1,
                name: 'root.IoTDB',
                type: 'IoTDB',
                host: '192.168.1.100',
                port: 6667,
                username: 'root',
                status: 'connected',
                registerTime: '2024-01-15 10:30:00',
                updateTime: '2024-01-20 14:25:00'
            },
            {
                id: 2,
                name: 'root.test',
                type: 'IoTDB',
                host: '127.0.0.1',
                port: 6667,
                username: 'root',
                status: 'disconnected',
                registerTime: '2024-01-10 09:15:00',
                updateTime: '2024-01-18 16:40:00'
            },
            {
                id: 3,
                name: 'root.mysql_db',
                type: 'MySQL',
                host: '192.168.1.200',
                port: 3306,
                username: 'admin',
                status: 'connected',
                registerTime: '2024-01-08 11:20:00',
                updateTime: '2024-01-19 09:30:00'
            }
        ];
    }

    renderTable() {
        const tbody = this.querySelector('#tableBody');
        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        const pageData = this.dataSources.slice(start, end);

        if (pageData.length === 0) {
            tbody.innerHTML = `
                <tr>
                    <td colspan="7" style="text-align: center; padding: 40px; color: var(--text-secondary);">
                        暂无数据源
                    </td>
                </tr>
            `;
            return;
        }

        tbody.innerHTML = pageData.map(dataSource => `
            <tr data-id="${dataSource.id}">
                <td>${dataSource.id}</td>
                <td>${dataSource.ip || '-'}</td>
                <td>${dataSource.port}</td>
                <td>${this.getTypeText(dataSource.type)}</td>
                <td>${dataSource.schemaPrefix || '-'}</td>
                <td>${dataSource.dataPrefix || '-'}</td>
                <td>
                    <button class="action-btn delete" title="移除" onclick="this.closest('data-source-list').removeDataSource(${dataSource.id})">卸载</button>
                </td>
            </tr>
        `).join('');
    }

    getTypeText(type) {
        const typeMap = {
            0: 'unknown',
            1: 'iotdb12',
            2: 'influxdb',
            3: 'filesystem',
            4: 'relational',
            5: 'mongodb',
            6: 'redis'
        };
        return typeMap[type] || `类型${type}`;
    }

    viewDataSource(id) {
        const dataSource = this.dataSources.find(ds => ds.id === id);
        if (!dataSource) return;

        // 可以显示数据源详情弹窗，或者跳转到详情页面
        console.log('查看数据源详情:', dataSource);
        this.showMessage(`数据源: ${dataSource.ip}:${dataSource.port} (${this.getTypeText(dataSource.type)})`);
    }

    removeDataSource(id) {
        const dataSource = this.dataSources.find(ds => ds.id === id);
        if (!dataSource) return;

        // 显示确认对话框
        this.showDeleteConfirmDialog(dataSource);
    }

    showRegisterDialog() {
        // 创建注册弹窗，直接包含表单内容
        const dialogHtml = `
            <div class="register-dialog-overlay" style="
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0, 0, 0, 0.5);
                display: flex;
                align-items: center;
                justify-content: center;
                z-index: 2000;
            ">
                <div class="dialog-content" style="
                    background: white;
                    border-radius: 8px;
                    padding: 0;
                    max-width: 600px;
                    width: 90%;
                    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
                    max-height: 80vh;
                    overflow-y: auto;
                ">
                    <div class="register-container" style="padding: 24px;">
                        <div class="register-header" style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
                            <h3 class="register-title" style="margin: 0; font-size: 18px; color: #1f2329;">注册异构数据源</h3>
                            <button class="close-btn" id="closeBtn" style="
                                background: none;
                                border: none;
                                font-size: 24px;
                                cursor: pointer;
                                color: #666;
                                padding: 0;
                                width: 24px;
                                height: 24px;
                                display: flex;
                                align-items: center;
                                justify-content: center;
                            ">&times;</button>
                        </div>
                        
                        <form id="registerForm">
                            <div style="margin-bottom: 16px;">
                                <label style="display: block; margin-bottom: 4px; font-weight: 500; color: #1f2329;">
                                    数据源名称 <span style="color: #ff4d4f;">*</span>
                                </label>
                                <input type="text" id="dataSourceName" required style="
                                    width: 100%;
                                    padding: 8px 12px;
                                    border: 1px solid #d9d9d9;
                                    border-radius: 4px;
                                    font-size: 14px;
                                    box-sizing: border-box;
                                " placeholder="请输入数据源名称">
                            </div>

                            <div style="margin-bottom: 16px;">
                                <label style="display: block; margin-bottom: 4px; font-weight: 500; color: #1f2329;">
                                    数据源类型 <span style="color: #ff4d4f;">*</span>
                                </label>
                                <select id="dataSourceType" required style="
                                    width: 100%;
                                    padding: 8px 12px;
                                    border: 1px solid #d9d9d9;
                                    border-radius: 4px;
                                    font-size: 14px;
                                    box-sizing: border-box;
                                ">
                                    <option value="">请选择数据源类型</option>
                                    <optgroup label="关系型数据库">
                                        <option value="mysql">MySQL</option>
                                        <option value="postgresql">PostgreSQL</option>
                                        <option value="oracle">Oracle</option>
                                        <option value="sqlserver">SQL Server</option>
                                        <option value="dameng">达梦数据库</option>
                                    </optgroup>
                                    <optgroup label="时序数据库">
                                        <option value="influxdb">InfluxDB</option>
                                        <option value="iotdb">IoTDB</option>
                                    </optgroup>
                                    <optgroup label="NoSQL数据库">
                                        <option value="mongodb">MongoDB</option>
                                        <option value="redis">Redis</option>
                                    </optgroup>
                                    <optgroup label="文件系统">
                                        <option value="file">文件数据源</option>
                                    </optgroup>
                                </select>
                            </div>

                            <div style="margin-bottom: 16px;">
                                <label style="display: block; margin-bottom: 4px; font-weight: 500; color: #1f2329;">描述</label>
                                <textarea id="description" rows="2" style="
                                    width: 100%;
                                    padding: 8px 12px;
                                    border: 1px solid #d9d9d9;
                                    border-radius: 4px;
                                    font-size: 14px;
                                    box-sizing: border-box;
                                    resize: vertical;
                                " placeholder="请输入数据源描述信息"></textarea>
                            </div>

                            <div style="display: flex; gap: 12px; margin-bottom: 16px;">
                                <div style="flex: 1;">
                                    <label style="display: block; margin-bottom: 4px; font-weight: 500; color: #1f2329;">
                                        主机地址 <span style="color: #ff4d4f;">*</span>
                                    </label>
                                    <input type="text" id="host" required style="
                                        width: 100%;
                                        padding: 8px 12px;
                                        border: 1px solid #d9d9d9;
                                        border-radius: 4px;
                                        font-size: 14px;
                                        box-sizing: border-box;
                                    " placeholder="localhost">
                                </div>
                                <div style="width: 120px;">
                                    <label style="display: block; margin-bottom: 4px; font-weight: 500; color: #1f2329;">
                                        端口 <span style="color: #ff4d4f;">*</span>
                                    </label>
                                    <input type="number" id="port" required style="
                                        width: 100%;
                                        padding: 8px 12px;
                                        border: 1px solid #d9d9d9;
                                        border-radius: 4px;
                                        font-size: 14px;
                                        box-sizing: border-box;
                                    " placeholder="3306">
                                </div>
                            </div>

                            <div style="display: flex; gap: 12px; margin-bottom: 16px;">
                                <div style="flex: 1;">
                                    <label style="display: block; margin-bottom: 4px; font-weight: 500; color: #1f2329;">
                                        用户名 <span style="color: #ff4d4f;">*</span>
                                    </label>
                                    <input type="text" id="username" required style="
                                        width: 100%;
                                        padding: 8px 12px;
                                        border: 1px solid #d9d9d9;
                                        border-radius: 4px;
                                        font-size: 14px;
                                        box-sizing: border-box;
                                    " placeholder="请输入用户名">
                                </div>
                                <div style="flex: 1;">
                                    <label style="display: block; margin-bottom: 4px; font-weight: 500; color: #1f2329;">
                                        密码 <span style="color: #ff4d4f;">*</span>
                                    </label>
                                    <input type="password" id="password" required style="
                                        width: 100%;
                                        padding: 8px 12px;
                                        border: 1px solid #d9d9d9;
                                        border-radius: 4px;
                                        font-size: 14px;
                                        box-sizing: border-box;
                                    " placeholder="请输入密码">
                                </div>
                            </div>

                            <div style="margin-bottom: 20px;">
                                <label style="display: block; margin-bottom: 4px; font-weight: 500; color: #1f2329;">数据库名称</label>
                                <input type="text" id="database" style="
                                    width: 100%;
                                    padding: 8px 12px;
                                    border: 1px solid #d9d9d9;
                                    border-radius: 4px;
                                    font-size: 14px;
                                    box-sizing: border-box;
                                " placeholder="请输入数据库名称">
                            </div>

                            <div style="display: flex; gap: 12px; justify-content: flex-end;">
                                <button type="button" id="cancelBtn" style="
                                    padding: 8px 16px;
                                    border: 1px solid #d9d9d9;
                                    border-radius: 4px;
                                    background: white;
                                    color: #1f2329;
                                    cursor: pointer;
                                    font-size: 14px;
                                ">取消</button>
                                <button type="button" id="submitBtn" style="
                                    padding: 8px 16px;
                                    border: 1px solid #1890ff;
                                    border-radius: 4px;
                                    background: #1890ff;
                                    color: white;
                                    cursor: pointer;
                                    font-size: 14px;
                                ">确认注册</button>
                            </div>
                        </form>
                    </div>
                </div>
            </div>
        `;
        
        // 创建对话框元素
        const dialog = document.createElement('div');
        dialog.innerHTML = dialogHtml;
        document.body.appendChild(dialog);
        
        // 绑定事件
        this.initRegisterFormEvents(dialog);
    }

    initRegisterFormEvents(dialog) {
        const closeBtn = dialog.querySelector('#closeBtn');
        const cancelBtn = dialog.querySelector('#cancelBtn');
        const submitBtn = dialog.querySelector('#submitBtn');
        const overlay = dialog.querySelector('.register-dialog-overlay');
        
        const closeDialog = () => {
            if (dialog && dialog.parentNode) {
                document.body.removeChild(dialog);
            }
        };
        
        if (closeBtn) {
            closeBtn.addEventListener('click', closeDialog);
        }
        
        if (cancelBtn) {
            cancelBtn.addEventListener('click', closeDialog);
        }
        
        if (submitBtn) {
            submitBtn.addEventListener('click', () => {
                this.handleRegisterSubmit(dialog);
            });
        }
        
        if (overlay) {
            overlay.addEventListener('click', (e) => {
                if (e.target === overlay) {
                    closeDialog();
                }
            });
        }
    }

    async handleRegisterSubmit(dialog) {
        const form = dialog.querySelector('#registerForm');
        
        // 获取表单数据
        const name = document.getElementById('dataSourceName')?.value;
        const type = document.getElementById('dataSourceType')?.value;
        const description = document.getElementById('description')?.value;
        const host = document.getElementById('host')?.value;
        const port = document.getElementById('port')?.value;
        const username = document.getElementById('username')?.value;
        const password = document.getElementById('password')?.value;
        const database = document.getElementById('database')?.value;
        
        // 类型映射
        const typeMapping = {
            'mysql': 4,      // relational
            'postgresql': 4,
            'oracle': 4,
            'sqlserver': 4,
            'dameng': 4,
            'influxdb': 2,  // influxdb
            'iotdb': 1,     // iotdb12
            'mongodb': 5,   // mongodb
            'redis': 6,     // redis
            'file': 3,      // filesystem
            'elasticsearch': 0, // unknown
            'api': 0        // unknown
        };
        
        // 映射到后端期望的字段名
        const data = {
            alias: name,
            ip: host,
            port: parseInt(port),
            storageEngineType: typeMapping[type] || 0,
            description: description,
            username: username,
            password: password,
            database: database
        };
        
        // 简单验证
        if (!data.alias || !data.ip || !data.port || data.storageEngineType === 0) {
            this.showMessage('请填写必填字段并选择有效的数据源类型', 'error');
            return;
        }
        
        try {
            const response = await fetch('/api/datasource/register', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(data)
            });
            
            const result = await response.json();
            
            if (result.code === 200) {
                this.showMessage('数据源注册成功', 'success');
                // 立即关闭弹窗并刷新
                if (dialog && dialog.parentNode) {
                    document.body.removeChild(dialog);
                }
                // 刷新数据源列表
                this.loadDataSources();
            } else {
                this.showMessage(result.message || '注册失败', 'error');
            }
        } catch (error) {
            console.error('注册数据源失败:', error);
            this.showMessage('注册失败，请稍后重试', 'error');
        }
    }

    showDeleteConfirmDialog(dataSource) {
        const dialogHtml = `
            <div class="delete-confirm-dialog" style="
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0, 0, 0, 0.5);
                display: flex;
                align-items: center;
                justify-content: center;
                z-index: 2000;
            ">
                <div class="dialog-content" style="
                    background: white;
                    border-radius: 8px;
                    padding: 24px;
                    max-width: 400px;
                    width: 90%;
                    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
                ">
                    <h3 style="margin: 0 0 16px 0; font-size: 18px; color: #1f2329;">确认删除</h3>
                    <p style="margin: 0 0 24px 0; color: #646a73; line-height: 1.5;">
                        确定要删除数据源 "${dataSource.ip}:${dataSource.port}" 吗？<br><br>
                        <span style="color: #f5222d;">此操作不可恢复！</span>
                    </p>
                    <div class="dialog-actions" style="display: flex; gap: 12px; justify-content: flex-end;">
                        <button class="cancel-btn" style="
                            padding: 8px 16px;
                            border: 1px solid #c9cdd4;
                            border-radius: 4px;
                            background: white;
                            color: #1f2329;
                            cursor: pointer;
                            font-size: 14px;
                        ">取消</button>
                        <button class="confirm-btn" style="
                            padding: 8px 16px;
                            border: 1px solid #f5222d;
                            border-radius: 4px;
                            background: #f5222d;
                            color: white;
                            cursor: pointer;
                            font-size: 14px;
                        ">确认删除</button>
                    </div>
                </div>
            </div>
        `;
        
        // 创建对话框元素
        const dialog = document.createElement('div');
        dialog.innerHTML = dialogHtml;
        document.body.appendChild(dialog);
        
        // 绑定事件
        const cancelBtn = dialog.querySelector('.cancel-btn');
        const confirmBtn = dialog.querySelector('.confirm-btn');
        
        const closeDialog = () => {
            document.body.removeChild(dialog);
        };
        
        cancelBtn.addEventListener('click', closeDialog);
        
        confirmBtn.addEventListener('click', () => {
            closeDialog();
            this.callDeleteApi(dataSource);
        });
        
        // 点击遮罩关闭
        dialog.addEventListener('click', (e) => {
            if (e.target === dialog) {
                closeDialog();
            }
        });
    }

    async callDeleteApi(dataSource) {
        try {
            console.log('删除数据源:', dataSource);
            
            // 调用删除API
            const response = await fetch('/api/datasource/remove', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(dataSource)
            });
            
            if (response.ok) {
                const result = await response.json();
                console.log('删除响应:', result);
                
                if (result.code === 200) {
                    this.showMessage('数据源删除成功', 'success');
                    // 重新加载数据
                    this.loadDataSources();
                } else {
                    this.showMessage(result.message || '删除失败', 'error');
                }
            } else {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
        } catch (error) {
            console.error('删除数据源失败:', error);
            this.showMessage('删除失败，请稍后重试', 'error');
        }
    }

    showMessage(message, type = 'success') {
        // 使用系统一致的消息提示
        try {
            if (typeof showWorkspaceMessage === 'function') {
                showWorkspaceMessage(message, type);
            } else if (window.parent && typeof window.parent.showWorkspaceMessage === 'function') {
                window.parent.showWorkspaceMessage(message, type);
            } else {
                // 降级到内联提示
                console.log(`${type}: ${message}`);
                const notification = document.createElement('div');
                notification.style.cssText = `
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    padding: 12px 20px;
                    border-radius: 4px;
                    color: white;
                    font-size: 14px;
                    z-index: 10000;
                    box-shadow: 0 2px 8px rgba(0,0,0,0.2);
                    transition: all 0.3s ease;
                    max-width: 300px;
                `;
                
                const colors = {
                    success: '#52c41a',
                    error: '#ff4d4f',
                    warning: '#faad14',
                    info: '#1890ff'
                };
                notification.style.backgroundColor = colors[type] || colors.info;
                notification.textContent = message;
                
                document.body.appendChild(notification);
                
                setTimeout(() => {
                    if (notification.parentNode) {
                        notification.style.opacity = '0';
                        setTimeout(() => {
                            if (notification.parentNode) {
                                document.body.removeChild(notification);
                            }
                        }, 300);
                    }
                }, 3000);
            }
        } catch (error) {
            console.error('显示消息失败:', error);
            console.log(`${type}: ${message}`);
        }
    }

    show() {
        this.style.display = 'block';
        // 每次显示时刷新数据
        this.loadDataSources();
    }

    hide() {
        this.style.display = 'none';
    }
}

// 注册自定义元素
customElements.define('data-source-list', DataSourceList);
