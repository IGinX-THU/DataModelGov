/**
 * 上传模型文件组件
 * 使用 Web Components (Custom Elements + Shadow DOM) 实现
 */
class ModelUpload extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.selectedFile = null;
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
            cssLink.href = './components/model-upload/model-upload.css';
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
            const response = await fetch('./components/model-upload/model-upload.html');
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
            <div class="upload-container">
                <div class="upload-header">
                    <h3 class="upload-title">上传模型文件</h3>
                    <button class="close-btn" id="closeBtn">&times;</button>
                </div>
                
                <form id="uploadForm">
                    <div class="form-group">
                        <label class="form-label required">模型文件</label>
                        <div class="file-upload-area" id="fileUploadArea">
                            <div class="upload-content">
                                <div class="upload-icon">📁</div>
                                <p class="upload-text">点击选择文件或拖拽文件到此处</p>
                                <p class="upload-hint">支持 .pkl, .joblib, .h5, .pt, .pth, .onnx, .pb 格式</p>
                                <input type="file" class="file-input" id="modelFile" accept=".pkl,.joblib,.h5,.pt,.pth,.onnx,.pb" required>
                            </div>
                        </div>
                        <div class="file-info" id="fileInfo" style="display: none;">
                            <div class="file-details">
                                <span class="file-name" id="fileName"></span>
                                <span class="file-size" id="fileSize"></span>
                            </div>
                            <button type="button" class="remove-file-btn" id="removeFileBtn">&times;</button>
                        </div>
                    </div>

                    <div class="form-group">
                        <label class="form-label required">是否关联已有模型</label>
                        <select class="form-control form-select" id="isRelatedModel" required>
                            <option value="">请选择</option>
                            <option value="yes">是</option>
                            <option value="no">否</option>
                        </select>
                    </div>

                    <div class="form-group">
                        <label class="form-label required">名称</label>
                        <input type="text" class="form-control" id="modelName" placeholder="请输入模型名称" required>
                    </div>

                    <div class="form-group">
                        <label class="form-label required">版本号</label>
                        <input type="text" class="form-control" id="modelVersion" placeholder="请输入版本号" required>
                    </div>

                    <div class="form-actions">
                        <button type="button" class="btn btn-secondary" id="cancelBtn">
                            取消
                        </button>
                        <button type="button" class="btn btn-primary" id="uploadBtn">
                            确认上传
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
                this.hide();
            });
        }

        // 取消按钮
        const cancelBtn = this.shadowRoot.getElementById('cancelBtn');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', () => {
                this.hide();
            });
        }

        // 上传按钮
        const uploadBtn = this.shadowRoot.getElementById('uploadBtn');
        if (uploadBtn) {
            uploadBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.upload();
            });
        }

        // 文件选择
        const fileInput = this.shadowRoot.getElementById('modelFile');
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
        
        if (fileInput) {
            fileInput.addEventListener('change', (e) => {
                this.handleFileSelect(e.target.files[0]);
            });
        }

        // 拖拽上传
        if (fileUploadArea) {
            fileUploadArea.addEventListener('dragover', (e) => {
                e.preventDefault();
                fileUploadArea.classList.add('dragover');
            });

            fileUploadArea.addEventListener('dragleave', (e) => {
                e.preventDefault();
                fileUploadArea.classList.remove('dragover');
            });

            fileUploadArea.addEventListener('drop', (e) => {
                e.preventDefault();
                fileUploadArea.classList.remove('dragover');
                const files = e.dataTransfer.files;
                if (files.length > 0) {
                    this.handleFileSelect(files[0]);
                }
            });
        }

        // 移除文件按钮
        const removeFileBtn = this.shadowRoot.getElementById('removeFileBtn');
        if (removeFileBtn) {
            removeFileBtn.addEventListener('click', () => {
                this.removeFile();
            });
        }

        // ESC键关闭
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.hasAttribute('show')) {
                this.hide();
            }
        });
    }

    handleFileSelect(file) {
        if (!file) return;

        // 验证文件类型
        const allowedTypes = ['.pkl', '.joblib', '.h5', '.pt', '.pth', '.onnx', '.pb'];
        const fileExtension = '.' + file.name.split('.').pop().toLowerCase();
        
        if (!allowedTypes.includes(fileExtension)) {
            this.showMessage('不支持的文件格式，请选择支持的模型文件格式', 'error');
            return;
        }

        // 验证文件大小（限制为100MB）
        const maxSize = 100 * 1024 * 1024; // 100MB
        if (file.size > maxSize) {
            this.showMessage('文件大小不能超过100MB', 'error');
            return;
        }

        this.selectedFile = file;
        this.displayFileInfo(file);
    }

    displayFileInfo(file) {
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
        const fileInfo = this.shadowRoot.getElementById('fileInfo');
        const fileName = this.shadowRoot.getElementById('fileName');
        const fileSize = this.shadowRoot.getElementById('fileSize');

        if (fileUploadArea) fileUploadArea.style.display = 'none';
        if (fileInfo) fileInfo.style.display = 'flex';
        if (fileName) fileName.textContent = file.name;
        if (fileSize) fileSize.textContent = this.formatFileSize(file.size);
    }

    removeFile() {
        this.selectedFile = null;
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
        const fileInfo = this.shadowRoot.getElementById('fileInfo');
        const fileInput = this.shadowRoot.getElementById('modelFile');

        if (fileUploadArea) fileUploadArea.style.display = 'block';
        if (fileInfo) fileInfo.style.display = 'none';
        if (fileInput) fileInput.value = '';
    }

    formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    show() {
        this.setAttribute('show', '');
        this.resetForm();
        this.clearValidationErrors();
    }

    hide() {
        this.removeAttribute('show');
        this.clearValidationErrors();
    }

    resetForm() {
        const modelName = this.shadowRoot.getElementById('modelName');
        const modelVersion = this.shadowRoot.getElementById('modelVersion');
        const isRelatedModel = this.shadowRoot.getElementById('isRelatedModel');

        if (modelName) modelName.value = '';
        if (modelVersion) modelVersion.value = '';
        if (isRelatedModel) isRelatedModel.value = '';

        this.removeFile();
    }

    async upload() {
        // 清除之前的错误状态
        this.clearValidationErrors();
        
        const formData = this.getFormData();
        
        let hasError = false;
        
        // 验证是否关联已有模型
        if (!formData.isRelatedModel) {
            this.showFieldError('isRelatedModel', '请选择是否关联已有模型');
            hasError = true;
        }
        
        // 验证模型名称
        if (!formData.name) {
            this.showFieldError('modelName', '请输入模型名称');
            hasError = true;
        }
        
        // 验证版本号
        if (!formData.version) {
            this.showFieldError('modelVersion', '请输入版本号');
            hasError = true;
        }
        
        // 验证模型文件
        if (!this.selectedFile) {
            this.showFieldError('modelFile', '请选择模型文件');
            hasError = true;
        }
        
        if (hasError) {
            this.showMessage('请填写必填字段', 'error');
            return;
        }

        try {
            // 创建FormData对象用于文件上传
            const uploadFormData = new FormData();
            uploadFormData.append('file', this.selectedFile);
            uploadFormData.append('isRelatedModel', formData.isRelatedModel);
            uploadFormData.append('name', formData.name);
            uploadFormData.append('version', formData.version);

            // 模拟上传API调用
            const response = await this.apiCall(window.AppConfig.getApiUrl('model', 'upload'), 'POST', uploadFormData, true);
            
            if (response.code === 200) {
                this.showMessage('模型文件上传成功', 'success');
                
                // 延迟关闭窗口
                setTimeout(() => {
                    this.hide();
                    
                    this.dispatchEvent(new CustomEvent('upload-success', {
                        detail: { formData, response },
                        bubbles: true,
                        composed: true
                    }));
                }, 1000);
            } else {
                const errorMessage = response.message || '上传失败';
                this.showMessage(errorMessage, 'error');
            }
        } catch (error) {
            console.error('上传模型文件失败:', error);
            this.showMessage('上传失败，请稍后重试', 'error');
        }
    }

    getFormData() {
        const modelName = this.shadowRoot.getElementById('modelName');
        const modelVersion = this.shadowRoot.getElementById('modelVersion');
        const isRelatedModel = this.shadowRoot.getElementById('isRelatedModel');
        
        return {
            file: this.selectedFile,
            isRelatedModel: isRelatedModel?.value || '',
            name: modelName?.value || '',
            version: modelVersion?.value || ''
        };
    }

    showFieldError(fieldId, message) {
        const field = this.shadowRoot.getElementById(fieldId);
        const errorElement = this.shadowRoot.getElementById(fieldId + 'Error');
        const formGroup = field?.closest('.form-group');
        
        if (field) {
            field.classList.add('error');
        }
        if (errorElement) {
            errorElement.textContent = message;
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
        const errorMessages = this.shadowRoot.querySelectorAll('.error-message.show');
        const errorGroups = this.shadowRoot.querySelectorAll('.form-group.error');
        
        errorFields.forEach(field => field.classList.remove('error'));
        errorMessages.forEach(msg => msg.classList.remove('show'));
        errorGroups.forEach(group => group.classList.remove('error'));
    }

    async apiCall(url, method = 'GET', data = null, isFormData = false) {
        const options = {
            method: method,
            headers: window.AppConfig.getAuthHeaders(),
        };

        // 如果是FormData，不要设置Content-Type，让浏览器自动设置
        if (!isFormData && data && method !== 'GET') {
            options.headers['Content-Type'] = 'application/json';
            options.body = JSON.stringify(data);
        } else if (data) {
            options.body = data;
        }

        const response = await fetch(url, options);
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const result = await response.json();
        return result;
    }

    showMessage(message, type = 'info') {
        // 移除已存在的消息
        const existingMessage = document.querySelector('.message');
        if (existingMessage) {
            existingMessage.remove();
        }

        const messageEl = document.createElement('div');
        messageEl.className = `message ${type}`;
        messageEl.textContent = message;
        
        // 添加到body，确保是全屏居中的弹窗
        document.body.appendChild(messageEl);
        
        // 根据消息类型设置不同的显示时间
        const duration = type === 'success' ? 5000 : 3000; // 成功消息显示5秒
        
        // 自动消失
        setTimeout(() => {
            if (messageEl.parentNode) {
                messageEl.remove();
            }
        }, duration);
    }
}

customElements.define('model-upload', ModelUpload);
