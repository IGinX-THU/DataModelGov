/**
 * 导入数据组件 - 基于Model Upload组件结构
 */
class ImportDataComponent extends HTMLElement {
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
            cssLink.href = './components/import-data/import-data.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        // 加载HTML模板
        try {
            const response = await fetch('./components/import-data/import-data.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const html = await response.text();
            this.shadowRoot.innerHTML += html;
            console.log('Import data HTML template loaded successfully');
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
            closeBtn.addEventListener('click', () => this.hide());
        }

        // 取消按钮
        const cancelBtn = this.shadowRoot.getElementById('cancelBtn');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', () => this.hide());
        }

        // 导入按钮
        const importBtn = this.shadowRoot.getElementById('importBtn');
        if (importBtn) {
            importBtn.addEventListener('click', () => this.handleImport());
        }

        // 文件选择事件
        const fileInput = this.shadowRoot.getElementById('csvFile');
        if (fileInput) {
            fileInput.addEventListener('change', (e) => this.handleFileSelect(e));
        }

        // 拖拽事件
        this.setupDragAndDrop();
    }

    setupDragAndDrop() {
        const fileUploadLabel = this.shadowRoot.querySelector('.file-upload-label');
        if (!fileUploadLabel) return;

        ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
            fileUploadLabel.addEventListener(eventName, this.preventDefaults, false);
        });

        ['dragenter', 'dragover'].forEach(eventName => {
            fileUploadLabel.addEventListener(eventName, () => {
                fileUploadLabel.classList.add('dragover');
            }, false);
        });

        ['dragleave', 'drop'].forEach(eventName => {
            fileUploadLabel.addEventListener(eventName, () => {
                fileUploadLabel.classList.remove('dragover');
            }, false);
        });

        fileUploadLabel.addEventListener('drop', (e) => {
            e.preventDefault();
            e.stopPropagation();
            const files = e.dataTransfer.files;
            console.log('拖拽文件数量:', files.length);
            if (files.length > 0) {
                console.log('拖拽的文件:', files[0].name, files[0].size);
                this.handleFileSelect({ target: { files: [files[0]] } });
            }
        }, false);
    }

    preventDefaults(e) {
        e.preventDefault();
        e.stopPropagation();
    }

    handleFileSelect(event) {
        const file = event.target.files[0];
        const csvFileError = this.shadowRoot.getElementById('csvFileError');
        const fileInput = this.shadowRoot.getElementById('csvFile');
        
        console.log('handleFileSelect被调用，文件:', file ? file.name : 'null');

        if (file) {
            // 验证文件类型
            if (!file.name.toLowerCase().endsWith('.csv')) {
                csvFileError.textContent = '仅支持CSV格式文件';
                csvFileError.classList.add('show');
                return;
            }

            // 验证文件大小（1GB）
            if (file.size > 1024 * 1024 * 1024) {
                csvFileError.textContent = '文件大小不能超过1GB';
                csvFileError.classList.add('show');
                return;
            }

            // 确保文件设置到fileInput中（拖拽时需要）
            if (!fileInput.files || fileInput.files.length === 0 || fileInput.files[0] !== file) {
                // 创建一个新的DataTransfer对象来设置文件
                const dataTransfer = new DataTransfer();
                dataTransfer.items.add(file);
                fileInput.files = dataTransfer.files;
                console.log('文件已设置到fileInput，当前files数量:', fileInput.files.length);
            }

            // 更新文件上传标签显示
            const fileUploadLabel = this.shadowRoot.querySelector('.file-upload-label');
            if (fileUploadLabel) {
                // 保持原有的input元素，只更新显示内容
                const existingInput = fileUploadLabel.querySelector('.file-input');
                fileUploadLabel.innerHTML = `
                    <div style="font-size: 48px; margin-bottom: 12px;">📄</div>
                    <div style="font-weight: 500; margin-bottom: 8px;">已选择文件: ${file.name}</div>
                    <div class="form-hint">文件大小: ${this.formatFileSize(file.size)}</div>
                `;
                // 重新添加input元素
                if (existingInput) {
                    fileUploadLabel.appendChild(existingInput);
                }
            }
            
            csvFileError.classList.remove('show');
        }
    }

    formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    async handleImport() {
        const targetPath = this.shadowRoot.getElementById('targetPath').value.trim();
        const fileInput = this.shadowRoot.getElementById('csvFile');
        const file = fileInput.files[0];
        const targetPathError = this.shadowRoot.getElementById('targetPathError');
        const csvFileError = this.shadowRoot.getElementById('csvFileError');
        const importBtn = this.shadowRoot.getElementById('importBtn');

        console.log('handleImport被调用');
        console.log('targetPath:', targetPath);
        console.log('fileInput:', fileInput);
        console.log('fileInput.files:', fileInput.files);
        console.log('file:', file);

        // 重置错误信息
        targetPathError.classList.remove('show');
        csvFileError.classList.remove('show');

        // 验证输入
        if (!targetPath) {
            targetPathError.classList.add('show');
            return;
        }

        if (!file) {
            csvFileError.textContent = '请选择CSV文件';
            csvFileError.classList.add('show');
            return;
        }

        try {
            // 禁用按钮
            importBtn.disabled = true;
            importBtn.textContent = '导入中...';

            // 显示loading
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在导入数据...');
            }

            // 创建FormData
            const formData = new FormData();
            
            // 添加配置参数作为JSON字符串
            const config = {
                targetPath: targetPath
            };
            formData.append('config', new Blob([JSON.stringify(config)], { type: 'application/json' }));
            
            // 添加文件
            formData.append('file', file);

            // 调用导入接口
            const response = await fetch(window.AppConfig.getApiUrl('data', 'import'), {
                method: 'POST',
                body: formData
            });

            const result = await response.json();

            if (result.code === 200) {
                this.showToast(result.message || '数据导入成功', 'success');
                this.hide();
                // 如果data-visualization组件存在且可见，刷新数据
                const dataViz = document.getElementById('dataVisualization');
                if (dataViz && dataViz.hasAttribute('show') && dataViz.loadData) {
                    dataViz.loadData();
                }
            } else {
                this.showToast(result.message || '数据导入失败', 'error');
            }
        } catch (error) {
            console.error('导入数据失败:', error);
            this.showToast('导入失败，请稍后重试', 'error');
        } finally {
            // 恢复按钮状态
            importBtn.disabled = false;
            importBtn.textContent = '导入';
            
            // 隐藏loading
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    showToast(message, type = 'success') {
        // 使用全局的toast提示系统
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console.warn('CommonUtils.showToast not available, falling back to console.log');
            console[type === 'error' ? 'error' : type === 'warning' ? 'warn' : 'log'](`[${type}] ${message}`);
        }
    }

    show() {
        this.removeAttribute('hidden');
        // 重置表单
        this.shadowRoot.getElementById('targetPath').value = '';
        this.shadowRoot.getElementById('csvFile').value = '';
        this.shadowRoot.getElementById('targetPathError').classList.remove('show');
        this.shadowRoot.getElementById('csvFileError').classList.remove('show');
        
        // 重置文件上传区域显示
        const fileUploadLabel = this.shadowRoot.querySelector('.file-upload-label');
        if (fileUploadLabel) {
            // 保持原有的input元素，只更新显示内容
            const existingInput = fileUploadLabel.querySelector('.file-input');
            fileUploadLabel.innerHTML = `
                <div style="font-size: 48px; margin-bottom: 12px;">📁</div>
                <div style="font-weight: 500; margin-bottom: 8px;">点击选择CSV文件或拖拽文件到此处</div>
                <div class="form-hint">仅支持CSV格式文件，文件大小不超过1GB</div>
            `;
            // 重新添加input元素
            if (existingInput) {
                fileUploadLabel.appendChild(existingInput);
            }
        }
    }

    hide() {
        this.setAttribute('hidden', '');
    }
}

// 注册自定义元素
customElements.define('import-data', ImportDataComponent);
