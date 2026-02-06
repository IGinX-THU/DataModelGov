/**
 * 注册异构数据源内嵌页面组件
 * 使用 Web Components (Custom Elements + Shadow DOM) 实现
 * 直接在workspace内显示，不使用弹框
 */
class RegisterDataResourceEmbedded extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
    }

    async connectedCallback() {
        await this.loadResources();
        this.render();
        // 等待DOM渲染完成后再绑定事件
        setTimeout(() => {
            this.bindEvents();
        }, 100);
    }

    async loadResources() {
        // 加载CSS
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/data-resource/register-embedded.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.htmlTemplate = this.getInlineHTML();
            return;
        }

        // 加载HTML模板
        try {
            const response = await fetch('./components/data-resource/register-embedded.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const htmlContent = await response.text();
            this.htmlTemplate = htmlContent;
        } catch (error) {
            console.error('Failed to load HTML template:', error);
            // 如果外部文件加载失败，使用内联模板
            this.htmlTemplate = this.getInlineHTML();
        }
    }

    getInlineHTML() {
        return `
            <style>
                /* 内联样式作为备用 */
                :host {
                    display: none;
                    width: 100%;
                    height: 100%;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                }

                :host([show]) {
                    display: block;
                }

                .register-container {
                    background: white;
                    border-radius: 8px;
                    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
                    padding: 24px;
                    height: 100%;
                    overflow-y: auto;
                }

                .register-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 24px;
                    padding-bottom: 16px;
                    border-bottom: 1px solid #e0e6ed;
                }

                .register-title {
                    font-size: 18px;
                    font-weight: 600;
                    color: #1f2329;
                    margin: 0;
                }

                .close-btn {
                    background: none;
                    border: none;
                    font-size: 20px;
                    cursor: pointer;
                    color: #646a73;
                    width: 28px;
                    height: 28px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    border-radius: 4px;
                    transition: all 0.2s;
                }

                .close-btn:hover {
                    background: #e0e6ed;
                    color: #1f2329;
                }

                .form-group {
                    margin-bottom: 16px;
                }

                .form-label {
                    display: block;
                    margin-bottom: 6px;
                    font-weight: 500;
                    color: #1f2329;
                    font-size: 14px;
                }

                .form-label.required::after {
                    content: ' *';
                    color: #f53f3f;
                }

                .form-control {
                    width: 100%;
                    padding: 8px 12px;
                    border: 1px solid #c9cdd4;
                    border-radius: 4px;
                    font-size: 14px;
                    transition: all 0.2s;
                    box-sizing: border-box;
                    background: #fff;
                }

                .form-control:focus {
                    outline: none;
                    border-color: #3370ff;
                    box-shadow: 0 0 0 2px rgba(51, 112, 255, 0.1);
                }

                .form-select {
                    appearance: none;
                    background-image: url("data:image/svg+xml,%3Csvg width='12' height='12' viewBox='0 0 12 12' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M2 4L6 8L10 4' stroke='%23646a73' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
                    background-repeat: no-repeat;
                    background-position: right 8px center;
                    background-size: 12px;
                    padding-right: 28px;
                }

                .form-row {
                    display: flex;
                    gap: 16px;
                }

                .form-row .form-group {
                    flex: 1;
                }

                .dynamic-fields {
                    margin-top: 16px;
                    padding-top: 16px;
                    border-top: 1px solid #e0e6ed;
                }

                .dynamic-fields .form-group {
                    margin-bottom: 12px;
                }

                .form-actions {
                    margin-top: 24px;
                    padding-top: 16px;
                    border-top: 1px solid #e0e6ed;
                    display: flex;
                    justify-content: flex-end;
                    gap: 12px;
                }

                .btn {
                    padding: 8px 16px;
                    border: 1px solid #c9cdd4;
                    border-radius: 4px;
                    cursor: pointer;
                    font-size: 14px;
                    transition: all 0.2s;
                    background: white;
                    color: #1f2329;
                }

                .btn:hover {
                    background: #f2f3f5;
                }

                .btn-primary {
                    background: #3370ff;
                    color: white;
                    border-color: #3370ff;
                }

                .btn-primary:hover {
                    background: #165dff;
                    border-color: #165dff;
                }

                .btn-secondary {
                    background: #f2f3f5;
                    color: #1f2329;
                    border-color: #c9cdd4;
                }

                .btn-secondary:hover {
                    background: #e5e6eb;
                }

                .message {
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    padding: 8px 16px;
                    border-radius: 4px;
                    color: white;
                    font-size: 14px;
                    z-index: 2000;
                    animation: slideIn 0.3s ease;
                    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
                }

                .message.success {
                    background: #00b42a;
                }

                .message.error {
                    background: #f53f3f;
                }

                .message.info {
                    background: #3370ff;
                }

                @keyframes slideIn {
                    from { transform: translateX(100%); opacity: 0; }
                    to { transform: translateX(0); opacity: 1; }
                }
            </style>
            <div class="register-container">
                <div class="register-header">
                    <h3 class="register-title">注册异构数据源</h3>
                    <button class="close-btn" id="closeBtn">&times;</button>
                </div>
                
                <form id="registerForm">
                    <div class="form-group">
                        <label class="form-label required">数据源名称</label>
                        <input type="text" class="form-control" id="dataSourceName" placeholder="请输入数据源名称" required>
                    </div>

                    <div class="form-group">
                        <label class="form-label required">数据源类型</label>
                        <select class="form-control form-select" id="dataSourceType" required>
                            <option value="">请选择数据源类型</option>
                            <option value="mysql">MySQL</option>
                            <option value="postgresql">PostgreSQL</option>
                            <option value="oracle">Oracle</option>
                            <option value="sqlserver">SQL Server</option>
                            <option value="influxdb">InfluxDB</option>
                            <option value="mongodb">MongoDB</option>
                            <option value="elasticsearch">Elasticsearch</option>
                            <option value="redis">Redis</option>
                            <option value="dameng">达梦数据库</option>
                            <option value="iotdb">IoTDB</option>
                            <option value="api">REST API</option>
                            <option value="file">文件数据源</option>
                        </select>
                    </div>

                    <div class="form-group">
                        <label class="form-label">描述</label>
                        <textarea class="form-control" id="description" rows="2" placeholder="请输入数据源描述信息"></textarea>
                    </div>

                    <div class="form-row">
                        <div class="form-group">
                            <label class="form-label required">主机地址</label>
                            <input type="text" class="form-control" id="host" placeholder="localhost" required>
                        </div>
                        <div class="form-group">
                            <label class="form-label required">端口</label>
                            <input type="number" class="form-control" id="port" placeholder="3306" required>
                        </div>
                    </div>

                    <div class="form-row">
                        <div class="form-group">
                            <label class="form-label required">用户名</label>
                            <input type="text" class="form-control" id="username" placeholder="请输入用户名" required>
                        </div>
                        <div class="form-group">
                            <label class="form-label required">密码</label>
                            <input type="password" class="form-control" id="password" placeholder="请输入密码" required>
                        </div>
                    </div>

                    <div class="form-group">
                        <label class="form-label">数据库名称</label>
                        <input type="text" class="form-control" id="database" placeholder="请输入数据库名称">
                    </div>

                    <!-- 动态字段区域 -->
                    <div id="dynamicFields" class="dynamic-fields" style="display: none;">
                        <!-- 动态字段将在这里插入 -->
                    </div>

                    <div class="form-actions">
                        <button type="button" class="btn btn-secondary" id="cancelBtn">
                            取消
                        </button>
                        <button type="button" class="btn btn-primary" id="submitBtn">
                            确认注册
                        </button>
                    </div>
                </form>
            </div>
        `;
    }

    render() {
        if (this.htmlTemplate) {
            // 保留已加载的CSS，只添加HTML
            const existingCSS = this.shadowRoot.querySelector('link');
            this.shadowRoot.innerHTML = '';
            if (existingCSS) {
                this.shadowRoot.appendChild(existingCSS);
            }
            this.shadowRoot.innerHTML += this.htmlTemplate;
        } else {
            console.error('没有可用的HTML模板');
        }
    }

    bindEvents() {
        // 关闭按钮
        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                if (this._closeDialog) {
                    this._closeDialog();
                } else {
                    this.hide();
                }
            });
        }

        // 取消按钮
        const cancelBtn = this.shadowRoot.getElementById('cancelBtn');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', () => {
                if (this._closeDialog) {
                    this._closeDialog();
                } else {
                    this.hide();
                }
            });
        }

        // 提交按钮
        const submitBtn = this.shadowRoot.getElementById('submitBtn');
        if (submitBtn) {
            submitBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.submit();
            });
        }

        // 数据源类型变化事件
        const dataSourceType = this.shadowRoot.getElementById('dataSourceType');
        if (dataSourceType) {
            dataSourceType.addEventListener('change', () => {
                this.clearFieldError('dataSourceType');
                this.updateDynamicFields();
            });
        }

        // 输入框清除错误事件
        const nameInput = this.shadowRoot.getElementById('dataSourceName');
        if (nameInput) {
            nameInput.addEventListener('input', () => {
                this.clearFieldError('dataSourceName');
            });
        }

        // ESC键关闭
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.hasAttribute('show')) {
                this.hide();
            }
        });
    }

    updateDynamicFields() {
        const dataSourceType = this.shadowRoot.getElementById('dataSourceType').value;
        const dynamicFieldsContainer = this.shadowRoot.getElementById('dynamicFields');
        
        if (!dataSourceType) {
            dynamicFieldsContainer.style.display = 'none';
            dynamicFieldsContainer.innerHTML = '';
            return;
        }

        let dynamicFieldsHTML = '';

        switch (dataSourceType) {
            case 'dameng':
                dynamicFieldsHTML = `
                    <div class="form-group">
                        <label class="form-label required">Database Name</label>
                        <input type="text" class="form-control" id="damengDatabase" placeholder="请输入达梦数据库名称" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label required">Schema</label>
                        <input type="text" class="form-control" id="damengSchema" placeholder="请输入Schema名称" required>
                    </div>
                `;
                break;
            case 'iotdb':
                dynamicFieldsHTML = `
                    <div class="form-group">
                        <label class="form-label required">Storage Group</label>
                        <input type="text" class="form-control" id="iotdbStorageGroup" placeholder="请输入存储组名称" required>
                    </div>
                `;
                break;
            case 'mongodb':
                dynamicFieldsHTML = `
                    <div class="form-group">
                        <label class="form-label">Authentication Database</label>
                        <input type="text" class="form-control" id="mongoAuthDatabase" placeholder="admin" value="admin">
                    </div>
                `;
                break;
            case 'elasticsearch':
                dynamicFieldsHTML = `
                    <div class="form-group">
                        <label class="form-label">Index Pattern</label>
                        <input type="text" class="form-control" id="esIndexPattern" placeholder="请输入索引模式">
                    </div>
                `;
                break;
            case 'influxdb':
                dynamicFieldsHTML = `
                    <div class="form-group">
                        <label class="form-label required">Organization</label>
                        <input type="text" class="form-control" id="influxOrg" placeholder="请输入组织名称" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label required">Bucket</label>
                        <input type="text" class="form-control" id="influxBucket" placeholder="请输入存储桶名称" required>
                    </div>
                `;
                break;
            case 'redis':
                dynamicFieldsHTML = `
                    <div class="form-group">
                        <label class="form-label">Database</label>
                        <input type="number" class="form-control" id="redisDatabase" placeholder="0" value="0" min="0" max="15">
                    </div>
                `;
                break;
        }

        if (dynamicFieldsHTML) {
            dynamicFieldsContainer.innerHTML = dynamicFieldsHTML;
            dynamicFieldsContainer.style.display = 'block';
        } else {
            dynamicFieldsContainer.style.display = 'none';
            dynamicFieldsContainer.innerHTML = '';
        }
    }

    show() {
        console.log('🔍 register-embedded show() 被调用');
        
        // 使用通用弹窗管理器
        const modal = window.modalManager.show(this, {
            maxWidth: '800px'
        });
        
        // 绑定组件内部事件
        this.bindModalEvents(modal);
        
        console.log('🔍 show() 方法执行完成');
    }

    hide() {
        console.log('🔍 register-embedded hide() 被调用');
        window.modalManager.hide();
        // 隐藏时也清除验证错误
        this.clearValidationErrors();
    }

    bindModalEvents(modal) {
        // 等待DOM更新后绑定事件
        setTimeout(() => {
            const modalElement = modal.modal;
            
            // 绑定关闭按钮
            const closeBtn = modalElement.querySelector('#closeBtn');
            if (closeBtn) {
                closeBtn.addEventListener('click', () => {
                    this.hide();
                });
            }
            
            // 绑定取消按钮
            const cancelBtn = modalElement.querySelector('#cancelBtn');
            if (cancelBtn) {
                cancelBtn.addEventListener('click', () => {
                    this.hide();
                });
            }
            
            // 绑定提交按钮
            const submitBtn = modalElement.querySelector('#submitBtn');
            if (submitBtn) {
                submitBtn.addEventListener('click', () => {
                    this.handleSubmit();
                });
            }
            
            // 绑定数据源类型变化事件
            const dataSourceType = modalElement.querySelector('#dataSourceType');
            if (dataSourceType) {
                dataSourceType.addEventListener('change', () => {
                    this.handleDataSourceTypeChange();
                });
            }
            
            console.log('🔍 事件绑定完成');
        }, 100);
    }

    handleSubmit() {
        console.log('🔍 handleSubmit 被调用');
        // 清除之前的错误状态
        this.clearValidationErrors();
        
        // 获取表单元素
        const nameInput = this.shadowRoot.getElementById('dataSourceName');
        const typeSelect = this.shadowRoot.getElementById('dataSourceType');
        const hostInput = this.shadowRoot.getElementById('host');
        const portInput = this.shadowRoot.getElementById('port');
        const usernameInput = this.shadowRoot.getElementById('username');
        const passwordInput = this.shadowRoot.getElementById('password');
        
        let hasError = false;
        
        // 验证必填字段
        if (!nameInput?.value?.trim()) {
            this.showFieldError('dataSourceName', '请输入数据源名称');
            hasError = true;
        }
        
        if (!typeSelect?.value) {
            this.showFieldError('dataSourceType', '请选择数据源类型');
            hasError = true;
        }
        
        if (!hostInput?.value?.trim()) {
            this.showFieldError('host', '请输入主机地址');
            hasError = true;
        }
        
        if (!portInput?.value) {
            this.showFieldError('port', '请输入端口号');
            hasError = true;
        }

        if (!usernameInput?.value?.trim()) {
            this.showFieldError('username', '请输入用户名');
            hasError = true;
        }

        if (!passwordInput?.value) {
            this.showFieldError('password', '请输入密码');
            hasError = true;
        }
        
        // 如果有验证错误，不继续提交
        if (hasError) {
            // 滚动到第一个错误位置
            const firstErrorField = this.shadowRoot.querySelector('.form-group.error');
            if (firstErrorField) {
                firstErrorField.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
            return;
        }
        
        // 调用submit方法进行API调用
        this.submit();
    }

    handleDataSourceTypeChange() {
        console.log('🔍 handleDataSourceTypeChange 被调用');
        // 这里添加数据源类型变化逻辑
        const typeSelect = this.shadowRoot.getElementById('dataSourceType');
        const selectedType = typeSelect?.value;
        console.log('🔍 选择的数据源类型:', selectedType);
        
        // 根据不同类型显示不同的字段
        this.showDynamicFields(selectedType);
    }

    showDynamicFields(dataSourceType) {
        console.log('🔍 showDynamicFields 被调用，类型:', dataSourceType);
        const dynamicFields = this.shadowRoot.getElementById('dynamicFields');
        
        if (!dynamicFields) return;
        
        // 清空现有字段
        dynamicFields.innerHTML = '';
        
        // 根据数据源类型添加特定字段
        switch(dataSourceType) {
            case 'api':
                dynamicFields.innerHTML = `
                    <div class="form-group">
                        <label class="form-label">API URL</label>
                        <input type="url" class="form-control" id="apiUrl" placeholder="请输入API地址">
                    </div>
                    <div class="form-group">
                        <label class="form-label">API Key</label>
                        <input type="text" class="form-control" id="apiKey" placeholder="请输入API Key">
                    </div>
                `;
                break;
            case 'file':
                dynamicFields.innerHTML = `
                    <div class="form-group">
                        <label class="form-label">文件路径</label>
                        <input type="text" class="form-control" id="filePath" placeholder="请输入文件路径">
                    </div>
                    <div class="form-group">
                        <label class="form-label">文件格式</label>
                        <select class="form-control" id="fileFormat">
                            <option value="csv">CSV</option>
                            <option value="json">JSON</option>
                            <option value="xml">XML</option>
                            <option value="excel">Excel</option>
                        </select>
                    </div>
                `;
                break;
            default:
                // 其他类型可能需要特定字段
                break;
        }
        
        dynamicFields.style.display = 'block';
    }

    resetForm() {
        const nameInput = this.shadowRoot.getElementById('dataSourceName');
        const typeSelect = this.shadowRoot.getElementById('dataSourceType');
        const descInput = this.shadowRoot.getElementById('description');
        const hostInput = this.shadowRoot.getElementById('host');
        const portInput = this.shadowRoot.getElementById('port');
        const userInput = this.shadowRoot.getElementById('username');
        const passInput = this.shadowRoot.getElementById('password');
        const dbInput = this.shadowRoot.getElementById('database');
        const dynamicFields = this.shadowRoot.getElementById('dynamicFields');

        if (nameInput) nameInput.value = '';
        if (typeSelect) typeSelect.value = '';
        if (descInput) descInput.value = '';
        if (hostInput) hostInput.value = '';
        if (portInput) portInput.value = '';
        if (userInput) userInput.value = '';
        if (passInput) passInput.value = '';
        if (dbInput) dbInput.value = '';
        if (dynamicFields) {
            dynamicFields.style.display = 'none';
            dynamicFields.innerHTML = '';
        }
    }

    async submit() {
        // 清除之前的错误状态
        this.clearValidationErrors();
        
        const formData = this.getFormData();
        
        let hasError = false;
        
        // 验证数据源名称
        if (!formData.alias) {
            this.showFieldError('dataSourceName', '请输入数据源名称');
            hasError = true;
        }
        
        // 验证数据源类型
        if (!formData.type) {
            this.showFieldError('dataSourceType', '请选择数据源类型');
            hasError = true;
        }
        
        // 验证主机地址
        if (!formData.host) {
            this.showFieldError('host', '请输入主机地址');
            hasError = true;
        }
        
        // 验证端口
        if (!formData.port) {
            this.showFieldError('port', '请输入端口号');
            hasError = true;
        }
        
        if (hasError) {
            this.showMessage('请填写必填字段', 'error');
            return;
        }

        try {
            // 转换为后端格式
            const backendData = window.AppConfig.transformFormData(formData, 'datasource');
            
            const response = await this.apiCall(window.AppConfig.getApiUrl('datasource', 'register'), 'POST', backendData);
            
            if (response.code === 200) {
                // 延迟关闭窗口，让用户看到响应信息
                setTimeout(() => {
                    if (this._closeDialog) {
                        this._closeDialog();
                    } else {
                        this.hide();
                    }
                    
                    this.dispatchEvent(new CustomEvent('submit-success', {
                        detail: { formData: backendData, response },
                        bubbles: true,
                        composed: true
                    }));
                }, 1000); // 1秒后关闭，让main.js处理成功消息
            } else {
                // 显示后端返回的错误消息 - 使用工作区消息
                const errorMessage = response.message || '注册失败';
                this.showWorkspaceMessage(errorMessage, 'error');
                
                // 延迟关闭窗口，让用户看到错误信息
                setTimeout(() => {
                    this.hide();
                }, 1000); // 1秒后关闭
            }
        } catch (error) {
            console.error('注册数据源失败:', error);
            this.showWorkspaceMessage('注册失败，请稍后重试', 'error');
            
            // 延迟关闭窗口，让用户看到错误信息
            setTimeout(() => {
                this.hide();
            }, 1000); // 1秒后关闭
        }
    }

    showFieldError(fieldId, message) {
        const field = this.shadowRoot.getElementById(fieldId);
        let errorElement = this.shadowRoot.getElementById(`${fieldId}Error`);
        const formGroup = field?.closest('.form-group');
        
        // 如果错误元素不存在，创建一个
        if (!errorElement && formGroup) {
            errorElement = document.createElement('div');
            errorElement.id = `${fieldId}Error`;
            errorElement.className = 'error-message';
            formGroup.appendChild(errorElement);
        }
        
        if (field) {
            field.classList.add('error');
        }
        
        if (errorElement) {
            errorElement.textContent = message;
            errorElement.style.display = 'block';
            errorElement.classList.add('show');
        }
        
        if (formGroup) {
            formGroup.classList.add('error');
        }
    }

    clearFieldError(fieldId) {
        const field = this.shadowRoot.getElementById(fieldId);
        const errorElement = this.shadowRoot.getElementById(fieldId + 'Error');
        const formGroup = field?.closest('.form-group');
        
        if (field) {
            field.classList.remove('error');
        }
        if (errorElement) {
            errorElement.classList.remove('show');
        }
        if (formGroup) {
            formGroup.classList.remove('error');
        }
    }

    clearValidationErrors() {
        // 清除所有错误状态
        const errorFields = this.shadowRoot.querySelectorAll('.form-control.error');
        const errorMessages = this.shadowRoot.querySelectorAll('.error-message');
        const errorGroups = this.shadowRoot.querySelectorAll('.form-group.error');
        
        errorFields.forEach(field => field.classList.remove('error'));
        errorMessages.forEach(msg => {
            msg.classList.remove('show');
            msg.style.display = 'none';
        });
        errorGroups.forEach(group => group.classList.remove('error'));
    }

    getFormData() {
        const nameInput = this.shadowRoot.getElementById('dataSourceName');
        const typeSelect = this.shadowRoot.getElementById('dataSourceType');
        const descInput = this.shadowRoot.getElementById('description');
        const hostInput = this.shadowRoot.getElementById('host');
        const portInput = this.shadowRoot.getElementById('port');
        const userInput = this.shadowRoot.getElementById('username');
        const passInput = this.shadowRoot.getElementById('password');
        const dbInput = this.shadowRoot.getElementById('database');
        
        const dataSourceType = typeSelect?.value || '';
        const baseData = {
            alias: nameInput?.value || '',
            type: dataSourceType,
            description: descInput?.value || '',
            host: hostInput?.value || '',
            port: parseInt(portInput?.value) || 3306,
            username: userInput?.value || '',
            password: passInput?.value || '',
            database: dbInput?.value || ''
        };
        
        console.log('基础表单数据:', baseData);

        // 添加动态字段数据
        switch (dataSourceType) {
            case 'dameng':
                baseData.damengDatabase = this.shadowRoot.getElementById('damengDatabase')?.value || '';
                baseData.damengSchema = this.shadowRoot.getElementById('damengSchema')?.value || '';
                break;
            case 'iotdb':
                baseData.storageGroup = this.shadowRoot.getElementById('iotdbStorageGroup')?.value || '';
                break;
            case 'mongodb':
                baseData.authDatabase = this.shadowRoot.getElementById('mongoAuthDatabase')?.value || 'admin';
                break;
            case 'elasticsearch':
                baseData.indexPattern = this.shadowRoot.getElementById('esIndexPattern')?.value || '';
                break;
            case 'influxdb':
                baseData.organization = this.shadowRoot.getElementById('influxOrg')?.value || '';
                baseData.bucket = this.shadowRoot.getElementById('influxBucket')?.value || '';
                break;
            case 'redis':
                baseData.redisDatabase = parseInt(this.shadowRoot.getElementById('redisDatabase')?.value) || 0;
                break;
        }

        return baseData;
    }

    async apiCall(url, method = 'GET', data = null) {
        const options = {
            method: method,
            headers: window.AppConfig.getAuthHeaders(),
        };

        if (data && method !== 'GET') {
            options.body = JSON.stringify(data);
        }

        const response = await fetch(url, options);
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const result = await response.json();
        return result;
    }

    showMessage(message, type = 'info') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            // 直接使用统一的 showToast
            window.CommonUtils.showToast(message, type);
        } else {
            // 简单的回退实现
            console.warn(`[${type}] ${message}`);
        }
    }

    // 在工作区显示消息提示（与main.js保持一致）
    showWorkspaceMessage(message, type = 'info') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            // 直接使用统一的 showToast
            window.CommonUtils.showToast(message, type);
        } else {
            // 简单的回退实现
            console.warn(`[${type}] ${message}`);
        }
    }
}

// 注册自定义元素
customElements.define('register-data-resource-embedded', RegisterDataResourceEmbedded);
