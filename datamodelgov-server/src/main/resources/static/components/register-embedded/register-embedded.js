/**
 * 注册异构数据源内嵌页面组件
 * 基于 model-edit 模式重写 - 弹窗模式
 */
class RegisterDataResourceEmbedded extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
    }

    async connectedCallback() {
        await this.loadResources();
        this.render();
        this.bindEvents();
        this.hide(); // 默认隐藏
    }

    async loadResources() {
        // 加载CSS
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/register-embedded/register-embedded.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        // 加载HTML模板
        try {
            const response = await fetch('./components/register-embedded/register-embedded.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const html = await response.text();
            this.shadowRoot.innerHTML += html;
            console.log('Register embedded HTML template loaded successfully');
        } catch (error) {
            console.error('Failed to load HTML template:', error);
        }
    }

    render() {
        // HTML已通过loadResources加载
    }

    bindEvents() {
        // 禁用所有number类型input的鼠标滚轮改变值功能
        this.shadowRoot.querySelectorAll('input[type="number"]').forEach(input => {
            input.addEventListener('wheel', (e) => e.preventDefault());
        });

        // 关闭按钮
        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        if (closeBtn) {
            closeBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.hide();
            });
        }

        // 取消按钮
        const cancelBtn = this.shadowRoot.getElementById('cancelBtn');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.hide();
            });
        }

        // 提交按钮
        const submitBtn = this.shadowRoot.getElementById('submitBtn');
        if (submitBtn) {
            submitBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.submit();
            });
        }

        // 数据源类型变化事件
        const dataSourceType = this.shadowRoot.getElementById('dataSourceType');
        if (dataSourceType) {
            dataSourceType.addEventListener('change', () => {
                this.toggleEngineField();
            });
        }

        // 是否读取原有数据变化事件
        const hasDataCheckbox = this.shadowRoot.getElementById('hasData');
        if (hasDataCheckbox) {
            hasDataCheckbox.addEventListener('change', () => {
                this.updateDummyDirRequired();
            });
        }

        // 是否只读变化事件
        const isReadOnlyCheckbox = this.shadowRoot.getElementById('isReadOnly');
        if (isReadOnlyCheckbox) {
            isReadOnlyCheckbox.addEventListener('change', (e) => {
                if (!e.target.checked) {
                    this.showMessage('非只读数据源将无法卸载！', 'warning');
                }
            });
        }
    }

    show() {
        console.log('RegisterDataResourceEmbedded show() called');
        // 使用多种方式确保显示
        this.removeAttribute('hidden');
        this.style.display = 'flex';
        console.log('RegisterDataResourceEmbedded: hidden attribute removed and display flex');
    }

    hide() {
        console.log('RegisterDataResourceEmbedded hide() called');
        // 使用多种方式确保隐藏
        this.setAttribute('hidden', '');
        this.style.display = 'none';
        console.log('RegisterDataResourceEmbedded: hidden attribute set and display none');
    }

    toggleEngineField() {
        const dataSourceType = this.shadowRoot.getElementById('dataSourceType');

        // Hide all storage-specific fields first
        const allFieldGroups = this.shadowRoot.querySelectorAll('.storage-specific-fields');
        allFieldGroups.forEach(group => group.style.display = 'none');

        // Hide auth fields by default
        const authFields = this.shadowRoot.getElementById('authFields');
        if (authFields) {
            authFields.style.display = 'none';
        }

        // 先清除relational的自动填充设置
        this.clearRelationalSettings();

        // 切换任意数据源类型时都默认勾选"是否只读"
        this.autoCheckReadOnly();

        if (dataSourceType) {
            // Show relevant fields based on storage engine type
            switch(dataSourceType.value) {
                case '1': // IoTDB 1.2
                    this.showFieldGroup('iotdbFields');
                    authFields.style.display = 'block';
                    break;
                case '2': // InfluxDB
                    this.showFieldGroup('influxdbFields');
                    authFields.style.display = 'block';
                    break;
                case '3': // Filesystem
                    this.showFieldGroup('filesystemFields');
                    // authFields remains hidden
                    // 更新历史数据文件读取目录的必填状态
                    this.updateDummyDirRequired();
                    break;
                case '4': // Relational
                    this.showFieldGroup('relationalFields');
                    authFields.style.display = 'block';
                    // 自动填充模式前缀为"relational"
                    this.autoFillRelationalSettings();
                    break;
                case '5': // MongoDB
                    this.showFieldGroup('mongodbFields');
                    // authFields remains hidden
                    break;
                case '6': // Redis
                    this.showFieldGroup('redisFields');
                    authFields.style.display = 'block';
                    break;
            }
        }
    }
    
    showFieldGroup(groupId) {
        const fieldGroup = this.shadowRoot.getElementById(groupId);
        if (fieldGroup) {
            fieldGroup.style.display = 'block';
        }
    }

    updateDummyDirRequired() {
        const dataSourceType = this.shadowRoot.getElementById('dataSourceType');
        const hasDataCheckbox = this.shadowRoot.getElementById('hasData');
        const dummyDirLabel = this.shadowRoot.querySelector('#dummyDir').parentElement.querySelector('.form-label');
        
        // 只在filesystem类型下处理
        if (dataSourceType && dataSourceType.value === '3' && hasDataCheckbox && dummyDirLabel) {
            if (hasDataCheckbox.checked) {
                // 添加required类显示红色星号
                if (!dummyDirLabel.classList.contains('required')) {
                    dummyDirLabel.classList.add('required');
                }
            } else {
                // 移除required类
                dummyDirLabel.classList.remove('required');
            }
        }
    }

    autoCheckReadOnly() {
        // 自动勾选"是否只读"
        const isReadOnlyCheckbox = this.shadowRoot.getElementById('isReadOnly');
        if (isReadOnlyCheckbox) {
            isReadOnlyCheckbox.checked = true;
            console.log('自动勾选"是否只读"');
        }
    }

    autoFillRelationalSettings() {
        // 自动填充模式前缀为"relational"
        const schemaPrefixInput = this.shadowRoot.getElementById('schemaPrefix');
        if (schemaPrefixInput) {
            // 只有当输入框为空时才自动填充，避免覆盖用户手动输入的内容
            if (!schemaPrefixInput.value || schemaPrefixInput.value.trim() === '') {
                schemaPrefixInput.value = 'relational';
                console.log('自动填充模式前缀为: relational');
            }
        }
    }

    clearRelationalSettings() {
        // 清除模式前缀（仅当值为"relational"时清除）
        const schemaPrefixInput = this.shadowRoot.getElementById('schemaPrefix');
        if (schemaPrefixInput && schemaPrefixInput.value === 'relational') {
            schemaPrefixInput.value = '';
            console.log('清除自动填充的模式前缀');
        }

        // 不再取消勾选"是否只读"，保持用户的选择
    }

    async submit() {
        // 获取表单数据
        const type = this.shadowRoot.getElementById('dataSourceType')?.value;
        const host = this.shadowRoot.getElementById('host')?.value;
        const port = this.shadowRoot.getElementById('port')?.value;
        
        // 获取通用配置字段
        const hasData = this.shadowRoot.getElementById('hasData')?.checked || false;
        const isReadOnly = this.shadowRoot.getElementById('isReadOnly')?.checked || false;
        const dataPrefix = this.shadowRoot.getElementById('dataPrefix')?.value;
        const schemaPrefix = this.shadowRoot.getElementById('schemaPrefix')?.value;
        const description = this.shadowRoot.getElementById('description')?.value;
        
        // 只对需要认证的存储引擎类型获取用户名密码
        let username = null;
        let password = null;
        if (type === '1' || type === '2' || type === '4' || type === '6') {
            username = this.shadowRoot.getElementById('username')?.value;
            password = this.shadowRoot.getElementById('password')?.value;
        }

        // 类型映射
        const typeMapping = {
            '1': 1,  // iotdb12
            '2': 2,  // influxdb
            '3': 3,  // filesystem
            '4': 4,  // relational
            '5': 5,  // mongodb
            '6': 6   // redis
        };
        
        const data = {
            storageEngineType: typeMapping[type] || null,
            ip: host,
            port: parseInt(port),
            hasData: hasData,
            isReadOnly: isReadOnly
        };
        
        // 添加可选字段（如果不为空）
        if (dataPrefix && dataPrefix.trim()) {
            data.dataPrefix = dataPrefix.trim();
        }
        // 模式前缀为必填项
        data.schemaPrefix = schemaPrefix ? schemaPrefix.trim() : '';
        
        // 添加描述信息
        if (description && description.trim()) {
            data.description = description.trim();
        }

        // 只对需要用户名密码的存储引擎类型添加这些字段
        if (username && (data.storageEngineType === 1 || data.storageEngineType === 2 || data.storageEngineType === 4 || data.storageEngineType === 6)) {
            data.username = username;
        }
        if (password && (data.storageEngineType === 1 || data.storageEngineType === 2 || data.storageEngineType === 4 || data.storageEngineType === 6)) {
            data.password = password;
        }
        
        // 根据存储引擎类型添加特定字段
        switch(data.storageEngineType) {
            case 1: // IoTDB 1.2
                this.addIotdbFields(data);
                break;
            case 2: // InfluxDB
                this.addInfluxdbFields(data);
                break;
            case 3: // Filesystem
                this.addFilesystemFields(data);
                break;
            case 4: // Relational
                this.addRelationalFields(data);
                break;
            case 5: // MongoDB
                this.addMongodbFields(data);
                break;
            case 6: // Redis
                this.addRedisFields(data);
                break;
        }
        
        // 验证必填字段
        if (!this.validateForm(data)) {
            return;
        }
        
        // 调试：打印发送的JSON数据
        console.log('Sending JSON data:', JSON.stringify(data, null, 2));
        
        try {
            // 直接发送数据，不使用字段转换（前端字段名已与后端匹配）
            const result = await window.AppConfig.post('datasource', 'register', data);
            
            if (result.success) {
                this.showMessage('数据源注册成功', 'success');
                console.log('Registration successful, closing modal...');
                
                // 重新加载左侧数据资源库
                console.log('🔄 数据源注册成功，准备调用 loadDataSourceTree');
                if (window.loadDataSourceTree) {
                    console.log('🔄 调用 window.loadDataSourceTree');
                    window.loadDataSourceTree();
                } else {
                    console.error('❌ window.loadDataSourceTree 不存在');
                }
                
                // 重新加载project tree
                console.log('🔄 数据源注册成功，准备调用 loadProjectTree');
                if (window.loadProjectTree) {
                    console.log('🔄 调用 window.loadProjectTree');
                    window.loadProjectTree();
                } else {
                    console.error('❌ window.loadProjectTree 不存在');
                }
                
                // 刷新数据源列表
                const dataSourceList = document.getElementById('dataSourceList');
                if (dataSourceList && typeof dataSourceList.loadDataSources === 'function') {
                    dataSourceList.loadDataSources();
                }
            } else {
                console.log('Registration failed, result:', result);
                this.showMessage(result.message || '注册失败', 'error');
            }
            
            // 无论成功失败都关闭弹窗
            this.hide();
        } catch (error) {
            console.error('注册数据源失败:', error);
            this.showMessage('注册失败，请稍后重试', 'error');
            // 异常情况下也要关闭弹窗
            this.hide();
        }
    }
    
    addIotdbFields(data) {
        const sessionPoolSize = this.shadowRoot.getElementById('sessionPoolSize')?.value;
        if (sessionPoolSize) {
            data.sessionPoolSize = parseInt(sessionPoolSize);
        }
    }
    
    addInfluxdbFields(data) {
        const url = this.shadowRoot.getElementById('influxdbUrl')?.value;
        const token = this.shadowRoot.getElementById('influxdbToken')?.value;
        const organization = this.shadowRoot.getElementById('influxdbOrganization')?.value;
        
        if (url) data.url = url;
        if (token) data.token = token;
        if (organization) data.organization = organization;
    }
    
    addFilesystemFields(data) {
        const iginxPort = this.shadowRoot.getElementById('iginxPort')?.value;
        const dir = this.shadowRoot.getElementById('dataDir')?.value;
        const dummyDir = this.shadowRoot.getElementById('dummyDir')?.value;
        const embeddedPrefix = this.shadowRoot.getElementById('embeddedPrefix')?.value;
        const dataStruct = this.shadowRoot.getElementById('dataStruct')?.value;
        const dummyStruct = this.shadowRoot.getElementById('dummyStruct')?.value;
        
        if (iginxPort) data.iginxPort = parseInt(iginxPort);
        if (dir) data.dir = dir;
        if (dummyDir) data.dummyDir = dummyDir;
        if (embeddedPrefix) data.embeddedPrefix = embeddedPrefix;
        if (dataStruct) data.dataStruct = dataStruct;
        if (dummyStruct) data.dummyStruct = dummyStruct;
    }
    
    addRelationalFields(data) {
        const engine = this.shadowRoot.getElementById('engine')?.value;
        const metaPropertiesPath = this.shadowRoot.getElementById('metaPropertiesPath')?.value;
        const connectionTimeout = this.shadowRoot.getElementById('connectionTimeout')?.value;
        const idleTimeout = this.shadowRoot.getElementById('idleTimeout')?.value;
        const maximumPoolSize = this.shadowRoot.getElementById('maximumPoolSize')?.value;
        const minimumIdle = this.shadowRoot.getElementById('minimumIdle')?.value;
        
        if (engine) data.engine = engine;
        if (metaPropertiesPath) data.metaPropertiesPath = metaPropertiesPath;
        if (connectionTimeout) data.connectionTimeout = parseInt(connectionTimeout);
        if (idleTimeout) data.idleTimeout = parseInt(idleTimeout);
        if (maximumPoolSize) data.maximumPoolSize = parseInt(maximumPoolSize);
        if (minimumIdle) data.minimumIdle = parseInt(minimumIdle);
    }
    
    addMongodbFields(data) {
        const uri = this.shadowRoot.getElementById('mongodbUri')?.value;
        const schemaSampleSize = this.shadowRoot.getElementById('schemaSampleSize')?.value;
        const dummySampleSize = this.shadowRoot.getElementById('dummySampleSize')?.value;
        
        if (uri) data.uri = uri;
        if (schemaSampleSize) data.schemaSampleSize = parseInt(schemaSampleSize);
        if (dummySampleSize) data.dummySampleSize = parseInt(dummySampleSize);
    }
    
    addRedisFields(data) {
        const timeout = this.shadowRoot.getElementById('redisTimeout')?.value;
        if (timeout) {
            data.timeout = parseInt(timeout);
        }
    }
    
    validateForm(data) {
        // 基础验证
        if (!data.ip || !data.port || !data.storageEngineType) {
            this.showMessage('请填写必填字段并选择有效的数据源类型', 'error');
            return false;
        }
        
        // 模式前缀为必填项
        if (!data.schemaPrefix || data.schemaPrefix.trim() === '') {
            this.showMessage('模式前缀为必填项', 'error');
            return false;
        }
        
        // 模式前缀不能包含"_system"
        if (data.schemaPrefix && data.schemaPrefix.includes('_system')) {
            this.showMessage('模式前缀不能包含"_system"', 'error');
            return false;
        }
        
        // 特定类型验证
        switch(data.storageEngineType) {
            case 2: // InfluxDB - URL必填
                if (!data.url) {
                    this.showMessage('InfluxDB URL为必填项', 'error');
                    return false;
                }
                break;
            case 3: // Filesystem - iginxPort必填
                if (!data.iginxPort) {
                    this.showMessage('IGinX节点端口为必填项', 'error');
                    return false;
                }
                // Filesystem读取原有数据时，历史数据文件读取目录必填
                if (data.hasData && !data.dummyDir) {
                    this.showMessage('读取原有数据时，历史数据文件读取目录为必填项', 'error');
                    return false;
                }
                break;
            case 4: // Relational - engine必填
                if (!data.engine) {
                    this.showMessage('数据库引擎为必填项', 'error');
                    return false;
                }
                // MySQL需要metaPropertiesPath
                // if (data.engine === 'mysql' && !data.metaPropertiesPath) {
                //     this.showMessage('MySQL存储引擎必须提供元数据配置文件路径', 'error');
                //     return false;
                // }
                break;
        }
        
        return true;
    }

    showMessage(message, type = 'info') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console.warn('CommonUtils.showToast not available');
        }
    }
}

// 注册自定义元素
customElements.define('register-data-resource-embedded', RegisterDataResourceEmbedded);
