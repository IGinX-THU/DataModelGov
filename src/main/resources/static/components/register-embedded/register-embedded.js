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
        const engineField = this.shadowRoot.getElementById('engineField');
        
        if (dataSourceType && engineField) {
            // 只有选择relational(4)时才显示engine字段
            if (dataSourceType.value === '4') {
                engineField.style.display = 'block';
            } else {
                engineField.style.display = 'none';
            }
        }
    }

    async submit() {
        // 获取表单数据
        const type = this.shadowRoot.getElementById('dataSourceType')?.value;
        const host = this.shadowRoot.getElementById('host')?.value;
        const port = this.shadowRoot.getElementById('port')?.value;
        const username = this.shadowRoot.getElementById('username')?.value;
        const password = this.shadowRoot.getElementById('password')?.value;
        const engine = this.shadowRoot.getElementById('engine')?.value;
        
        // 类型映射
        const typeMapping = {
            '0': 0,  // unknown
            '1': 1,  // iotdb12
            '2': 2,  // influxdb
            '3': 3,  // filesystem
            '4': 4,  // relational
            '5': 5,  // mongodb
            '6': 6   // redis
        };
        
        const data = {
            storageEngineType: typeMapping[type] || 0,
            ip: host,
            port: parseInt(port),
            username: username,
            password: password
        };
        
        // 当storageEngineType为4（关系型数据库）时，添加engine字段
        if (data.storageEngineType === 4 && engine) {
            data.engine = engine;
        }
        
        // 简单验证
        if (!data.ip || !data.port || data.storageEngineType === 0) {
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
                console.log('Registration successful, closing modal...');
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
